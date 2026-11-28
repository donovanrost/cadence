defmodule Cadence.Contacts.ListenerRefusalAttentionTest do
  @moduledoc """
  ux U50 `listener_refusal`, through real contacts on one shared listener (#87): a connection
  no pass expects raises one item per open pass on the listener; the pass's own connection
  resolves its item `accepted`; a pass that ends with its window open records the summary at LOS
  and reads `ended`; second connections are counted live and after LOS.
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.SharedListenerFixtures

  alias Cadence.Contacts

  alias Cadence.Contacts.{
    ContactSettlement,
    ContactStore,
    ListenerRefusalAttention,
    ProfileStore,
    ProviderProfile
  }

  alias Cadence.Control.Contacts, as: ControlContacts

  setup do
    ctx = fixture!()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    port = free_port()
    alpha_endpoint = endpoint!(ctx, "alpha", 1)
    bravo_endpoint = endpoint!(ctx, "bravo", 2)

    alpha =
      schedule!(
        ctx,
        alpha_endpoint,
        "alpha",
        DateTime.add(now, -60),
        DateTime.add(now, 600),
        port
      )

    bravo =
      schedule!(
        ctx,
        bravo_endpoint,
        "bravo",
        DateTime.add(now, -30),
        DateTime.add(now, 600),
        port
      )

    assert {:ok, %{errors: []}} = Contacts.reconcile(ctx.mission_id, now)

    on_exit(fn ->
      for pass <- [alpha, bravo],
          do: Cadence.Runtime.terminate_realized_contact(ctx.mission_id, run_id(pass))
    end)

    Map.merge(ctx, %{alpha: alpha, bravo: bravo, port: port, since: DateTime.add(now, -1)})
  end

  # #990: the item says who sets the listener's allowlist, so the fix line can name who acts.
  test "an item names the allowlist's source and transport", ctx do
    for {origin, source} <- [{"provider_managed", "provider"}, {"direct", "transport"}] do
      {:ok, _profile} =
        ProfileStore.persist_provider_profile(
          ctx.organization_id,
          ProviderProfile.new(%{
            provider_profile_id: ctx.profile_id,
            mission_id: ctx.mission_id,
            adapter_key: :tcp_socket,
            version: next_profile_version(ctx),
            configuration: %{"mode" => "listen", "expected_peer_addresses" => ["127.0.0.1/32"]},
            metadata: %{
              "display_name" => "Shared downlink",
              "transport_origin" => origin,
              "materialized_from_transport_id" => "transport-#{origin}"
            }
          })
        )

      _stranger = connect!(ctx.port, frame(9))
      [item | _rest] = eventually_items(ctx, 2)

      assert %{allowlist_source: ^source, provider_profile_name: "Shared downlink"} = item
      assert item.transport_id == "transport-#{origin}"
    end
  end

  test "a refused connection raises an item for every open pass on the listener", ctx do
    assert ListenerRefusalAttention.items(ctx.organization_id, ctx.mission_id) == []

    _stranger = connect!(ctx.port, frame(9))
    items = eventually_items(ctx, 2)

    alpha = Enum.find(items, &(&1.realized_contact_id == run_id(ctx.alpha)))
    bravo = Enum.find(items, &(&1.realized_contact_id == run_id(ctx.bravo)))

    assert %{
             source: "listener_refusal",
             state: "open",
             refused_count: 1,
             connected: false,
             p1: true,
             own_quiet_since: nil,
             provider_profile_id: profile,
             last_refusal: %{reason: "unregistered_scid", scid: 9}
           } = alpha

    assert profile == ctx.profile_id
    assert alpha.id == "#{run_id(ctx.alpha)}:#{ctx.profile_id}"
    assert alpha.shared_with == [run_id(ctx.bravo)]
    assert bravo.shared_with == [run_id(ctx.alpha)]
    assert alpha.contact_id == ctx.alpha.scheduled_contact_id

    assert %{open: 2, acknowledged: 0} =
             ListenerRefusalAttention.counts(ctx.organization_id, ctx.mission_id)
  end

  test "the pass's own connection resolves its item accepted; the other stays open", ctx do
    _stranger = connect!(ctx.port, frame(9))
    eventually_items(ctx, 2)

    _alpha_peer = connect!(ctx.port, frame(1))
    [open] = eventually_items(ctx, 1)
    assert open.realized_contact_id == run_id(ctx.bravo)

    alpha_id = "#{run_id(ctx.alpha)}:#{ctx.profile_id}"

    assert [%{id: ^alpha_id, action: "accepted", resolved_by: "system"}] =
             ListenerRefusalAttention.resolved_since(
               ctx.organization_id,
               ctx.mission_id,
               ctx.since
             )
  end

  test "a pass that ends with its window open reads ended, and keeps its counts", ctx do
    _alpha_peer = connect!(ctx.port, frame(1))
    _duplicate = connect!(ctx.port, frame(1))
    _stranger = connect!(ctx.port, frame(9))
    # Every pass on the listener hears the refusal: alpha's row too, P2 while it's connected.
    items = eventually_items(ctx, 2)

    assert %{connected: true, p1: false} =
             Enum.find(items, &(&1.realized_contact_id == run_id(ctx.alpha)))

    alpha = run_id(ctx.alpha)
    bravo = run_id(ctx.bravo)

    assert eventually(fn ->
             ListenerRefusalAttention.second_connections_refused(
               ctx.organization_id,
               ctx.mission_id,
               alpha
             ) == 1
           end)

    # Bravo's pass ends (as its settler does at LOS): the summary is recorded, then it stops.
    {:ok, contact} = ContactStore.fetch_realized(ctx.organization_id, ctx.mission_id, bravo)

    document =
      ListenerRefusalAttention.settlement_document(
        ControlContacts.listener_refusals(ctx.mission_id, bravo),
        DateTime.utc_now()
      )

    :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, bravo)
    assert {:ok, _} = ContactSettlement.record(contact, :settled, %{}, :ok, document)

    assert [%{realized_contact_id: ^alpha}] =
             ListenerRefusalAttention.items(ctx.organization_id, ctx.mission_id)

    bravo_id = "#{bravo}:#{ctx.profile_id}"

    assert [%{id: ^bravo_id, action: "ended"}] =
             ctx.organization_id
             |> ListenerRefusalAttention.resolved_since(ctx.mission_id, ctx.since)
             |> Enum.filter(&(&1.realized_contact_id == bravo))

    {:ok, settled} = ContactStore.fetch_realized(ctx.organization_id, ctx.mission_id, bravo)

    assert %{"refused_count" => 1, "last" => %{"reason" => "unregistered_scid", "scid" => 9}} =
             settled.metadata["listener_refusal"][ctx.profile_id]

    # Alpha's count is read live; bravo's from its record; a contact with neither is nil.
    assert ListenerRefusalAttention.second_connections_refused(
             ctx.organization_id,
             ctx.mission_id,
             bravo
           ) == 0

    assert ListenerRefusalAttention.second_connections_refused(
             ctx.organization_id,
             ctx.mission_id,
             "no-such-contact"
           ) == nil
  end

  # The item reads the profile's latest version, so each persisted case must be the newest one.
  defp next_profile_version(ctx) do
    case ProfileStore.fetch_provider_profile(ctx.organization_id, ctx.mission_id, ctx.profile_id) do
      {:ok, profile} -> profile.version + 1
      {:error, :contact_provider_profile_not_found} -> 1
    end
  end

  defp eventually_items(ctx, count) do
    assert eventually(fn ->
             length(ListenerRefusalAttention.items(ctx.organization_id, ctx.mission_id)) ==
               count
           end)

    ListenerRefusalAttention.items(ctx.organization_id, ctx.mission_id)
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(50)
      eventually(fun, attempts - 1)
    end
  end
end
