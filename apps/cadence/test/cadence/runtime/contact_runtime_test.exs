defmodule Cadence.Runtime.ContactRuntimeTest do
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Contacts.{
    CombinedDownlinkRecord,
    DownlinkDiagnostic,
    DownlinkObservation,
    Path,
    RealizedContact,
    TransportBinding
  }

  alias Cadence.OperationalEvents

  alias Cadence.Persistence.Schemas.{
    CombinedDownlinkRecordRow,
    DownlinkDiagnosticRow,
    DownlinkObservationRow,
    TransportActionRequestRow,
    TransportCapabilityRecordRow,
    TransportTimerEventRow
  }

  alias Cadence.Runtime

  setup do
    mission_id =
      "mission-contact-runtime-" <> Integer.to_string(System.unique_integer([:positive]))

    on_exit(fn ->
      Runtime.stop_realized_contact(mission_id, "contact-alpha")
      Runtime.stop_realized_contact(mission_id, "contact-downlink-only")
      Runtime.stop_realized_contact(mission_id, "contact-uplink-only")
      Runtime.stop_realized_contact(mission_id, "contact-invalid")
      Runtime.stop_mission(mission_id)
    end)

    %{mission_id: mission_id}
  end

  test "starts a realized contact runtime, persists transport records, and advances transport state deterministically",
       %{mission_id: mission_id} do
    start_time = DateTime.from_unix!(1_700_030_000, :second)

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "contact-alpha",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        clock_mode: :replay,
        initial_time: start_time,
        paths: [
          Path.new(%{
            path_id: "uplink-path-alpha",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha",
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-heartbeat",
                family_key: :heartbeat_monitor,
                target_scope: :path,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          }),
          Path.new(%{
            path_id: "downlink-path-alpha",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha",
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "downlink-heartbeat",
                family_key: :heartbeat_monitor,
                target_scope: :transport,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          })
        ]
      })

    assert {:ok, _realized_contact_runtime} = Cadence.start_realized_contact(realized_contact)

    assert {:ok, contact_snapshot} =
             Cadence.realized_contact_snapshot(mission_id, realized_contact.realized_contact_id)

    assert contact_snapshot.path_count == 2
    assert contact_snapshot.clock_mode == :replay
    assert DateTime.compare(contact_snapshot.initial_time, start_time) == :eq
    assert contact_snapshot.downlink_combiner.selected_downlink_path_id == "downlink-path-alpha"
    assert contact_snapshot.downlink_combiner.active_observation_key_count == 0

    assert {:ok, uplink_snapshot} =
             Cadence.path_runtime_snapshot(
               mission_id,
               realized_contact.realized_contact_id,
               "uplink-path-alpha"
             )

    assert {:ok, downlink_snapshot} =
             Cadence.path_runtime_snapshot(
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-alpha"
             )

    assert uplink_snapshot.transport_runtime_count == 1
    assert downlink_snapshot.transport_runtime_count == 1

    [uplink_transport] = uplink_snapshot.transport_runtimes
    [downlink_transport] = downlink_snapshot.transport_runtimes

    assert uplink_transport.scope_ref == "uplink-path-alpha"
    assert uplink_transport.partition_key == "path:uplink-path-alpha"
    assert uplink_transport.state.heartbeat_count == 0
    assert uplink_transport.timer_count == 1

    assert downlink_transport.scope_ref == "downlink-heartbeat"
    assert downlink_transport.partition_key == "transport:downlink-heartbeat"
    assert downlink_transport.state.heartbeat_count == 0
    assert downlink_transport.timer_count == 1

    assert :ok =
             Cadence.advance_realized_contact_time(
               mission_id,
               realized_contact.realized_contact_id,
               DateTime.add(start_time, 60, :millisecond)
             )

    assert {:ok, advanced_uplink_snapshot} =
             Cadence.path_runtime_snapshot(
               mission_id,
               realized_contact.realized_contact_id,
               "uplink-path-alpha"
             )

    assert {:ok, advanced_downlink_snapshot} =
             Cadence.path_runtime_snapshot(
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-alpha"
             )

    [advanced_uplink_transport] = advanced_uplink_snapshot.transport_runtimes
    [advanced_downlink_transport] = advanced_downlink_snapshot.transport_runtimes

    assert advanced_uplink_transport.state.heartbeat_count == 2
    assert advanced_downlink_transport.state.heartbeat_count == 2

    assert {:ok, []} =
             Cadence.handle_path_control_input(
               mission_id,
               realized_contact.realized_contact_id,
               "uplink-path-alpha",
               "uplink-heartbeat",
               %{command: :pause},
               occurred_at: DateTime.add(start_time, 70, :millisecond)
             )

    assert :ok =
             Cadence.advance_realized_contact_time(
               mission_id,
               realized_contact.realized_contact_id,
               DateTime.add(start_time, 120, :millisecond)
             )

    assert {:ok, paused_uplink_snapshot} =
             Cadence.path_runtime_snapshot(
               mission_id,
               realized_contact.realized_contact_id,
               "uplink-path-alpha"
             )

    assert {:ok, continued_downlink_snapshot} =
             Cadence.path_runtime_snapshot(
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-alpha"
             )

    [paused_uplink_transport] = paused_uplink_snapshot.transport_runtimes
    [continued_downlink_transport] = continued_downlink_snapshot.transport_runtimes

    assert paused_uplink_transport.state.last_control_command == :pause
    refute paused_uplink_transport.state.active?
    assert paused_uplink_transport.state.heartbeat_count == 2
    assert paused_uplink_transport.timer_count == 0

    assert continued_downlink_transport.state.active?
    assert continued_downlink_transport.state.heartbeat_count == 4
    assert continued_downlink_transport.timer_count == 1

    assert {:ok, []} =
             Cadence.handle_path_transport_event(
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-alpha",
               "downlink-heartbeat",
               %{kind: :frame_received},
               occurred_at: DateTime.add(start_time, 120, :millisecond)
             )

    assert {:ok, event_downlink_snapshot} =
             Cadence.path_runtime_snapshot(
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-alpha"
             )

    [event_downlink_transport] = event_downlink_snapshot.transport_runtimes

    assert event_downlink_transport.state.last_transport_event_kind == :frame_received

    assert DateTime.compare(
             event_downlink_transport.state.last_transport_event_at,
             DateTime.add(start_time, 120, :millisecond)
           ) == :eq

    assert {:ok, []} =
             Cadence.handle_path_control_input(
               mission_id,
               realized_contact.realized_contact_id,
               "uplink-path-alpha",
               "uplink-heartbeat",
               %{command: :resume},
               occurred_at: DateTime.add(start_time, 130, :millisecond)
             )

    assert :ok =
             Cadence.advance_realized_contact_time(
               mission_id,
               realized_contact.realized_contact_id,
               DateTime.add(start_time, 160, :millisecond)
             )

    assert {:ok, resumed_uplink_snapshot} =
             Cadence.path_runtime_snapshot(
               mission_id,
               realized_contact.realized_contact_id,
               "uplink-path-alpha"
             )

    [resumed_uplink_transport] = resumed_uplink_snapshot.transport_runtimes

    assert resumed_uplink_transport.state.last_control_command == :resume
    assert resumed_uplink_transport.state.active?
    assert resumed_uplink_transport.state.heartbeat_count == 3
    assert resumed_uplink_transport.timer_count == 1

    transport_capability_rows =
      TransportCapabilityRecordRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.all()

    transport_event_kinds =
      transport_capability_rows
      |> Enum.map(& &1.event_kind)
      |> MapSet.new()

    assert transport_event_kinds ==
             MapSet.new([
               "initialized",
               "control_input_handled",
               "transport_event_handled",
               "timer_handled"
             ])

    operational_transport_events =
      OperationalEvents.list_events(mission_id,
        source_record_kind: :transport_capability_record,
        order: :asc,
        limit: length(transport_capability_rows)
      )

    assert operational_transport_events
           |> Enum.map(& &1.kind)
           |> MapSet.new() ==
             MapSet.new([
               :transport_initialized,
               :transport_control_input_handled,
               :transport_event_handled,
               :transport_timer_handled
             ])

    assert operational_transport_events
           |> Enum.map(& &1.causality.source_record_id)
           |> MapSet.new() ==
             transport_capability_rows
             |> Enum.map(& &1.transport_record_id)
             |> MapSet.new()

    transport_action_kinds =
      TransportActionRequestRow
      |> where([row], row.mission_id == ^mission_id)
      |> select([row], row.action_kind)
      |> Repo.all()
      |> MapSet.new()

    assert transport_action_kinds == MapSet.new(["schedule_timer", "cancel_timer"])

    transport_timer_rows =
      TransportTimerEventRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.all()

    transport_timer_event_kinds =
      transport_timer_rows
      |> Enum.map(& &1.event_kind)
      |> MapSet.new()

    assert transport_timer_event_kinds == MapSet.new(["scheduled", "fired", "canceled"])

    operational_timer_events =
      OperationalEvents.list_events(mission_id,
        source_record_kind: :transport_timer_event,
        order: :asc,
        limit: length(transport_timer_rows)
      )

    assert operational_timer_events
           |> Enum.map(& &1.kind)
           |> MapSet.new() ==
             MapSet.new([
               :transport_timer_scheduled,
               :transport_timer_fired,
               :transport_timer_canceled
             ])

    assert operational_timer_events
           |> Enum.map(& &1.causality.source_record_id)
           |> MapSet.new() ==
             transport_timer_rows
             |> Enum.map(& &1.timer_event_id)
             |> MapSet.new()
  end

  test "combines duplicate downlink observations and persists diagnostics", %{
    mission_id: mission_id
  } do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "contact-alpha",
        mission_id: mission_id,
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_030_500, :second),
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: [
          Path.new(%{
            path_id: "uplink-path-alpha",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha",
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-heartbeat",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          }),
          Path.new(%{
            path_id: "downlink-path-alpha",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha",
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "downlink-heartbeat-alpha",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          }),
          Path.new(%{
            path_id: "downlink-path-beta",
            direction: :downlink,
            selection_role: :contributing,
            source_endpoint_ref: "source-endpoint-alpha",
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "downlink-heartbeat-beta",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          })
        ]
      })

    assert {:ok, _realized_contact_runtime} = Cadence.start_realized_contact(realized_contact)

    assert {:ok, first_outputs} =
             Cadence.handle_path_transport_event(
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-beta",
               "downlink-heartbeat-beta",
               %{
                 kind: :downlink_observation,
                 observation_key: "frame-001",
                 payload: %{frame: 1, source: "beta"},
                 quality_score: 10
               },
               occurred_at: DateTime.from_unix!(1_700_030_510, :second),
               call_timeout: :infinity
             )

    assert Enum.any?(first_outputs, &match?(%DownlinkObservation{}, &1))
    assert Enum.any?(first_outputs, &match?(%CombinedDownlinkRecord{}, &1))

    assert Enum.any?(
             first_outputs,
             &match?(%DownlinkDiagnostic{diagnostic_kind: :accepted}, &1)
           )

    assert {:ok, second_outputs} =
             Cadence.handle_path_transport_event(
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-alpha",
               "downlink-heartbeat-alpha",
               %{
                 kind: :downlink_observation,
                 observation_key: "frame-001",
                 payload: %{frame: 1, source: "alpha"},
                 quality_score: 5
               },
               occurred_at: DateTime.from_unix!(1_700_030_515, :second),
               call_timeout: :infinity
             )

    assert Enum.any?(second_outputs, &match?(%DownlinkObservation{}, &1))
    assert Enum.any?(second_outputs, &match?(%CombinedDownlinkRecord{}, &1))

    assert Enum.any?(
             second_outputs,
             &match?(%DownlinkDiagnostic{diagnostic_kind: :selected_path_preferred}, &1)
           )

    assert {:ok, contact_snapshot} =
             Cadence.realized_contact_snapshot(mission_id, realized_contact.realized_contact_id)

    assert contact_snapshot.downlink_combiner.selected_downlink_path_id == "downlink-path-alpha"
    assert contact_snapshot.downlink_combiner.observation_count == 2
    assert contact_snapshot.downlink_combiner.combined_record_count == 2
    assert contact_snapshot.downlink_combiner.diagnostic_count == 2
    assert contact_snapshot.downlink_combiner.active_observation_key_count == 1

    assert [
             %{
               observation_key: "frame-001",
               path_id: "downlink-path-alpha",
               source_endpoint_ref: "source-endpoint-alpha"
             }
           ] = contact_snapshot.downlink_combiner.current_winners

    assert Repo.aggregate(DownlinkObservationRow, :count, :observation_id) == 2
    assert Repo.aggregate(CombinedDownlinkRecordRow, :count, :merged_record_id) == 2
    assert Repo.aggregate(DownlinkDiagnosticRow, :count, :diagnostic_id) == 2

    selected_reasons =
      CombinedDownlinkRecordRow
      |> where([row], row.mission_id == ^mission_id)
      |> select([row], {row.selected_path_id, row.selected_reason})
      |> Repo.all()

    assert {"downlink-path-beta", "accepted"} in selected_reasons
    assert {"downlink-path-alpha", "selected_path_preferred"} in selected_reasons
  end

  test "allows downlink-only realized contacts for telemetry downlink intent", %{
    mission_id: mission_id
  } do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "contact-downlink-only",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        contact_intents: [:telemetry_downlink],
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_030_100, :second),
        paths: [
          Path.new(%{
            path_id: "downlink-path-alpha",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha",
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "downlink-heartbeat",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          })
        ]
      })

    assert {:ok, _realized_contact_runtime} = Cadence.start_realized_contact(realized_contact)

    assert {:ok, contact_snapshot} =
             Cadence.realized_contact_snapshot(mission_id, realized_contact.realized_contact_id)

    assert contact_snapshot.contact_intents == ["telemetry_downlink"]
    assert contact_snapshot.path_count == 1
    assert contact_snapshot.downlink_combiner.selected_downlink_path_id == "downlink-path-alpha"
  end

  test "allows uplink-only realized contacts for command window intent", %{mission_id: mission_id} do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "contact-uplink-only",
        mission_id: mission_id,
        contact_intents: [:command_window],
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_030_100, :second),
        paths: [
          Path.new(%{
            path_id: "uplink-path-alpha",
            direction: :uplink,
            selection_role: :selected,
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-heartbeat",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          })
        ]
      })

    assert {:ok, _realized_contact_runtime} = Cadence.start_realized_contact(realized_contact)
  end

  test "rejects command window realized contacts without a selected uplink path", %{
    mission_id: mission_id
  } do
    invalid_contact =
      RealizedContact.new(%{
        realized_contact_id: "contact-invalid",
        mission_id: mission_id,
        contact_intents: [:command_window],
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_030_100, :second),
        paths: [
          Path.new(%{
            path_id: "downlink-path-alpha",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha"
          })
        ]
      })

    assert {:error, :realized_contact_requires_selected_uplink_path} =
             Cadence.start_realized_contact(invalid_contact)
  end

  test "rejects realized contacts with multiple selected uplink paths", %{mission_id: mission_id} do
    invalid_contact =
      RealizedContact.new(%{
        realized_contact_id: "contact-invalid",
        mission_id: mission_id,
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_030_100, :second),
        paths: [
          Path.new(%{
            path_id: "uplink-path-primary",
            direction: :uplink,
            selection_role: :selected,
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-heartbeat-primary",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          }),
          Path.new(%{
            path_id: "uplink-path-secondary",
            direction: :uplink,
            selection_role: :selected,
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-heartbeat-secondary",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          })
        ]
      })

    assert {:error, :realized_contact_has_multiple_selected_uplink_paths} =
             Cadence.start_realized_contact(invalid_contact)
  end
end
