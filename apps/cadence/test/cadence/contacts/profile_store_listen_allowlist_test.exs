defmodule Cadence.Contacts.ProfileStoreListenAllowlistTest do
  @moduledoc """
  #990 (DECISIONS #115, platform-eng on #993): every provider-profile write checks a listening TCP
  profile's source allowlist, so no path stores a profile the runtime would refuse. Each write
  path (`persist_provider_profile/2`, `persist_provider_profile/1`, `version_provider_profile/4`)
  refuses a listen profile with no list, a bad entry or a whole-family prefix; client mode and
  other adapters are unaffected.
  """
  use Cadence.DataCase, async: true

  alias Cadence.Contacts.{ProfileStore, ProviderProfile}
  alias Cadence.Contacts.ProfileStore.Versions

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-listen-allowlist-#{suffix}"
    mission_id = "mission-listen-allowlist-#{suffix}"
    persist_mission_scope(organization_id, mission_id)
    %{organization_id: organization_id, mission_id: mission_id}
  end

  @cases [
    {nil, :peer_addresses_missing},
    {[], :peer_addresses_missing},
    {["not-an-address"], :peer_addresses_invalid},
    {["0.0.0.0/0"], :peer_addresses_too_broad},
    {["::/0"], :peer_addresses_too_broad},
    {["::ffff:0:0/96"], :peer_addresses_too_broad}
  ]

  test "persist_provider_profile/2 refuses a listen profile without a usable list", c do
    for {list, reason} <- @cases do
      assert {:error, ^reason} =
               ProfileStore.persist_provider_profile(c.organization_id, profile(c, list))
    end

    assert {:ok, _stored} =
             ProfileStore.persist_provider_profile(c.organization_id, profile(c, ["10.0.0.0/8"]))
  end

  test "persist_provider_profile/1 refuses it too", c do
    for {list, reason} <- @cases do
      unscoped = %{profile(c, list) | organization_id: c.organization_id}
      assert {:error, ^reason} = ProfileStore.persist_provider_profile(unscoped)
    end
  end

  test "version_provider_profile/4 refuses a version that drops or breaks the list", c do
    {:ok, stored} =
      ProfileStore.persist_provider_profile(c.organization_id, profile(c, ["10.0.0.0/8"]))

    for {list, reason} <- @cases do
      configuration =
        if list,
          do: %{"mode" => "listen", "expected_peer_addresses" => list},
          else: %{"mode" => "listen"}

      assert {:error, ^reason} =
               ProfileStore.version_provider_profile(
                 c.organization_id,
                 c.mission_id,
                 stored.provider_profile_id,
                 %{configuration: configuration}
               )
    end
  end

  test "activating a stored listen profile in a new version requires an allowlist", c do
    inactive = %{profile(c, nil) | lifecycle_state: :deleted}

    assert {:ok, %ProviderProfile{lifecycle_state: :deleted} = stored} =
             ProfileStore.persist_provider_profile(c.organization_id, inactive)

    assert {:ok, %ProviderProfile{lifecycle_state: :active} = next} =
             Versions.next_provider_profile(stored, %{})

    assert {:error, :peer_addresses_missing} =
             ProfileStore.persist_provider_profile(c.organization_id, next)

    assert {:error, :contact_provider_profile_not_found} =
             ProfileStore.fetch_provider_profile_version(
               c.organization_id,
               c.mission_id,
               stored.provider_profile_id,
               next.version
             )
  end

  test "client mode and other adapters need no list", c do
    connect = %{profile(c, nil) | configuration: %{"mode" => "connect"}}
    assert :ok = ProfileStore.listen_allowlist(connect)

    other = %{profile(c, nil) | adapter_key: :websocket}
    assert :ok = ProfileStore.listen_allowlist(other)
  end

  defp profile(c, list) do
    configuration =
      if list,
        do: %{"mode" => "listen", "expected_peer_addresses" => list},
        else: %{"mode" => "listen"}

    ProviderProfile.new(%{
      provider_profile_id: "listen-#{System.unique_integer([:positive])}",
      mission_id: c.mission_id,
      adapter_key: :tcp_socket,
      configuration: configuration
    })
  end
end
