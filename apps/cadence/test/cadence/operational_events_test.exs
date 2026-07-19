defmodule Cadence.OperationalEventsTest do
  use Cadence.RuntimeCase, async: false

  import Cadence.OperationalEventsFixtures

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    DataBinding,
    DataSource,
    DataSources,
    PlannedSourceRequest
  }

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  setup do
    organization_id =
      "org-operational-events-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id =
      "operational-events-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "persists and reads canonical operational event envelopes", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    occurred_at = DateTime.from_unix!(1_700_060_100, :second)

    event =
      Event.new(%{
        event_id: "operational_event:binding_set_activation:activation-1",
        mission_id: mission_id,
        occurred_at: occurred_at,
        recorded_at: occurred_at,
        effective_at: occurred_at,
        category: :runtime,
        kind: :binding_set_activated,
        severity: :info,
        actor: %{kind: :system},
        subject: %{kind: :binding_set, id: "runtime-basis"},
        causality: %{
          correlation_id: "runtime-basis",
          source_record_kind: :binding_set_activation,
          source_record_id: "activation-1"
        },
        payload: %{binding_set_id: "runtime-basis", binding_set_version: 2},
        metadata: %{"operator supplied key" => "kept"}
      })

    assert {:ok, persisted_event} = OperationalEvents.persist_event(event)

    assert persisted_event.organization_id == organization_id
    assert persisted_event.event_id == event.event_id
    assert DateTime.compare(persisted_event.occurred_at, occurred_at) == :eq
    assert persisted_event.category == :runtime
    assert persisted_event.kind == :binding_set_activated
    assert persisted_event.subject == %{kind: :binding_set, id: "runtime-basis"}

    assert persisted_event.causality == %{
             correlation_id: "runtime-basis",
             source_record_kind: :binding_set_activation,
             source_record_id: "activation-1"
           }

    assert persisted_event.payload == %{
             "binding_set_id" => "runtime-basis",
             "binding_set_version" => 2
           }

    assert persisted_event.metadata == %{"operator supplied key" => "kept"}

    assert {:ok, fetched_event} = Cadence.fetch_operational_event(event.event_id)
    assert fetched_event.event_id == event.event_id

    assert {:ok, scoped_event} =
             OperationalEvents.fetch_event(organization_id, mission_id, event.event_id)

    assert scoped_event.event_id == event.event_id

    assert {:error, :not_found} =
             OperationalEvents.fetch_event("other-organization", mission_id, event.event_id)

    assert Enum.any?(
             OperationalEvents.list_all_events(mission_id),
             &(&1.event_id == event.event_id)
           )

    assert [listed_event] =
             Cadence.list_operational_events(
               organization_id,
               mission_id,
               category: :runtime,
               kind: :binding_set_activated,
               source_record_kind: :binding_set_activation,
               source_record_id: "activation-1"
             )

    assert listed_event.event_id == event.event_id
  end

  test "upserts by event id without duplicating the source record", %{
    mission_id: mission_id
  } do
    occurred_at = DateTime.from_unix!(1_700_060_100, :second)

    event =
      Event.new(%{
        event_id: "operational_event:binding_set_activation:activation-upsert",
        mission_id: mission_id,
        occurred_at: occurred_at,
        recorded_at: occurred_at,
        category: :runtime,
        kind: :binding_set_activated,
        subject: %{kind: :binding_set, id: "runtime-basis"},
        causality: %{
          source_record_kind: :binding_set_activation,
          source_record_id: "activation-upsert"
        },
        metadata: %{"attempt" => 1}
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    assert {:ok, updated_event} =
             OperationalEvents.persist_event(%Event{event | metadata: %{"attempt" => 2}})

    assert updated_event.metadata == %{"attempt" => 2}

    events =
      Cadence.list_operational_events(
        mission_id,
        source_record_kind: :binding_set_activation,
        source_record_id: "activation-upsert"
      )

    assert Enum.map(events, & &1.event_id) == [event.event_id]
  end

  test "records and lists dashboard source capability posture operational events", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    posture = %{
      status: :fallback,
      requested_sampling: :latest,
      supported_sampling: [:latest],
      requested_products: [:link_rf_metric_history],
      supported_products: [:transport_bitrate_history],
      requested_time_axis: :generation_time,
      executed_time_axis: :receipt_time,
      supported_time_axes: [:receipt_time],
      fallbacks: [
        %{
          capability: :time_axis,
          requested: :generation_time,
          executed: :receipt_time,
          reason: :unsupported_time_axis
        }
      ]
    }

    result = %DashboardResolveResult{
      dashboard_id: "dashboard-capability-events",
      resolve_mode: :live_tick,
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-telemetry",
          organization_id: organization_id,
          mission_id: mission_id,
          logical_source: :telemetry,
          observables: ["HK.counter"],
          sampling: %{mode: :latest},
          metadata: %{
            capability_provenance: %{
              data_source_id: "flight-questdb",
              source_binding_id: "flight-telemetry",
              realm: :flight,
              capability_posture: posture
            }
          }
        }
      ],
      plan_metadata: %{
        source_request_count: 1,
        executed_source_request_count: 1,
        skipped_source_request_count: 0,
        cache: %{
          source_result_cache_by_request_id: %{
            "req-telemetry" => %{status: :hit}
          }
        }
      }
    }

    assert {:ok, [event]} =
             Cadence.record_dashboard_source_capability_postures(result,
               observed_at: ~U[2026-06-26 12:00:00Z],
               resolve_id: "resolve-capability-events"
             )

    assert event.kind == :source_capability_fallback
    assert event.subject == %{kind: :data_source, id: "flight-questdb"}

    assert [listed_event] =
             Cadence.list_dashboard_source_capability_posture_events(
               organization_id,
               mission_id,
               source_record_id:
                 "dashboard-capability-events:resolve-capability-events:req-telemetry"
             )

    assert listed_event.event_id == event.event_id
    assert listed_event.causality.source_record_kind == :source_capability_posture
    assert listed_event.payload["source_request_id"] == "req-telemetry"
    assert listed_event.payload["requested_products"] == ["link_rf_metric_history"]
    assert listed_event.payload["supported_products"] == ["transport_bitrate_history"]
    assert listed_event.current["capability_status"] == "fallback"
    assert listed_event.current["requested_products"] == ["link_rf_metric_history"]
    assert listed_event.current["supported_products"] == ["transport_bitrate_history"]
  end

  test "segregates source capability posture events by replay run id", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    observed_at = ~U[2026-06-26 12:00:00Z]
    posture_id = "dashboard-capability-events:resolve-capability-events:req-telemetry"

    replay_one =
      source_capability_posture_event(
        organization_id,
        mission_id,
        posture_id,
        "replay-run-1",
        observed_at
      )

    replay_two =
      source_capability_posture_event(
        organization_id,
        mission_id,
        posture_id,
        "replay-run-2",
        observed_at
      )

    assert replay_one.event_id != replay_two.event_id

    assert replay_one.event_id ==
             "operational_event:source_capability_posture:replay-run-1:#{posture_id}"

    assert replay_two.event_id ==
             "operational_event:source_capability_posture:replay-run-2:#{posture_id}"

    assert {:ok, _event} = OperationalEvents.persist_event(replay_one)
    assert {:ok, _event} = OperationalEvents.persist_event(replay_two)

    assert [listed_one] =
             Cadence.list_dashboard_source_capability_posture_events(
               organization_id,
               mission_id,
               source_record_id: posture_id,
               replay_run_id: "replay-run-1"
             )

    assert [listed_two] =
             Cadence.list_dashboard_source_capability_posture_events(
               organization_id,
               mission_id,
               source_record_id: posture_id,
               replay_run_id: "replay-run-2"
             )

    assert listed_one.event_id == replay_one.event_id
    assert listed_two.event_id == replay_two.event_id
    assert listed_one.payload["replay_run_id"] == "replay-run-1"
    assert listed_two.payload["replay_run_id"] == "replay-run-2"

    all_replay_postures =
      Cadence.list_dashboard_source_capability_posture_events(
        organization_id,
        mission_id,
        source_record_id: posture_id,
        order: :asc
      )

    assert Enum.map(all_replay_postures, & &1.event_id) == [
             replay_one.event_id,
             replay_two.event_id
           ]
  end

  test "segregates source health and watermark operational events by replay run id", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    observed_at = ~U[2026-06-26 12:00:00Z]

    health_replay_one =
      source_health_event(
        organization_id,
        mission_id,
        "source-health-event-1",
        "replay-run-1",
        observed_at
      )

    health_replay_two =
      source_health_event(
        organization_id,
        mission_id,
        "source-health-event-1",
        "replay-run-2",
        observed_at
      )

    watermark_replay_one =
      source_watermark_event(
        organization_id,
        mission_id,
        "source-watermark-event-1",
        "replay-run-1",
        observed_at
      )

    watermark_replay_two =
      source_watermark_event(
        organization_id,
        mission_id,
        "source-watermark-event-1",
        "replay-run-2",
        observed_at
      )

    assert health_replay_one.event_id ==
             "operational_event:source_health_event:replay-run-1:source-health-event-1"

    assert health_replay_two.event_id ==
             "operational_event:source_health_event:replay-run-2:source-health-event-1"

    assert watermark_replay_one.event_id ==
             "operational_event:source_watermark_event:replay-run-1:source-watermark-event-1"

    assert watermark_replay_two.event_id ==
             "operational_event:source_watermark_event:replay-run-2:source-watermark-event-1"

    assert {:ok, _event} = OperationalEvents.persist_event(health_replay_one)
    assert {:ok, _event} = OperationalEvents.persist_event(health_replay_two)
    assert {:ok, _event} = OperationalEvents.persist_event(watermark_replay_one)
    assert {:ok, _event} = OperationalEvents.persist_event(watermark_replay_two)

    assert [listed_health] =
             Cadence.list_operational_events(
               organization_id,
               mission_id,
               source_record_kind: :source_health_event,
               source_record_id: "source-health-event-1",
               replay_run_id: "replay-run-2"
             )

    assert [listed_watermark] =
             Cadence.list_operational_events(
               organization_id,
               mission_id,
               source_record_kind: :source_watermark_event,
               source_record_id: "source-watermark-event-1",
               replay_run_id: "replay-run-1"
             )

    assert listed_health.event_id == health_replay_two.event_id
    assert listed_watermark.event_id == watermark_replay_one.event_id
    assert listed_health.payload["replay_run_id"] == "replay-run-2"
    assert listed_watermark.payload["replay_run_id"] == "replay-run-1"
  end

  test "projects source health transitions as replay-scoped intervals", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    live_at = ~U[2026-06-26 12:00:00Z]
    replay_first_at = ~U[2026-06-26 12:01:00Z]
    other_replay_at = ~U[2026-06-26 12:02:00Z]
    replay_second_at = ~U[2026-06-26 12:03:00Z]

    assert {:ok, _event} =
             source_health_transition_event(
               organization_id,
               mission_id,
               "source-health-live-1",
               "live-questdb",
               nil,
               live_at,
               :degraded,
               :healthy
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             source_health_transition_event(
               organization_id,
               mission_id,
               "source-health-replay-1",
               "replay-questdb",
               "replay-run-1",
               replay_first_at,
               :degraded,
               :healthy
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             source_health_transition_event(
               organization_id,
               mission_id,
               "source-health-other-replay",
               "replay-questdb",
               "replay-run-2",
               other_replay_at,
               :unavailable,
               :healthy
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             source_health_transition_event(
               organization_id,
               mission_id,
               "source-health-replay-2",
               "replay-questdb",
               "replay-run-1",
               replay_second_at,
               :healthy,
               :degraded
             )
             |> OperationalEvents.persist_event()

    [live_interval] =
      Cadence.operational_source_health_intervals(organization_id, mission_id,
        data_source_id: "live-questdb",
        order: :asc
      )

    assert live_interval.kind == :source_health
    assert live_interval.subject_id == "live-questdb"
    assert live_interval.ends_at == nil
    assert live_interval.payload["realm"] == "live"
    assert live_interval.payload["source_health"] == "degraded"
    assert live_interval.payload["previous_source_health"] == "healthy"
    assert live_interval.payload["replay_run_id"] == nil

    [replay_first, replay_second] =
      Cadence.operational_source_health_intervals(organization_id, mission_id,
        data_source_id: "replay-questdb",
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_first.source_event_id ==
             "operational_event:source_health_event:replay-run-1:source-health-replay-1"

    assert replay_first.superseded_by_event_id ==
             "operational_event:source_health_event:replay-run-1:source-health-replay-2"

    assert DateTime.compare(replay_first.ends_at, replay_second_at) == :eq
    assert replay_first.payload["realm"] == "replay"
    assert replay_first.payload["source_health"] == "degraded"
    assert replay_first.payload["previous_source_health"] == "healthy"
    assert replay_first.payload["replay_run_id"] == "replay-run-1"

    assert replay_second.source_event_id ==
             "operational_event:source_health_event:replay-run-1:source-health-replay-2"

    assert replay_second.ends_at == nil
    assert replay_second.payload["source_health"] == "healthy"
    assert replay_second.payload["previous_source_health"] == "degraded"
    assert replay_second.payload["replay_run_id"] == "replay-run-1"

    [other_replay_interval] =
      Cadence.operational_source_health_intervals(organization_id, mission_id,
        data_source_id: "replay-questdb",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_interval.source_event_id ==
             "operational_event:source_health_event:replay-run-2:source-health-other-replay"

    assert other_replay_interval.payload["source_health"] == "unavailable"
    assert other_replay_interval.payload["replay_run_id"] == "replay-run-2"
  end

  test "segregates native transport operational events by replay run id", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    occurred_at = ~U[2026-06-30 12:10:01Z]

    capability_replay_one =
      mission_id
      |> transport_capability_record(
        "transport-record-1",
        "uplink-heartbeat",
        :initialized,
        occurred_at,
        state_snapshot: %{active?: true}
      )
      |> Event.from_transport_capability_record("replay-run-1")

    capability_replay_two =
      mission_id
      |> transport_capability_record(
        "transport-record-1",
        "uplink-heartbeat",
        :initialized,
        occurred_at,
        state_snapshot: %{active?: true}
      )
      |> Event.from_transport_capability_record("replay-run-2")

    action_replay_one =
      mission_id
      |> transport_action_request("transport-action-1", occurred_at)
      |> Event.from_transport_action_request("replay-run-1")

    action_replay_two =
      mission_id
      |> transport_action_request("transport-action-1", occurred_at)
      |> Event.from_transport_action_request("replay-run-2")

    timer_replay_one =
      mission_id
      |> transport_timer_event("transport-timer-1", occurred_at)
      |> Event.from_transport_timer_event("replay-run-1")

    timer_replay_two =
      mission_id
      |> transport_timer_event("transport-timer-1", occurred_at)
      |> Event.from_transport_timer_event("replay-run-2")

    assert {:ok, _event} = OperationalEvents.persist_event(capability_replay_one)
    assert {:ok, _event} = OperationalEvents.persist_event(capability_replay_two)
    assert {:ok, _event} = OperationalEvents.persist_event(action_replay_one)
    assert {:ok, _event} = OperationalEvents.persist_event(action_replay_two)
    assert {:ok, _event} = OperationalEvents.persist_event(timer_replay_one)
    assert {:ok, _event} = OperationalEvents.persist_event(timer_replay_two)

    assert [listed_capability] =
             Cadence.list_operational_events(
               organization_id,
               mission_id,
               source_record_kind: :transport_capability_record,
               source_record_id: "transport-record-1",
               replay_run_id: "replay-run-2"
             )

    assert [listed_action] =
             Cadence.list_operational_events(
               organization_id,
               mission_id,
               source_record_kind: :transport_action_request,
               source_record_id: "transport-action-1",
               replay_run_id: "replay-run-1"
             )

    assert [listed_timer] =
             Cadence.list_operational_events(
               organization_id,
               mission_id,
               source_record_kind: :transport_timer_event,
               source_record_id: "transport-timer-1",
               replay_run_id: "replay-run-2"
             )

    assert listed_capability.event_id ==
             "operational_event:transport_capability_record:replay-run-2:transport-record-1"

    assert listed_action.event_id ==
             "operational_event:transport_action_request:replay-run-1:transport-action-1"

    assert listed_timer.event_id ==
             "operational_event:transport_timer_event:replay-run-2:transport-timer-1"
  end

  test "projects binding-set activation intervals from operational events", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    first_activated_at = DateTime.from_unix!(1_700_060_100, :second)
    second_activated_at = DateTime.from_unix!(1_700_060_200, :second)

    first_binding_set = telemetry_binding_set(mission_id, "runtime-basis-a", 42)
    second_binding_set = telemetry_binding_set(mission_id, "runtime-basis-b", 43)

    assert {:ok, _binding_set} = Cadence.persist_binding_set(organization_id, first_binding_set)
    assert {:ok, _binding_set} = Cadence.persist_binding_set(organization_id, second_binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               organization_id,
               mission_id,
               first_binding_set.binding_set_id,
               first_binding_set.version,
               activated_at: first_activated_at
             )

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               organization_id,
               mission_id,
               second_binding_set.binding_set_id,
               second_binding_set.version,
               activated_at: second_activated_at
             )

    [first_interval, second_interval] =
      Cadence.operational_binding_set_intervals(organization_id, mission_id, order: :asc)

    assert first_interval.kind == :binding_set
    assert first_interval.subject_kind == :binding_set
    assert first_interval.subject_id == first_binding_set.binding_set_id
    assert DateTime.compare(first_interval.starts_at, first_activated_at) == :eq
    assert DateTime.compare(first_interval.ends_at, second_activated_at) == :eq
    assert first_interval.superseded_by_event_id == second_interval.source_event_id
    assert first_interval.payload["binding_set_id"] == first_binding_set.binding_set_id

    assert second_interval.subject_id == second_binding_set.binding_set_id
    assert DateTime.compare(second_interval.starts_at, second_activated_at) == :eq
    assert is_nil(second_interval.ends_at)
    assert is_nil(second_interval.superseded_by_event_id)

    [active_before_second] =
      Cadence.operational_binding_set_intervals(
        organization_id,
        mission_id,
        at: DateTime.from_unix!(1_700_060_150, :second)
      )

    assert active_before_second.subject_id == first_binding_set.binding_set_id

    [active_after_second] =
      Cadence.operational_binding_set_intervals(
        organization_id,
        mission_id,
        at: DateTime.from_unix!(1_700_060_250, :second)
      )

    assert active_after_second.subject_id == second_binding_set.binding_set_id

    assert [^first_interval] =
             Cadence.operational_binding_set_intervals(
               organization_id,
               mission_id,
               binding_set_id: first_binding_set.binding_set_id
             )
  end

  test "projects application binding intervals from active binding-set intervals", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    first_activated_at = ~U[2026-06-21 20:00:00Z]
    second_activated_at = ~U[2026-06-21 21:00:00Z]

    persist_source_endpoint_scope(organization_id, mission_id, "endpoint-sc-001")

    first_binding_set =
      application_binding_set(mission_id, "runtime-apps-a",
        source_endpoint_ref: "endpoint-sc-001",
        apid: 42,
        metric_name: "packets_v1"
      )

    second_binding_set =
      application_binding_set(mission_id, "runtime-apps-b",
        source_endpoint_ref: "endpoint-sc-001",
        apid: 43,
        metric_name: "packets_v2"
      )

    assert {:ok, _binding_set} = Cadence.persist_binding_set(organization_id, first_binding_set)
    assert {:ok, _binding_set} = Cadence.persist_binding_set(organization_id, second_binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               organization_id,
               mission_id,
               first_binding_set.binding_set_id,
               first_binding_set.version,
               activated_at: first_activated_at
             )

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               organization_id,
               mission_id,
               second_binding_set.binding_set_id,
               second_binding_set.version,
               activated_at: second_activated_at
             )

    [first_interval, second_interval] =
      Cadence.operational_application_binding_intervals(organization_id, mission_id,
        source_endpoint_ref: "endpoint-sc-001",
        application_key: :packet_counter,
        order: :asc
      )

    assert first_interval.kind == :application_binding
    assert first_interval.subject_kind == :application_binding
    assert first_interval.subject_id == "runtime-apps-a-packet-counter-rule"
    assert DateTime.compare(first_interval.starts_at, first_activated_at) == :eq
    assert DateTime.compare(first_interval.ends_at, second_activated_at) == :eq
    assert first_interval.superseded_by_event_id == second_interval.source_event_id
    assert first_interval.payload["binding_set_id"] == "runtime-apps-a"
    assert first_interval.payload["binding_set_version"] == 1
    assert first_interval.payload["binding_rule_id"] == "runtime-apps-a-packet-counter-rule"
    assert first_interval.payload["capability_instance_id"] == "runtime-apps-a-packet-counter"
    assert first_interval.payload["application_key"] == :packet_counter
    assert first_interval.payload["target_scope"] == :source_endpoint
    assert first_interval.payload["source_endpoint_ref"] == "endpoint-sc-001"
    assert first_interval.payload["packet_kind"] == :space_packet
    assert first_interval.payload["apid"] == 42
    assert first_interval.payload["fanout_mode"] == :multi
    assert first_interval.payload["capability_lifecycle_state"] == :active

    assert first_interval.metadata["binding_set_interval_id"] =~
             "effective_interval:binding_set:"

    assert second_interval.subject_id == "runtime-apps-b-packet-counter-rule"
    assert DateTime.compare(second_interval.starts_at, second_activated_at) == :eq
    assert second_interval.ends_at == nil
    assert second_interval.payload["binding_set_id"] == "runtime-apps-b"
    assert second_interval.payload["apid"] == 43

    [active_before_second] =
      Cadence.operational_application_binding_intervals(organization_id, mission_id,
        at: ~U[2026-06-21 20:30:00Z],
        target_scope: :source_endpoint
      )

    assert active_before_second.payload["binding_set_id"] == "runtime-apps-a"

    [active_after_second] =
      Cadence.operational_application_binding_intervals(organization_id, mission_id,
        at: ~U[2026-06-21 21:30:00Z],
        capability_instance_id: "runtime-apps-b-packet-counter"
      )

    assert active_after_second.payload["binding_set_id"] == "runtime-apps-b"
  end

  test "projects catalog revision intervals from canonical operational events", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    first_registered_at = ~U[2026-06-21 20:00:00Z]
    second_registered_at = ~U[2026-06-21 21:00:00Z]

    first_revision =
      catalog_revision(
        organization_id,
        mission_id,
        "catalog-revision-a",
        revision_number: 1,
        revision_label: "FSW 3.6",
        telemetry_snapshot_id: "telemetry-snapshot-a",
        import_run_id: "import-run-a"
      )

    second_revision =
      catalog_revision(
        organization_id,
        mission_id,
        "catalog-revision-b",
        revision_number: 2,
        revision_label: "FSW 3.7",
        telemetry_snapshot_id: "telemetry-snapshot-b",
        import_run_id: "import-run-b"
      )

    assert {:ok, _event} =
             first_revision
             |> Event.from_catalog_revision(first_registered_at)
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             second_revision
             |> Event.from_catalog_revision(second_registered_at)
             |> OperationalEvents.persist_event()

    [first_interval, second_interval] =
      Cadence.operational_catalog_revision_intervals(organization_id, mission_id,
        catalog_database_id: "bus-catalog",
        order: :asc
      )

    assert first_interval.kind == :catalog_revision
    assert first_interval.subject_kind == :catalog_revision
    assert first_interval.subject_id == "catalog-revision-a"
    assert DateTime.compare(first_interval.starts_at, first_registered_at) == :eq
    assert DateTime.compare(first_interval.ends_at, second_registered_at) == :eq
    assert first_interval.superseded_by_event_id == second_interval.source_event_id
    assert first_interval.payload["catalog_database_id"] == "bus-catalog"
    assert first_interval.payload["revision_number"] == 1
    assert first_interval.payload["revision_label"] == "FSW 3.6"
    assert first_interval.payload["catalog_family"] == "telemetry"
    assert first_interval.payload["telemetry_snapshot_id"] == "telemetry-snapshot-a"
    assert first_interval.metadata["source_record_kind"] == :catalog_revision
    assert first_interval.metadata["source_record_id"] == "catalog-revision-a"

    assert second_interval.subject_id == "catalog-revision-b"
    assert DateTime.compare(second_interval.starts_at, second_registered_at) == :eq
    assert second_interval.ends_at == nil
    assert second_interval.payload["revision_number"] == 2

    [active_before_second] =
      Cadence.operational_catalog_revision_intervals(organization_id, mission_id,
        at: ~U[2026-06-21 20:30:00Z],
        catalog_family: :telemetry
      )

    assert active_before_second.subject_id == "catalog-revision-a"

    [active_after_second] =
      Cadence.operational_catalog_revision_intervals(organization_id, mission_id,
        at: ~U[2026-06-21 21:30:00Z],
        catalog_revision_id: "catalog-revision-b"
      )

    assert active_after_second.payload["revision_label"] == "FSW 3.7"
  end

  test "projects source-binding intervals from canonical operational events", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    first_event_at = ~U[2026-06-21 20:00:00Z]
    second_event_at = ~U[2026-06-21 21:00:00Z]

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "interval-questdb-v1",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: organization_id,
               mission_id: mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true},
               metadata: %{storage: :questdb}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "interval-questdb-v2",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: organization_id,
               mission_id: mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true},
               metadata: %{storage: :questdb}
             })

    binding = %DataBinding{
      binding_id: "interval-flight-telemetry",
      organization_id: organization_id,
      mission_id: mission_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "interval-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, registered} =
             DataSources.persist_data_binding(binding,
               actor_id: "operator-1",
               occurred_at: first_event_at,
               payload: %{reason: :initial_binding}
             )

    assert {:ok, changed} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding
                 | data_source_id: "interval-questdb-v2",
                   dataset: "flight-v2",
                   priority: 1
               },
               actor_id: "operator-2",
               occurred_at: second_event_at,
               payload: %{change_request_id: "CR-42"}
             )

    [first_interval, second_interval] =
      Cadence.operational_source_binding_intervals(organization_id, mission_id,
        binding_id: "interval-flight-telemetry",
        order: :asc
      )

    assert first_interval.kind == :source_binding
    assert first_interval.subject_kind == :source_binding
    assert first_interval.subject_id == "interval-flight-telemetry"
    assert DateTime.compare(first_interval.starts_at, first_event_at) == :eq
    assert DateTime.compare(first_interval.ends_at, second_event_at) == :eq
    assert first_interval.superseded_by_event_id == second_interval.source_event_id
    assert first_interval.payload["binding_id"] == "interval-flight-telemetry"
    assert first_interval.payload["binding_version"] == 1
    assert first_interval.payload["status"] == "active"
    assert first_interval.payload["logical_source"] == "telemetry"
    assert first_interval.payload["realm"] == "flight"
    assert first_interval.payload["data_source_id"] == "interval-questdb-v1"
    assert first_interval.payload["dataset"] == "flight-v1"
    assert first_interval.metadata["source_record_kind"] == :dashboard_data_binding_event
    assert first_interval.metadata["source_record_id"] == registered.current_event_id

    assert second_interval.subject_id == "interval-flight-telemetry"
    assert DateTime.compare(second_interval.starts_at, second_event_at) == :eq
    assert second_interval.ends_at == nil
    assert second_interval.payload["binding_version"] == 2
    assert second_interval.payload["data_source_id"] == "interval-questdb-v2"
    assert second_interval.metadata["source_record_id"] == changed.current_event_id

    [active_before_change] =
      Cadence.operational_source_binding_intervals(organization_id, mission_id,
        at: ~U[2026-06-21 20:30:00Z],
        logical_source: :telemetry,
        realm: :flight
      )

    assert active_before_change.payload["data_source_id"] == "interval-questdb-v1"

    [active_after_change] =
      Cadence.operational_source_binding_intervals(organization_id, mission_id,
        at: ~U[2026-06-21 21:30:00Z],
        data_source_id: "interval-questdb-v2"
      )

    assert active_after_change.payload["dataset"] == "flight-v2"
  end

  test "projects transport execution intervals from canonical operational events", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    initialized_at = ~U[2026-06-30 12:00:00Z]
    control_at = ~U[2026-06-30 12:05:00Z]
    other_transport_at = ~U[2026-06-30 12:02:00Z]

    assert {:ok, _event} =
             transport_capability_record(
               mission_id,
               "transport-record-1",
               "uplink-heartbeat",
               :initialized,
               initialized_at,
               state_snapshot: %{active?: true, heartbeat_count: 0}
             )
             |> Event.from_transport_capability_record()
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             transport_capability_record(
               mission_id,
               "transport-record-2",
               "uplink-heartbeat",
               :control_input_handled,
               control_at,
               state_snapshot: %{active?: false, last_control_command: :pause},
               metadata: %{interaction: :control_input}
             )
             |> Event.from_transport_capability_record()
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             transport_capability_record(
               mission_id,
               "transport-record-3",
               "downlink-heartbeat",
               :initialized,
               other_transport_at,
               path_id: "downlink-path-alpha",
               state_snapshot: %{active?: true, heartbeat_count: 0}
             )
             |> Event.from_transport_capability_record()
             |> OperationalEvents.persist_event()

    [first_interval, second_interval] =
      Cadence.operational_transport_execution_intervals(organization_id, mission_id,
        capability_instance_id: "uplink-heartbeat",
        order: :asc
      )

    assert first_interval.kind == :transport_execution
    assert first_interval.subject_kind == :transport
    assert first_interval.subject_id == "uplink-heartbeat"
    assert DateTime.compare(first_interval.starts_at, initialized_at) == :eq
    assert DateTime.compare(first_interval.ends_at, control_at) == :eq
    assert first_interval.superseded_by_event_id == second_interval.source_event_id
    assert first_interval.payload["transport_record_id"] == "transport-record-1"
    assert first_interval.payload["contact_id"] == "realized-contact-1"
    assert first_interval.payload["path_id"] == "uplink-path-alpha"
    assert first_interval.payload["event_kind"] == "initialized"
    assert first_interval.payload["family_key"] == "heartbeat_monitor"

    assert first_interval.payload["state_snapshot"] == %{
             "active?" => true,
             "heartbeat_count" => 0
           }

    assert first_interval.metadata["source_record_kind"] == :transport_capability_record
    assert first_interval.metadata["source_record_id"] == "transport-record-1"
    assert first_interval.metadata["event_kind"] == :transport_initialized

    assert second_interval.payload["transport_record_id"] == "transport-record-2"
    assert second_interval.payload["event_kind"] == "control_input_handled"

    assert second_interval.payload["state_snapshot"] == %{
             "active?" => false,
             "last_control_command" => "pause"
           }

    assert is_nil(second_interval.ends_at)

    [active_before_control] =
      Cadence.operational_transport_execution_intervals(organization_id, mission_id,
        at: ~U[2026-06-30 12:03:00Z],
        capability_instance_id: "uplink-heartbeat"
      )

    assert active_before_control.payload["transport_record_id"] == "transport-record-1"

    [paused_interval] =
      Cadence.operational_transport_execution_intervals(organization_id, mission_id,
        event_kind: :control_input_handled
      )

    assert paused_interval.subject_id == "uplink-heartbeat"
    assert paused_interval.payload["record_metadata"] == %{"interaction" => "control_input"}

    [downlink_interval] =
      Cadence.operational_transport_execution_intervals(organization_id, mission_id,
        path_id: "downlink-path-alpha"
      )

    assert downlink_interval.subject_id == "downlink-heartbeat"
    assert downlink_interval.ends_at == nil
  end

  test "scopes transport execution intervals by replay run without mixing live events", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    live_at = ~U[2026-06-30 12:00:00Z]
    replay_first_at = ~U[2026-06-30 12:01:00Z]
    other_replay_at = ~U[2026-06-30 12:02:00Z]
    replay_second_at = ~U[2026-06-30 12:03:00Z]

    assert {:ok, _event} =
             transport_capability_record(
               mission_id,
               "transport-live-record",
               "uplink-heartbeat",
               :initialized,
               live_at,
               state_snapshot: %{active?: true, source: :live}
             )
             |> Event.from_transport_capability_record()
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             transport_capability_record(
               mission_id,
               "transport-replay-record-1",
               "uplink-heartbeat",
               :initialized,
               replay_first_at,
               state_snapshot: %{active?: true, source: :replay}
             )
             |> replay_scoped_event("replay-run-1")
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             transport_capability_record(
               mission_id,
               "transport-other-replay-record",
               "uplink-heartbeat",
               :control_input_handled,
               other_replay_at,
               state_snapshot: %{active?: false, source: :other_replay}
             )
             |> replay_scoped_event("replay-run-2")
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             transport_capability_record(
               mission_id,
               "transport-replay-record-2",
               "uplink-heartbeat",
               :timer_handled,
               replay_second_at,
               timer_key: "health-check",
               state_snapshot: %{active?: true, source: :replay}
             )
             |> replay_scoped_event("replay-run-1")
             |> OperationalEvents.persist_event()

    [live_interval] =
      Cadence.operational_transport_execution_intervals(organization_id, mission_id,
        capability_instance_id: "uplink-heartbeat",
        order: :asc
      )

    assert live_interval.payload["transport_record_id"] == "transport-live-record"
    assert live_interval.ends_at == nil

    [replay_first, replay_second] =
      Cadence.operational_transport_execution_intervals(organization_id, mission_id,
        capability_instance_id: "uplink-heartbeat",
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_first.payload["transport_record_id"] == "transport-replay-record-1"

    assert replay_first.source_event_id ==
             "operational_event:transport_capability_record:replay-run-1:transport-replay-record-1"

    assert DateTime.compare(replay_first.ends_at, replay_second_at) == :eq
    assert replay_first.payload["replay_run_id"] == "replay-run-1"

    assert replay_second.payload["transport_record_id"] == "transport-replay-record-2"

    assert replay_second.source_event_id ==
             "operational_event:transport_capability_record:replay-run-1:transport-replay-record-2"

    assert replay_second.ends_at == nil
    assert replay_second.payload["replay_run_id"] == "replay-run-1"

    [other_replay_interval] =
      Cadence.operational_transport_execution_intervals(organization_id, mission_id,
        capability_instance_id: "uplink-heartbeat",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_interval.payload["transport_record_id"] ==
             "transport-other-replay-record"

    assert other_replay_interval.source_event_id ==
             "operational_event:transport_capability_record:replay-run-2:transport-other-replay-record"
  end
end
