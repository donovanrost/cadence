defmodule Cadence.Contacts.ContactStartTest do
  @moduledoc """
  ux U45: a pass whose runtime can't start is retried while its window is open and shown on Now,
  never lost silently. P9CS night (11-14): EARENDIL-006's pass on the Santiago listen profile held
  :42105 until 00:34:18Z, so 001's overlapping pass (from 00:33:52Z) couldn't open its listener;
  the scheduler never retried it, and only the queued command's dispatch started it at 00:35:01Z.
  Four earlier passes overlapping this way were lost entirely.
  """
  use Cadence.RuntimeCase, async: false

  @moduletag :ingest_journal_matrix

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Contacts
  alias Cadence.Contacts.{ContactStartAttention, ContactStore, ListenerOverlap, Scheduler}
  alias Cadence.Contacts.{Path, ProviderBinding, ScheduledContact}
  alias Cadence.Reads.PassListenerOverlap
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  @frame_size 10
  @apid 42

  setup do
    settlement = Application.get_env(:cadence, :contact_settlement)
    Application.put_env(:cadence, :contact_settlement, deadline_ms: 2_000)
    on_exit(fn -> restore(:contact_settlement, settlement) end)

    fixture!()
  end

  test "an overlapping pass on the same listen profile starts once the earlier pass ends", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    port = free_port()
    first = schedule!(ctx, "first", DateTime.add(now, -60), DateTime.add(now, 60), port)
    second = schedule!(ctx, "second", DateTime.add(now, -30), DateTime.add(now, 600), port)

    assert {:ok, summary} = Contacts.reconcile(ctx.mission_id, now)
    first_run = run_id(first)
    second_run = run_id(second)
    assert summary.realized_scheduled_contact_ids == [first_run]
    second_id = second.scheduled_contact_id

    # Tonight's error, exactly: the listener is still the first pass's.
    assert [
             %{
               kind: :scheduled_contact_realization,
               scheduled_contact_id: ^second_id,
               reason:
                 {:shutdown,
                  {:failed_to_start_child, Cadence.Runtime.PathCoordinator,
                   {:tcp_provider_listen_failed, _profile, :eaddrinuse}}}
             }
           ] = summary.errors

    # The second pass is realized but not running: its failure is kept, and Now shows it.
    assert {:ok, %{lifecycle_state: :defined} = defined} =
             ContactStore.fetch_realized(ctx.mission_id, second_run)

    assert %{"reason" => "listener_in_use", "attempts" => 1} = defined.metadata["start_failure"]

    assert [
             %{
               id: ^second_run,
               source: "contact_start",
               conflict: "not_started",
               reason: "listener_in_use",
               retry: "automatic",
               attempts: 1,
               holder: %{realized_contact_id: ^first_run}
             }
           ] = ContactStartAttention.items(ctx.organization_id, ctx.mission_id)

    # Every reconcile retries it while the listener is still held.
    assert {:ok, %{restarted_realized_contact_ids: []}} =
             Contacts.reconcile(ctx.mission_id, DateTime.add(now, 5))

    assert [%{attempts: 2}] = ContactStartAttention.items(ctx.organization_id, ctx.mission_id)

    # The first pass ends; when its runtime stops (listener closed) the settler wakes the
    # mission's scheduler, which starts the second pass at once, with no command queued.
    assert {:ok, %{completed_realized_contact_ids: [^first_run]}} =
             Contacts.reconcile(ctx.mission_id, DateTime.add(now, 61))

    assert_eventually(fn ->
      not Cadence.Runtime.realized_contact_running?(ctx.mission_id, first_run) and
        Cadence.Runtime.realized_contact_running?(ctx.mission_id, second_run)
    end)

    assert Cadence.Runtime.realized_contact_running?(ctx.mission_id, second_run)

    assert {:ok, %{lifecycle_state: :active} = started} =
             ContactStore.fetch_realized(ctx.mission_id, second_run)

    # api U46: the scheduler started it, and a later start (a release reaching the running pass)
    # doesn't rename the starter.
    scheduler = %{"kind" => "system", "id" => "contact_scheduler"}
    assert started.metadata["started_by"] == scheduler

    assert {:ok, _pid} =
             Contacts.start_realized_contact(
               ctx.organization_id,
               ctx.mission_id,
               second_run,
               %{"kind" => "user", "id" => "op"}
             )

    assert {:ok, %{metadata: %{"started_by" => ^scheduler}}} =
             ContactStore.fetch_realized(ctx.mission_id, second_run)

    assert [] = ContactStartAttention.items(ctx.organization_id, ctx.mission_id)

    assert [%{id: ^second_run, action: "started", resolved_by: %{"kind" => "system"}}] =
             ContactStartAttention.resolved_since(
               ctx.organization_id,
               ctx.mission_id,
               DateTime.add(DateTime.utc_now(), -60)
             )

    :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, second_run)
  end

  test "a pass inside another pass's window that never starts is missed until marked seen", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    port = free_port()
    long = schedule!(ctx, "long", DateTime.add(now, -600), DateTime.add(now, 600), port)
    inner = schedule!(ctx, "inner", DateTime.add(now, -300), DateTime.add(now, -120), port)

    assert {:ok, _summary} = Contacts.reconcile(ctx.mission_id, DateTime.add(now, -200))
    inner_run = run_id(inner)
    long_run = run_id(long)

    # Its window has ended: no more retries, and the item says it was missed.
    assert {:ok, %{restarted_realized_contact_ids: []}} = Contacts.reconcile(ctx.mission_id, now)

    assert [
             %{
               id: ^inner_run,
               conflict: "missed",
               reason: "listener_in_use",
               holder: %{realized_contact_id: ^long_run}
             }
           ] = ContactStartAttention.items(ctx.organization_id, ctx.mission_id)

    scope = TelemetryDecomFixtures.user_scope(ctx.organization_id, "op")

    assert {:ok, %{state: "resolved", acknowledged_by: %{"kind" => "user"}}} =
             ContactStartAttention.acknowledge(scope, ctx.mission_id, inner_run)

    assert [] = ContactStartAttention.items(ctx.organization_id, ctx.mission_id)

    assert {:error, :attention_item_not_found} =
             ContactStartAttention.acknowledge(scope, ctx.mission_id, inner_run)

    assert [%{id: ^inner_run, action: "acknowledged"}] =
             ContactStartAttention.resolved_since(
               ctx.organization_id,
               ctx.mission_id,
               DateTime.add(DateTime.utc_now(), -60)
             )

    :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, long_run)
  end

  test "a pass still in its window can't be marked seen; Cadence is still retrying it", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    port = free_port()
    first = schedule!(ctx, "first", DateTime.add(now, -60), DateTime.add(now, 600), port)
    second = schedule!(ctx, "second", DateTime.add(now, -30), DateTime.add(now, 600), port)

    assert {:ok, _summary} = Contacts.reconcile(ctx.mission_id, now)
    scope = TelemetryDecomFixtures.user_scope(ctx.organization_id, "op")

    assert {:error, :contact_start_not_missed} =
             ContactStartAttention.acknowledge(scope, ctx.mission_id, run_id(second))

    :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, run_id(first))
  end

  test "retry_starts reconciles the mission at once, starting a pass the listener blocked", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    port = free_port()
    first = schedule!(ctx, "first", DateTime.add(now, -60), DateTime.add(now, 600), port)
    second = schedule!(ctx, "second", DateTime.add(now, -30), DateTime.add(now, 600), port)
    assert {:ok, _summary} = Contacts.reconcile(ctx.mission_id, now)
    first_run = run_id(first)
    second_run = run_id(second)

    # The first pass ends without any notification: no reconcile runs, so nothing retries yet.
    {:ok, first_contact} = ContactStore.fetch_realized(ctx.mission_id, first_run)
    {:ok, _} = ContactStore.update_realized_lifecycle(first_contact, :completed, %{})
    :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, first_run)
    Process.sleep(300)
    refute Cadence.Runtime.realized_contact_running?(ctx.mission_id, second_run)

    scheduler =
      start_supervised!(
        {Scheduler,
         name: nil, mission_id: ctx.mission_id, run_on_boot?: false, auto_schedule?: true}
      )

    # Another mission's wake is ignored; this mission's starts the pass.
    assert :ok = Scheduler.retry_starts("another-mission", server: scheduler)
    assert :ok = Scheduler.retry_starts(ctx.mission_id, server: scheduler)

    assert_eventually(fn ->
      Cadence.Runtime.realized_contact_running?(ctx.mission_id, second_run)
    end)

    :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, second_run)
  end

  defp run_id(%ScheduledContact{scheduled_contact_id: id}), do: id <> "_run"

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp fixture! do
    organization_id = "org-start-#{System.unique_integer([:positive])}"
    suffix = Integer.to_string(System.unique_integer([:positive]))
    mission_id = "mission-start-" <> suffix
    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-start-" <> suffix,
        mission_id: mission_id,
        display_name: "SC start"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    {:ok, endpoint} =
      Cadence.SourceEndpointFixtures.persist(
        organization_id,
        SourceEndpoint.new(%{
          source_endpoint_id: "endpoint-start-" <> suffix,
          mission_id: mission_id,
          spacecraft_id: spacecraft.spacecraft_id,
          source_ref: "provider/tcp"
        })
      )

    packet =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-start-" <> suffix,
        packet_name: "TMHK",
        apid: @apid,
        version: 1,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    {:ok, binding_set} =
      Cadence.Governance.persist_binding_set(
        organization_id,
        BindingSet.new(%{
          mission_id: mission_id,
          binding_set_id: "start-basis-" <> suffix,
          version: 1,
          rules: [
            BindingRule.new(%{
              binding_rule_id: "start-telemetry-rule-" <> suffix,
              handler_key: :definition_bound_telemetry,
              packet_kind: :space_packet,
              apid: @apid,
              priority: 10,
              handler_configuration: packet
            })
          ]
        })
      )

    {:ok, _activation} =
      Cadence.ActivationFixtures.activate_binding_set(
        organization_id,
        mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        activated_by: %{"service_identity_id" => "svc-test"}
      )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      endpoint_id: endpoint.source_endpoint_id,
      profile_id: "provider-profile-" <> suffix
    }
  end

  # Every pass uses the same provider profile, as materialized contacts do: one provider binding
  # id and one fixed listen port.
  # #361 (domain's condition 5): planning's flag and the runtime's refusal agree on one fixture,
  # the same listener and the same loser, and the loser binds as the earlier pass lets go.
  test "the booking-time overlap flag names the pass the runtime refuses, for the seconds it waits",
       ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    port = free_port()
    first = schedule!(ctx, "first", DateTime.add(now, -60), DateTime.add(now, 60), port)
    second = schedule!(ctx, "second", DateTime.add(now, -30), DateTime.add(now, 600), port)

    flags = ListenerOverlap.for_scheduled([first, second])
    first_id = first.scheduled_contact_id

    assert %{with: ^first_id, loses: "this", seconds: 90, direction: :downlink} =
             flags[second.scheduled_contact_id]

    assert %{loses: "other"} = flags[first_id]
    assert flags[second.scheduled_contact_id].listener.port == port

    # The read's wire shape (Reads.Passes rows): this mission's pass named, the listener only for
    # Technical details, state booked.
    wire =
      PassListenerOverlap.for_rows(ctx.organization_id, ctx.mission_id, [
        %{starts_at: second.starts_at, ends_at: second.ends_at}
      ])

    assert %{
             seconds: 90,
             loses: "this",
             direction: "downlink",
             count: 1,
             listener: %{port: ^port},
             with: %{state: "booked", starts_at: first_start, spacecraft: %{} = spacecraft}
           } = wire[second.scheduled_contact_id]

    assert first_start == first.starts_at
    assert Map.has_key?(spacecraft, :id) and Map.has_key?(spacecraft, :name)

    # The runtime: the flagged loser is the one refused with listener_in_use…
    assert {:ok, _summary} = Contacts.reconcile(ctx.mission_id, now)
    second_run = run_id(second)

    assert {:ok, %{metadata: %{"start_failure" => %{"reason" => "listener_in_use"}}}} =
             ContactStore.fetch_realized(ctx.mission_id, second_run)

    # …and it binds once the earlier pass ends (+60 s, so 90 s after its own start).
    assert {:ok, _} = Contacts.reconcile(ctx.mission_id, DateTime.add(now, 61))

    assert_eventually(fn ->
      Cadence.Runtime.realized_contact_running?(ctx.mission_id, second_run)
    end)
  end

  defp schedule!(ctx, name, starts_at, ends_at, port) do
    id = "#{name}-#{System.unique_integer([:positive])}"

    contact =
      ScheduledContact.new(%{
        scheduled_contact_id: id,
        mission_id: ctx.mission_id,
        source_endpoint_refs: [ctx.endpoint_id],
        starts_at: starts_at,
        ends_at: ends_at,
        paths: [
          Path.new(%{
            path_id: "downlink-#{id}",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: ctx.endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: ctx.profile_id,
                adapter_key: :tcp_socket,
                configuration: %{
                  mode: :listen,
                  port: port,
                  ingress_protocol_family: :tm,
                  frame_size: @frame_size,
                  ingress_metadata: %{frame_size: @frame_size, ocf_length: 0}
                }
              })
            ]
          })
        ]
      })

    {:ok, scheduled} = Contacts.persist_scheduled_contact(ctx.organization_id, contact)
    scheduled
  end

  defp assert_eventually(fun, attempts \\ 200)
  defp assert_eventually(_fun, 0), do: flunk("condition was not satisfied in time")

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp restore(key, nil), do: Application.delete_env(:cadence, key)
  defp restore(key, value), do: Application.put_env(:cadence, key, value)
end
