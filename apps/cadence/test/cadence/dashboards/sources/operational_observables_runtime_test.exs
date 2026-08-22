defmodule Cadence.Dashboards.Sources.OperationalObservablesRuntimeTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.Sources.OperationalObservablesFixtures

  alias Cadence.Dashboards.{Frame, SourceResult}
  alias Cadence.Dashboards.Sources.OperationalObservables

  test "resolves replay managed runtime activity with operational event evidence" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    action_event =
      managed_runtime_event(
        "managed-action-1",
        :managed_action_request,
        :managed_action_requested,
        ~U[2026-06-17 12:01:30Z],
        action_kind: :schedule_timer,
        runtime_fact_id: "action-request-1",
        request_document: %{delay_ms: 5_000, timer_key: "flush"}
      )

    timer_event =
      managed_runtime_event(
        "managed-timer-1",
        :managed_timer_event,
        :managed_timer_fired,
        ~U[2026-06-17 12:02:30Z],
        timer_key: "flush",
        runtime_fact_id: "timer-event-1"
      )

    managed_runtime_events_fun = fn organization_id, mission_id, opts ->
      send(self(), {:managed_runtime_events, organization_id, mission_id, opts})
      [timer_event, action_event]
    end

    result =
      source_request()
      |> Map.put(:observables, ["runtime.managed_activity"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> Map.put(:scope_context, %{
        primary: %{kind: :mission, mode: :one, ids: ["mission-1"]}
      })
      |> OperationalObservables.resolve(
        managed_runtime_events_fun: managed_runtime_events_fun,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :managed_runtime_activity_history
    assert frame.meta.supported_capability == :managed_runtime_activity_history
    assert frame.meta.product_family == :runtime_managed
    assert frame.meta.state_color_policy == :managed_runtime_activity
    assert frame.meta.observable_id == "runtime.managed_activity"
    assert frame.meta.realm == :replay
    assert frame.meta.dataset == "operational_observables_replay"
    assert frame.meta.replay_run_id == "replay-run-1"
    assert frame.meta.runtime_fact_ids == ["action-request-1", "timer-event-1"]
    assert frame.meta.returned_points == 2

    assert field_values(frame, "source_event_id") == ["managed-action-1", "managed-timer-1"]

    assert field_values(frame, "runtime_fact_kind") == [
             :managed_action_request,
             :managed_timer_event
           ]

    assert field_values(frame, "runtime_fact_id") == ["action-request-1", "timer-event-1"]
    assert field_values(frame, "state") == [:managed_action_requested, :managed_timer_fired]
    assert field_values(frame, "timer_key") == [nil, "flush"]
    assert field_values(frame, "action_kind") == [:schedule_timer, nil]

    assert field_values(frame, "action_request_document_json") == [
             ~s({"delay_ms":5000,"timer_key":"flush"}),
             nil
           ]

    assert "managed-action-1" in operational_event_link_ids(frame)
    assert "managed-timer-1" in operational_event_link_ids(frame)

    assert evidence_identities(frame) == [
             {:operational_event, "managed-action-1"},
             {:operational_event, "managed-timer-1"}
           ]

    assert_received {:managed_runtime_events, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time
  end

  test "resolves replay managed capability record lifecycle with state snapshot evidence" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    initialized_event =
      managed_runtime_event(
        "managed-capability-initialized-1",
        :managed_capability_record,
        :managed_capability_initialized,
        ~U[2026-06-17 12:00:30Z],
        runtime_fact_id: "capability-record-initialized-1",
        event_kind: :initialized,
        emitted_record_kinds: [],
        emitted_record_count: 0,
        action_request_count: 0,
        state_snapshot: %{active?: true, heartbeat_count: 0}
      )

    record_event =
      managed_runtime_event(
        "managed-capability-record-handled-1",
        :managed_capability_record,
        :managed_capability_record_handled,
        ~U[2026-06-17 12:01:30Z],
        runtime_fact_id: "capability-record-handled-1",
        event_kind: :record_handled,
        emitted_record_kinds: [:limit_state, :derived_metric],
        emitted_record_count: 2,
        action_request_count: 1,
        state_snapshot: %{active?: true, heartbeat_count: 1},
        record_metadata: %{
          emitted_record_refs: ["limit-state-1", "derived-metric-1"],
          action_request_ids: ["managed-action-request-2"]
        }
      )

    timer_event =
      managed_runtime_event(
        "managed-capability-timer-handled-1",
        :managed_capability_record,
        :managed_capability_timer_handled,
        ~U[2026-06-17 12:02:30Z],
        runtime_fact_id: "capability-record-timer-handled-1",
        event_kind: :timer_handled,
        timer_key: "flush",
        emitted_record_kinds: [:flush_summary],
        emitted_record_count: 1,
        action_request_count: 0,
        state_snapshot: %{active?: false, heartbeat_count: 2}
      )

    result =
      source_request()
      |> Map.put(:observables, ["runtime.managed_activity"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> OperationalObservables.resolve(
        managed_runtime_events_fun: fn organization_id, mission_id, opts ->
          send(self(), {:managed_capability_events, organization_id, mission_id, opts})
          [timer_event, initialized_event, record_event]
        end,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert frame.meta.supported_capability == :managed_runtime_activity_history

    assert frame.meta.runtime_fact_ids == [
             "capability-record-initialized-1",
             "capability-record-handled-1",
             "capability-record-timer-handled-1"
           ]

    assert field_values(frame, "source_event_id") == [
             "managed-capability-initialized-1",
             "managed-capability-record-handled-1",
             "managed-capability-timer-handled-1"
           ]

    assert field_values(frame, "runtime_fact_kind") == [
             :managed_capability_record,
             :managed_capability_record,
             :managed_capability_record
           ]

    assert field_values(frame, "record_event_kind") == [
             :initialized,
             :record_handled,
             :timer_handled
           ]

    assert field_values(frame, "emitted_record_kinds") == [
             "",
             "derived_metric,limit_state",
             "flush_summary"
           ]

    assert field_values(frame, "emitted_record_count") == [0, 2, 1]
    assert field_values(frame, "action_request_count") == [0, 1, 0]
    assert field_values(frame, "timer_key") == [nil, nil, "flush"]

    assert field_values(frame, "state_snapshot_json") == [
             ~s({"active?":true,"heartbeat_count":0}),
             ~s({"active?":true,"heartbeat_count":1}),
             ~s({"active?":false,"heartbeat_count":2})
           ]

    assert field_values(frame, "record_metadata_json") == [
             nil,
             ~s({"action_request_ids":["managed-action-request-2"],"emitted_record_refs":["limit-state-1","derived-metric-1"]}),
             nil
           ]

    assert evidence_identities(frame) == [
             {:operational_event, "managed-capability-initialized-1"},
             {:operational_event, "managed-capability-record-handled-1"},
             {:operational_event, "managed-capability-timer-handled-1"}
           ]

    assert_received {:managed_capability_events, "org-1", "mission-1", opts}
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time
  end

  test "resolves replay transport runtime activity with capability action and timer evidence" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    record_event =
      transport_runtime_event(
        "transport-capability-record-event-1",
        :transport_capability_record,
        :transport_control_input_handled,
        ~U[2026-06-17 12:01:00Z],
        runtime_fact_id: "transport-record-1",
        event_kind: :control_input_handled,
        emitted_record_kinds: [:uplink_frame],
        emitted_record_count: 1,
        action_request_count: 1,
        state_snapshot: %{cop1_state: "active", vcid: 7},
        record_metadata: %{
          emitted_record_refs: ["uplink-frame-1"],
          action_request_ids: ["transport-action-request-1"]
        }
      )

    action_event =
      transport_runtime_event(
        "transport-action-request-event-1",
        :transport_action_request,
        :transport_action_requested,
        ~U[2026-06-17 12:01:30Z],
        runtime_fact_id: "transport-action-request-1",
        action_kind: :release_command,
        command_release_attempt_id: "release-attempt-1",
        command_request_id: "command-request-1",
        command_name: "NOOP",
        signal_phase: :start,
        source_endpoint_ref: "endpoint-alpha",
        request_document: %{command_request_id: "command-request-1", frame_count: 1},
        action_metadata: %{release_attempt_id: "release-attempt-1"}
      )

    timer_event =
      transport_runtime_event(
        "transport-timer-event-1",
        :transport_timer_event,
        :transport_timer_fired,
        ~U[2026-06-17 12:02:00Z],
        runtime_fact_id: "transport-timer-1",
        event_kind: :fired,
        timer_key: "cop1_timeout",
        timer_metadata: %{action_request_id: "transport-action-request-1"}
      )

    satisfied_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-satisfied",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :satisfied,
      matched_record_kind: :transport_action_request,
      matched_record_id: "transport-action-request-1",
      matched_at: ~U[2026-06-17 12:01:45Z]
    }

    failed_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-failed",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :failed,
      matched_record_kind: :transport_action_request,
      matched_record_id: "transport-action-request-1",
      matched_at: ~U[2026-06-17 12:01:50Z],
      failure_reason: "failure_criteria_matched"
    }

    telemetry_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-telemetry-satisfied",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :satisfied,
      matched_record_kind: :telemetry_sample,
      matched_record_id: "verifier-telemetry-sample-1",
      matched_at: ~U[2026-06-17 12:01:55Z]
    }

    capability_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-capability-satisfied",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :satisfied,
      matched_record_kind: :transport_capability_record,
      matched_record_id: "transport-record-1",
      matched_at: ~U[2026-06-17 12:01:58Z]
    }

    timed_out_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-timed-out",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :timed_out,
      matched_at: ~U[2026-06-17 12:02:30Z],
      failure_reason: "timed_out"
    }

    result =
      source_request()
      |> Map.put(:observables, ["runtime.transport_activity"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        transport_runtime_events_fun: fn organization_id, mission_id, opts ->
          send(self(), {:transport_runtime_events, organization_id, mission_id, opts})
          [timer_event, record_event, action_event]
        end,
        command_verifier_instances_fun: fn organization_id, mission_id, opts ->
          send(self(), {:command_verifier_instances, organization_id, mission_id, opts})

          [
            satisfied_verifier_instance,
            failed_verifier_instance,
            telemetry_verifier_instance,
            capability_verifier_instance,
            timed_out_verifier_instance
          ]
        end,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :transport_runtime_activity_history
    assert frame.meta.supported_capability == :transport_runtime_activity_history
    assert frame.meta.product_family == :runtime_transport
    assert frame.meta.state_color_policy == :transport_runtime_activity
    assert frame.meta.observable_id == "runtime.transport_activity"
    assert frame.meta.realm == :replay
    assert frame.meta.dataset == "operational_observables_replay"
    assert frame.meta.replay_run_id == "replay-run-1"

    assert frame.meta.runtime_fact_ids == [
             "transport-record-1",
             "transport-action-request-1",
             "transport-timer-1"
           ]

    assert field_values(frame, "source_event_id") == [
             "transport-capability-record-event-1",
             "transport-action-request-event-1",
             "transport-timer-event-1"
           ]

    assert field_values(frame, "runtime_fact_kind") == [
             :transport_capability_record,
             :transport_action_request,
             :transport_timer_event
           ]

    assert field_values(frame, "runtime_fact_id") == [
             "transport-record-1",
             "transport-action-request-1",
             "transport-timer-1"
           ]

    assert field_values(frame, "transport_id") == [
             "transport-alpha",
             "transport-alpha",
             "transport-alpha"
           ]

    assert field_values(frame, "contact_id") == [
             "replay-contact-alpha",
             "replay-contact-alpha",
             "replay-contact-alpha"
           ]

    assert field_values(frame, "path_id") == [
             "replay-uplink-path",
             "replay-uplink-path",
             "replay-uplink-path"
           ]

    assert field_values(frame, "source_endpoint_ref") == [nil, "endpoint-alpha", nil]

    assert field_values(frame, "state") == [
             :transport_control_input_handled,
             :transport_action_requested,
             :transport_timer_fired
           ]

    assert field_values(frame, "record_event_kind") == [:control_input_handled, nil, :fired]
    assert field_values(frame, "emitted_record_kinds") == ["uplink_frame", nil, nil]
    assert field_values(frame, "emitted_record_count") == [1, nil, nil]
    assert field_values(frame, "action_request_count") == [1, nil, nil]
    assert field_values(frame, "timer_key") == [nil, nil, "cop1_timeout"]
    assert field_values(frame, "action_kind") == [nil, :release_command, nil]
    assert field_values(frame, "command_release_attempt_id") == [nil, "release-attempt-1", nil]
    assert field_values(frame, "command_request_id") == [nil, "command-request-1", nil]

    assert field_values(frame, "command_verifier_instance_ids") == [
             nil,
             "verifier-instance-satisfied,verifier-instance-failed,verifier-instance-telemetry-satisfied,verifier-instance-capability-satisfied,verifier-instance-timed-out",
             nil
           ]

    assert field_values(frame, "command_verification_state") == [nil, :failed, nil]

    assert field_values(frame, "command_verifier_lifecycle_states") == [
             nil,
             "satisfied,failed,timed_out",
             nil
           ]

    assert field_values(frame, "command_verifier_matched_record_ids") == [
             nil,
             "transport-action-request-1,verifier-telemetry-sample-1,transport-record-1",
             nil
           ]

    assert field_values(frame, "command_verifier_failure_reasons") == [
             nil,
             "failure_criteria_matched,timed_out",
             nil
           ]

    assert field_values(frame, "command_name") == [nil, "NOOP", nil]
    assert field_values(frame, "signal_phase") == [nil, :start, nil]

    assert field_values(frame, "action_request_document_json") == [
             nil,
             ~s({"command_request_id":"command-request-1","frame_count":1}),
             nil
           ]

    assert field_values(frame, "state_snapshot_json") == [
             ~s({"cop1_state":"active","vcid":7}),
             nil,
             nil
           ]

    assert field_values(frame, "record_metadata_json") == [
             ~s({"action_request_ids":["transport-action-request-1"],"emitted_record_refs":["uplink-frame-1"]}),
             ~s({"release_attempt_id":"release-attempt-1"}),
             ~s({"action_request_id":"transport-action-request-1"})
           ]

    assert evidence_identities(frame) == [
             {:operational_event, "transport-capability-record-event-1"},
             {:operational_event, "transport-action-request-event-1"},
             {:operational_event, "transport-timer-event-1"},
             {:command_release_attempt, "release-attempt-1"},
             {:command_verifier_instance, "verifier-instance-satisfied"},
             {:command_verifier_instance, "verifier-instance-failed"},
             {:command_verifier_instance, "verifier-instance-telemetry-satisfied"},
             {:command_verifier_instance, "verifier-instance-capability-satisfied"},
             {:command_verifier_instance, "verifier-instance-timed-out"},
             {:transport_action_request, "transport-action-request-1"},
             {:telemetry_sample, "verifier-telemetry-sample-1"},
             {:transport_capability_record, "transport-record-1"}
           ]

    assert_received {:transport_runtime_events, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time

    assert_received {:command_verifier_instances, "org-1", "mission-1", verifier_opts}
    assert verifier_opts[:command_release_attempt_ids] == ["release-attempt-1"]
    assert verifier_opts[:replay_run_id] == "replay-run-1"
  end

  test "filters transport execution history rows to operational resource scopes" do
    intervals = [
      transport_execution_interval(
        "link-alpha-interval",
        "transport-alpha",
        :initialized,
        ~U[2026-06-17 12:00:00Z],
        ~U[2026-06-17 12:01:00Z],
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha"
      ),
      transport_execution_interval(
        "link-beta-interval",
        "transport-beta",
        :timer_handled,
        ~U[2026-06-17 12:01:00Z],
        ~U[2026-06-17 12:02:00Z],
        source_endpoint_id: "endpoint-beta",
        ground_station_id: "dss-63",
        link_id: "link-beta"
      )
    ]

    for {scope_kind, scope_id, expected_interval_id} <- [
          {:source_endpoint, "endpoint-beta", "link-beta-interval"},
          {:ground_station, "dss-63", "link-beta-interval"},
          {:link, "link-beta", "link-beta-interval"}
        ] do
      result =
        source_request()
        |> Map.put(:observables, ["comms.transport.execution_state"])
        |> Map.put(:sampling, %{mode: :event_history, limit: 10})
        |> Map.put(:time_context, %{
          from: ~U[2026-06-17 12:00:00Z],
          to: ~U[2026-06-17 12:03:00Z]
        })
        |> Map.put(:scope_context, %{primary: %{kind: scope_kind, mode: :one, ids: [scope_id]}})
        |> OperationalObservables.resolve(
          transport_execution_intervals_fun: fn _organization_id, _mission_id, _opts ->
            intervals
          end,
          source_binding: source_binding()
        )

      assert %SourceResult{frames: [frame], warnings: []} = result
      assert field_values(frame, "interval_id") == [expected_interval_id]
      assert field_values(frame, "#{scope_kind}_id") == [scope_id]
    end

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.execution_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :link, mode: :many, ids: ["link-alpha", "link-beta"]}
      })
      |> OperationalObservables.resolve(
        transport_execution_intervals_fun: fn _organization_id, _mission_id, _opts ->
          intervals
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert field_values(frame, "interval_id") == ["link-alpha-interval", "link-beta-interval"]
    assert field_values(frame, "link_id") == ["link-alpha", "link-beta"]
  end
end
