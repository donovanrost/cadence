defmodule Cadence.Contacts.ProfileStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{ProfileStore, ProviderProfile, TransportProfile}

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-profile-store-#{suffix}"
    mission_id = "mission-profile-store-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "persists, versions, lists, and tombstones provider profiles", context do
    profile =
      ProviderProfile.new(%{
        provider_profile_id: "provider-1",
        mission_id: context.mission_id,
        adapter_key: :tcp_socket,
        configuration: %{"mode" => "listen"},
        metadata: %{"owner" => "ops"}
      })

    assert {:ok, %ProviderProfile{version: 1} = persisted} =
             ProfileStore.persist_provider_profile(context.organization_id, profile)

    assert persisted.organization_id == context.organization_id

    assert {:ok, %ProviderProfile{version: 2} = versioned} =
             ProfileStore.version_provider_profile(
               context.organization_id,
               context.mission_id,
               profile.provider_profile_id,
               %{configuration: %{"mode" => "connect"}, metadata: %{"reviewed" => true}}
             )

    assert versioned.configuration == %{"mode" => "connect"}
    assert versioned.metadata == %{"owner" => "ops", "reviewed" => true}

    assert Enum.map(
             ProfileStore.list_provider_profile_versions(
               context.organization_id,
               context.mission_id,
               profile.provider_profile_id
             ),
             & &1.version
           ) == [2, 1]

    assert {:ok, %ProviderProfile{version: 3, lifecycle_state: :deleted}} =
             ProfileStore.delete_provider_profile(
               context.organization_id,
               context.mission_id,
               profile.provider_profile_id,
               %{"reason" => "retired"}
             )

    assert {:error, :contact_provider_profile_not_found} =
             ProfileStore.fetch_provider_profile(
               context.organization_id,
               context.mission_id,
               profile.provider_profile_id
             )

    assert {:ok, %ProviderProfile{version: 1}} =
             ProfileStore.fetch_provider_profile_version(
               context.organization_id,
               context.mission_id,
               profile.provider_profile_id,
               1
             )
  end

  test "persists, versions, lists, and tombstones transport profiles", context do
    profile =
      TransportProfile.new(%{
        transport_profile_id: "transport-1",
        mission_id: context.mission_id,
        family_key: :uplink_gateway,
        target_scope: :path,
        configuration: %{"route" => "primary"}
      })

    assert {:ok, %TransportProfile{version: 1}} =
             ProfileStore.persist_transport_profile(context.organization_id, profile)

    assert {:ok, %TransportProfile{version: 2} = versioned} =
             ProfileStore.version_transport_profile(
               context.organization_id,
               context.mission_id,
               profile.transport_profile_id,
               %{configuration: %{"route" => "secondary"}}
             )

    assert versioned.configuration == %{"route" => "secondary"}

    assert [%TransportProfile{version: 2}] =
             ProfileStore.list_transport_profiles(context.organization_id, context.mission_id)

    assert {:ok, %TransportProfile{version: 3, lifecycle_state: :deleted}} =
             ProfileStore.delete_transport_profile(
               context.organization_id,
               context.mission_id,
               profile.transport_profile_id
             )

    assert ProfileStore.list_transport_profiles(context.organization_id, context.mission_id) == []

    assert Enum.map(
             ProfileStore.list_transport_profile_versions(
               context.organization_id,
               context.mission_id,
               profile.transport_profile_id
             ),
             & &1.version
           ) == [3, 2, 1]
  end
end
