defmodule Cadence.OperationalEventsTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Catalog.Revision

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    DataBinding,
    DataSource,
    DataSources,
    PlannedSourceRequest,
    SourceHealthEvent,
    SourceWatermarkEvent
  }

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Runtime.{TransportActionRequest, TransportCapabilityRecord, TransportTimerEvent}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

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

  test "projects antenna pointing state events as generic operational observable intervals",
       %{organization_id: organization_id, mission_id: mission_id} do
    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "antenna-pointing-1",
               :slewing,
               ~U[2026-06-30 12:00:00Z],
               observable_id: "ground.station.antenna_pointing_state",
               resource_id: "dss-14",
               scope_kind: :ground_station
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "antenna-pointing-2",
               :tracking,
               ~U[2026-06-30 12:05:00Z],
               observable_id: "ground.station.antenna_pointing_state",
               resource_id: "dss-14",
               scope_kind: :ground_station
             )
             |> OperationalEvents.persist_event()

    [slewing, tracking] =
      Cadence.operational_observable_state_intervals(organization_id, mission_id,
        observable_id: "ground.station.antenna_pointing_state",
        resource_id: "dss-14",
        order: :asc
      )

    assert slewing.kind == :operational_observable_state
    assert slewing.subject_kind == :ground_station
    assert slewing.subject_id == "dss-14"
    assert DateTime.compare(slewing.starts_at, ~U[2026-06-30 12:00:00Z]) == :eq
    assert DateTime.compare(slewing.ends_at, ~U[2026-06-30 12:05:00Z]) == :eq
    assert slewing.payload["observable_id"] == "ground.station.antenna_pointing_state"
    assert slewing.payload["state"] == "slewing"

    assert DateTime.compare(tracking.starts_at, ~U[2026-06-30 12:05:00Z]) == :eq
    assert tracking.ends_at == nil
    assert tracking.payload["state"] == "tracking"
  end

  test "scopes operational observable state intervals by replay run without mixing live events",
       %{
         organization_id: organization_id,
         mission_id: mission_id
       } do
    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "connection-live-1",
               :connected,
               ~U[2026-06-30 12:00:00Z]
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "connection-replay-1",
               :connecting,
               ~U[2026-06-30 12:01:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "connection-other-replay",
               :disconnected,
               ~U[2026-06-30 12:02:00Z],
               replay_run_id: "replay-run-2"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "connection-replay-2",
               :connected,
               ~U[2026-06-30 12:03:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    [live_interval] =
      Cadence.operational_observable_state_intervals(organization_id, mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        order: :asc
      )

    assert live_interval.kind == :operational_observable_state
    assert live_interval.subject_kind == :transport
    assert live_interval.subject_id == "transport-alpha"

    assert live_interval.source_event_id ==
             "operational_event:connection_state_snapshot:connection-live-1"

    assert live_interval.payload["connection_state"] == "connected"
    assert live_interval.payload["replay_run_id"] == nil

    [replay_first, replay_second] =
      Cadence.operational_observable_state_intervals(organization_id, mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_first.source_event_id ==
             "operational_event:connection_state_snapshot:replay-run-1:connection-replay-1"

    assert replay_first.payload["connection_state"] == "connecting"
    assert replay_first.payload["replay_run_id"] == "replay-run-1"
    assert DateTime.compare(replay_first.ends_at, ~U[2026-06-30 12:03:00Z]) == :eq
    assert replay_first.superseded_by_event_id == replay_second.source_event_id

    assert replay_second.source_event_id ==
             "operational_event:connection_state_snapshot:replay-run-1:connection-replay-2"

    assert replay_second.payload["connection_state"] == "connected"
    assert replay_second.payload["replay_run_id"] == "replay-run-1"
    assert replay_second.ends_at == nil

    [other_replay_interval] =
      Cadence.operational_observable_state_intervals(organization_id, mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_interval.source_event_id ==
             "operational_event:connection_state_snapshot:replay-run-2:connection-other-replay"

    assert other_replay_interval.payload["connection_state"] == "disconnected"
  end

  test "segregates typed operational observable state source-record families", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    observed_at = ~U[2026-06-30 12:20:00Z]

    events = [
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "shared-state-snapshot",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        scope_kind: :transport,
        transport_id: "transport-alpha",
        connection_state: :connected,
        observed_at: observed_at
      }),
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "shared-state-snapshot",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        link_id: "link-alpha",
        state: :locked,
        observed_at: DateTime.add(observed_at, 1, :second)
      }),
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "shared-state-snapshot",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.frame_sync_state",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        link_id: "link-alpha",
        state: :synchronized,
        observed_at: DateTime.add(observed_at, 2, :second)
      })
    ]

    for event <- events do
      assert {:ok, _event} = OperationalEvents.persist_event(event)
    end

    assert [connection_event] =
             Cadence.list_operational_events(organization_id, mission_id,
               source_record_kind: :connection_state_snapshot,
               source_record_id: "shared-state-snapshot"
             )

    assert [rf_lock_event] =
             Cadence.list_operational_events(organization_id, mission_id,
               source_record_kind: :link_rf_lock_state_snapshot,
               source_record_id: "shared-state-snapshot"
             )

    assert [frame_sync_event] =
             Cadence.list_operational_events(organization_id, mission_id,
               source_record_kind: :link_frame_sync_state_snapshot,
               source_record_id: "shared-state-snapshot"
             )

    assert connection_event.event_id ==
             "operational_event:connection_state_snapshot:shared-state-snapshot"

    assert rf_lock_event.event_id ==
             "operational_event:link_rf_lock_state_snapshot:shared-state-snapshot"

    assert frame_sync_event.event_id ==
             "operational_event:link_frame_sync_state_snapshot:shared-state-snapshot"

    [rf_lock_interval] =
      Cadence.operational_observable_state_intervals(organization_id, mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha"
      )

    assert rf_lock_interval.source_event_id == rf_lock_event.event_id
    assert rf_lock_interval.metadata["source_record_kind"] == :link_rf_lock_state_snapshot

    [frame_sync_interval] =
      Cadence.operational_observable_state_intervals(organization_id, mission_id,
        observable_id: "link.frame_sync_state",
        resource_id: "link-alpha"
      )

    assert frame_sync_interval.source_event_id == frame_sync_event.event_id
    assert frame_sync_interval.metadata["source_record_kind"] == :link_frame_sync_state_snapshot
  end

  test "projects typed RF state facts into native link RF intervals", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "rf-lock-live-1",
               :acquiring,
               ~U[2026-06-30 12:30:00Z],
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "rf-lock-replay-1",
               :locked,
               ~U[2026-06-30 12:31:00Z],
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "rf-lock-other-replay",
               :unlocked,
               ~U[2026-06-30 12:32:00Z],
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-2"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "rf-lock-replay-2",
               :degraded,
               ~U[2026-06-30 12:33:00Z],
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "frame-sync-replay-1",
               :synchronized,
               ~U[2026-06-30 12:31:30Z],
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    [live_lock] =
      Cadence.operational_link_rf_state_intervals(organization_id, mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha",
        order: :asc
      )

    assert live_lock.kind == :link_rf_lock_state
    assert live_lock.subject_kind == :link
    assert live_lock.subject_id == "link-alpha"

    assert live_lock.source_event_id ==
             "operational_event:link_rf_lock_state_snapshot:rf-lock-live-1"

    assert live_lock.payload["rf_state_family"] == :rf_lock
    assert live_lock.payload["rf_lock_state"] == "acquiring"
    assert live_lock.payload["frame_sync_state"] == nil
    assert live_lock.payload["replay_run_id"] == nil
    assert live_lock.metadata["source_record_kind"] == :link_rf_lock_state_snapshot

    [replay_lock_first, replay_frame_sync, replay_lock_second] =
      Cadence.operational_link_rf_state_intervals(organization_id, mission_id,
        resource_id: "link-alpha",
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_lock_first.kind == :link_rf_lock_state
    assert replay_lock_first.payload["rf_lock_state"] == "locked"
    assert replay_lock_first.payload["replay_run_id"] == "replay-run-1"
    assert DateTime.compare(replay_lock_first.ends_at, ~U[2026-06-30 12:33:00Z]) == :eq
    assert replay_lock_first.superseded_by_event_id == replay_lock_second.source_event_id

    assert replay_frame_sync.kind == :link_frame_sync_state

    assert replay_frame_sync.source_event_id ==
             "operational_event:link_frame_sync_state_snapshot:replay-run-1:frame-sync-replay-1"

    assert replay_frame_sync.payload["rf_state_family"] == :frame_sync
    assert replay_frame_sync.payload["frame_sync_state"] == "synchronized"
    assert replay_frame_sync.payload["rf_lock_state"] == nil

    assert replay_lock_second.kind == :link_rf_lock_state
    assert replay_lock_second.payload["rf_lock_state"] == "degraded"
    assert replay_lock_second.ends_at == nil

    [other_replay_lock] =
      Cadence.operational_link_rf_state_intervals(organization_id, mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_lock.payload["rf_lock_state"] == "unlocked"

    [family_filtered] =
      Cadence.operational_link_rf_state_intervals(organization_id, mission_id,
        rf_state_family: :frame_sync,
        replay_run_id: "replay-run-1"
      )

    assert family_filtered.kind == :link_frame_sync_state
  end

  test "projects typed connection state facts into native connection intervals", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "transport-connection-live-1",
               :connecting,
               ~U[2026-06-30 12:40:00Z]
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "transport-connection-replay-1",
               :connected,
               ~U[2026-06-30 12:41:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "transport-connection-other-replay",
               :disconnected,
               ~U[2026-06-30 12:42:00Z],
               replay_run_id: "replay-run-2"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "transport-connection-replay-2",
               :degraded,
               ~U[2026-06-30 12:43:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "ground-connection-replay-1",
               :connected,
               ~U[2026-06-30 12:41:30Z],
               observable_id: "ground.station.connection_state",
               resource_id: "dss-14",
               scope_kind: :ground_station,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    [live_transport] =
      Cadence.operational_connection_state_intervals(organization_id, mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        order: :asc
      )

    assert live_transport.kind == :transport_connection_state
    assert live_transport.subject_kind == :transport
    assert live_transport.subject_id == "transport-alpha"

    assert live_transport.source_event_id ==
             "operational_event:connection_state_snapshot:transport-connection-live-1"

    assert live_transport.payload["connection_state_family"] == :transport
    assert live_transport.payload["transport_connection_state"] == "connecting"
    assert live_transport.payload["ground_station_connection_state"] == nil
    assert live_transport.payload["replay_run_id"] == nil
    assert live_transport.metadata["source_record_kind"] == :connection_state_snapshot

    [replay_transport_first, replay_ground_station, replay_transport_second] =
      Cadence.operational_connection_state_intervals(organization_id, mission_id,
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_transport_first.kind == :transport_connection_state
    assert replay_transport_first.payload["connection_state"] == "connected"
    assert replay_transport_first.payload["transport_connection_state"] == "connected"
    assert replay_transport_first.payload["replay_run_id"] == "replay-run-1"
    assert DateTime.compare(replay_transport_first.ends_at, ~U[2026-06-30 12:43:00Z]) == :eq

    assert replay_transport_first.superseded_by_event_id ==
             replay_transport_second.source_event_id

    assert replay_ground_station.kind == :ground_station_connection_state
    assert replay_ground_station.subject_kind == :ground_station
    assert replay_ground_station.subject_id == "dss-14"

    assert replay_ground_station.source_event_id ==
             "operational_event:connection_state_snapshot:replay-run-1:ground-connection-replay-1"

    assert replay_ground_station.payload["connection_state_family"] == :ground_station
    assert replay_ground_station.payload["ground_station_connection_state"] == "connected"
    assert replay_ground_station.payload["transport_connection_state"] == nil

    assert replay_transport_second.kind == :transport_connection_state
    assert replay_transport_second.payload["connection_state"] == "degraded"
    assert replay_transport_second.ends_at == nil

    [other_replay_transport] =
      Cadence.operational_connection_state_intervals(organization_id, mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_transport.payload["connection_state"] == "disconnected"

    [family_filtered] =
      Cadence.operational_connection_state_intervals(organization_id, mission_id,
        connection_state_family: :ground_station,
        replay_run_id: "replay-run-1"
      )

    assert family_filtered.kind == :ground_station_connection_state
  end

  test "scopes operational observable metric samples by replay run without mixing live events",
       %{
         organization_id: organization_id,
         mission_id: mission_id
       } do
    assert {:ok, _event} =
             operational_observable_metric_event(
               organization_id,
               mission_id,
               "rf-snr-live-1",
               11.5,
               ~U[2026-06-30 12:00:00Z]
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_metric_event(
               organization_id,
               mission_id,
               "rf-snr-replay-1",
               12.25,
               ~U[2026-06-30 12:01:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_metric_event(
               organization_id,
               mission_id,
               "rf-snr-other-replay",
               7.5,
               ~U[2026-06-30 12:02:00Z],
               replay_run_id: "replay-run-2"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_metric_event(
               organization_id,
               mission_id,
               "rf-snr-replay-2",
               14.0,
               ~U[2026-06-30 12:03:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    [live_sample] =
      Cadence.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.snr_db",
        resource_id: "link-alpha",
        order: :asc
      )

    assert live_sample.observable_id == "link.snr_db"
    assert live_sample.resource_id == "link-alpha"
    assert live_sample.scope_kind == "link"
    assert live_sample.snr_db == 11.5
    assert Map.get(live_sample, :replay_run_id) == nil

    [replay_first, replay_second] =
      Cadence.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.snr_db",
        resource_id: "link-alpha",
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_first.snr_db == 12.25
    assert replay_first.replay_run_id == "replay-run-1"
    assert replay_first.observed_at == ~U[2026-06-30 12:01:00Z]

    assert replay_second.snr_db == 14.0
    assert replay_second.replay_run_id == "replay-run-1"
    assert replay_second.observed_at == ~U[2026-06-30 12:03:00Z]

    [other_replay_sample] =
      Cadence.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.snr_db",
        resource_id: "link-alpha",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_sample.snr_db == 7.5
  end

  test "preserves uplink bitrate fields in operational observable metric samples", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "uplink-bitrate-live-1",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "comms.transport.uplink_bitrate",
        resource_id: "transport-alpha",
        scope_kind: :transport,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        uplink_bitrate: 4_800.0,
        uplink_bitrate_bps: 4_800.0,
        unit: "bit/s",
        observed_at: ~U[2026-06-30 12:04:00Z]
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    [sample] =
      Cadence.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "comms.transport.uplink_bitrate",
        resource_id: "transport-alpha"
      )

    assert sample.observable_id == "comms.transport.uplink_bitrate"
    assert sample.resource_id == "transport-alpha"
    assert sample.scope_kind == "transport"
    assert sample.uplink_bitrate == 4_800.0
    assert sample.uplink_bitrate_bps == 4_800.0
    assert sample.unit == "bit/s"
  end

  test "preserves RF Eb/N0 fields in operational observable metric samples", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-ebn0-live-1",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.eb_n0_db",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        eb_n0_db: 8.25,
        ebn0_db: 8.25,
        energy_per_bit_to_noise_density_db: 8.25,
        unit: "dB",
        observed_at: ~U[2026-06-30 12:04:30Z]
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    [sample] =
      Cadence.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.eb_n0_db",
        resource_id: "link-alpha"
      )

    assert sample.observable_id == "link.eb_n0_db"
    assert sample.resource_id == "link-alpha"
    assert sample.scope_kind == "link"
    assert sample.eb_n0_db == 8.25
    assert sample.ebn0_db == 8.25
    assert sample.energy_per_bit_to_noise_density_db == 8.25
    assert sample.unit == "dB"
  end

  test "preserves RF symbol-rate fields in operational observable metric samples", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-symbol-rate-live-1",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.symbol_rate_sps",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        symbol_rate_sps: 1_024_000.0,
        symbol_rate: 1_024_000.0,
        symbols_per_second: 1_024_000.0,
        unit: "sym/s",
        observed_at: ~U[2026-06-30 12:04:45Z]
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    [sample] =
      Cadence.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.symbol_rate_sps",
        resource_id: "link-alpha"
      )

    assert sample.observable_id == "link.symbol_rate_sps"
    assert sample.resource_id == "link-alpha"
    assert sample.scope_kind == "link"
    assert sample.symbol_rate_sps == 1_024_000.0
    assert sample.symbol_rate == 1_024_000.0
    assert sample.symbols_per_second == 1_024_000.0
    assert sample.unit == "sym/s"
  end

  test "preserves RF Doppler fields in operational observable metric samples", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-doppler-live-1",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.doppler_hz",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        doppler_hz: -42.5,
        frequency_offset_hz: -42.5,
        carrier_frequency_offset_hz: -42.5,
        unit: "Hz",
        observed_at: ~U[2026-06-30 12:05:00Z]
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    [sample] =
      Cadence.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.doppler_hz",
        resource_id: "link-alpha"
      )

    assert sample.observable_id == "link.doppler_hz"
    assert sample.resource_id == "link-alpha"
    assert sample.scope_kind == "link"
    assert sample.doppler_hz == -42.5
    assert sample.frequency_offset_hz == -42.5
    assert sample.carrier_frequency_offset_hz == -42.5
    assert sample.unit == "Hz"
  end

  defp transport_capability_record(
         mission_id,
         transport_record_id,
         capability_instance_id,
         event_kind,
         recorded_at,
         opts
       ) do
    %TransportCapabilityRecord{
      transport_record_id: transport_record_id,
      mission_id: mission_id,
      realized_contact_id: "realized-contact-1",
      path_id: Keyword.get(opts, :path_id, "uplink-path-alpha"),
      capability_instance_id: capability_instance_id,
      family_key: :heartbeat_monitor,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "source-endpoint-alpha",
      event_kind: event_kind,
      timer_key: Keyword.get(opts, :timer_key),
      emitted_record_kinds: Keyword.get(opts, :emitted_record_kinds, []),
      emitted_record_count: Keyword.get(opts, :emitted_record_count, 0),
      action_request_count: Keyword.get(opts, :action_request_count, 0),
      state_snapshot: Keyword.fetch!(opts, :state_snapshot),
      recorded_at: recorded_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp transport_action_request(mission_id, action_request_id, requested_at, opts \\ []) do
    %TransportActionRequest{
      action_request_id: action_request_id,
      mission_id: mission_id,
      realized_contact_id: "realized-contact-1",
      path_id: Keyword.get(opts, :path_id, "uplink-path-alpha"),
      capability_instance_id: Keyword.get(opts, :capability_instance_id, "uplink-heartbeat"),
      family_key: :heartbeat_monitor,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "source-endpoint-alpha",
      command_release_attempt_id: Keyword.get(opts, :command_release_attempt_id),
      command_request_id: Keyword.get(opts, :command_request_id),
      source_endpoint_ref: "source-endpoint-alpha",
      command_name: Keyword.get(opts, :command_name),
      signal_phase: Keyword.get(opts, :signal_phase),
      action_kind: Keyword.get(opts, :action_kind, :uplink_request),
      request_document: Keyword.get(opts, :request_document, %{}),
      requested_at: requested_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp transport_timer_event(mission_id, timer_event_id, occurred_at, opts \\ []) do
    %TransportTimerEvent{
      timer_event_id: timer_event_id,
      mission_id: mission_id,
      realized_contact_id: "realized-contact-1",
      path_id: Keyword.get(opts, :path_id, "uplink-path-alpha"),
      capability_instance_id: Keyword.get(opts, :capability_instance_id, "uplink-heartbeat"),
      family_key: :heartbeat_monitor,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "source-endpoint-alpha",
      timer_key: Keyword.get(opts, :timer_key, "health-check"),
      event_kind: Keyword.get(opts, :event_kind, :fired),
      due_at: Keyword.get(opts, :due_at),
      occurred_at: occurred_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp operational_observable_state_event(
         organization_id,
         mission_id,
         snapshot_id,
         state,
         observed_at,
         opts \\ []
       ) do
    observable_id = Keyword.get(opts, :observable_id, "comms.transport.connection_state")

    Event.from_operational_observable_state_snapshot(%{
      snapshot_id: snapshot_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: observable_id,
      resource_id: Keyword.get(opts, :resource_id, "transport-alpha"),
      scope_kind: Keyword.get(opts, :scope_kind, :transport),
      transport_id: "transport-alpha",
      source_endpoint_id: "endpoint-alpha",
      ground_station_id: "dss-14",
      link_id: "link-alpha",
      adapter_key: :tcp_socket,
      connection_state: connection_state(observable_id, state),
      state: operational_observable_state(observable_id, state),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    })
  end

  defp connection_state(observable_id, state)
       when observable_id in [
              "comms.transport.connection_state",
              "ground.station.connection_state"
            ],
       do: state

  defp connection_state(_observable_id, _state), do: nil

  defp operational_observable_state(observable_id, state)
       when observable_id in [
              "link.rf_lock_state",
              "link.frame_sync_state",
              "ground.station.antenna_pointing_state"
            ],
       do: state

  defp operational_observable_state(_observable_id, _state), do: nil

  defp operational_observable_metric_event(
         organization_id,
         mission_id,
         sample_id,
         snr_db,
         observed_at,
         opts \\ []
       ) do
    Event.from_operational_observable_metric_sample(%{
      sample_id: sample_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: "link.snr_db",
      resource_id: "link-alpha",
      scope_kind: :link,
      transport_id: "transport-alpha",
      source_endpoint_id: "endpoint-alpha",
      ground_station_id: "dss-14",
      link_id: "link-alpha",
      adapter_key: :rf_adapter,
      snr_db: snr_db,
      unit: "dB",
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    })
  end

  defp replay_scoped_event(%TransportCapabilityRecord{} = record, replay_run_id) do
    Event.from_transport_capability_record(record, replay_run_id)
  end

  defp source_capability_posture_event(
         organization_id,
         mission_id,
         posture_id,
         replay_run_id,
         observed_at
       ) do
    Event.from_source_capability_posture(%{
      source_capability_posture_id: posture_id,
      organization_id: organization_id,
      mission_id: mission_id,
      dashboard_id: "dashboard-capability-events",
      dashboard_version: 4,
      resolve_id: "resolve-capability-events",
      source_request_id: "req-telemetry",
      logical_source: :telemetry,
      data_source_id: "flight-questdb",
      source_binding_id: "flight-telemetry",
      realm: :replay,
      replay_run_id: replay_run_id,
      dataset: "flight",
      status: :fallback,
      requested_sampling: :latest,
      supported_sampling: [:latest],
      requested_products: [:link_rf_metric_history],
      supported_products: [:transport_bitrate_history],
      requested_time_axis: :generation_time,
      executed_time_axis: :receipt_time,
      supported_time_axes: [:receipt_time],
      source_execution_status: :cache_hit,
      source_execution_cache_status: :hit,
      source_execution_operator_action: :none,
      source_execution_runtime_action: :none,
      source_execution_warning_codes: [],
      observed_at: observed_at
    })
  end

  defp source_health_event(
         organization_id,
         mission_id,
         source_health_event_id,
         replay_run_id,
         observed_at
       ) do
    %{
      source_health_event_id: source_health_event_id,
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :telemetry,
      data_source_id: "replay-questdb",
      source_binding_id: "replay-telemetry",
      realm: :replay,
      replay_run_id: replay_run_id,
      dataset: "replay",
      source_health: :degraded,
      previous_source_health: :healthy,
      reason: :source_probe_failed,
      observed_at: observed_at
    }
    |> SourceHealthEvent.new()
    |> Event.from_source_health_event()
  end

  defp source_health_transition_event(
         organization_id,
         mission_id,
         source_health_event_id,
         data_source_id,
         replay_run_id,
         observed_at,
         source_health,
         previous_source_health
       ) do
    realm = if replay_run_id, do: :replay, else: :live

    dataset =
      if replay_run_id, do: "operational_observables_replay", else: "operational_observables"

    %{
      source_health_event_id: source_health_event_id,
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :operational_observables,
      data_source_id: data_source_id,
      source_binding_id: "operational-observables",
      realm: realm,
      replay_run_id: replay_run_id,
      dataset: dataset,
      source_health: source_health,
      previous_source_health: previous_source_health,
      reason: :source_probe_failed,
      observed_at: observed_at
    }
    |> SourceHealthEvent.new()
    |> Event.from_source_health_event()
  end

  defp source_watermark_event(
         organization_id,
         mission_id,
         source_watermark_event_id,
         replay_run_id,
         observed_at
       ) do
    %{
      source_watermark_event_id: source_watermark_event_id,
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :telemetry,
      data_source_id: "replay-questdb",
      source_binding_id: "replay-telemetry",
      realm: :replay,
      replay_run_id: replay_run_id,
      dataset: "replay",
      event_type: :observed,
      complete_through: observed_at,
      latest_receipt_time: observed_at,
      sample_count: 42,
      confidence: :best_effort,
      reason: :source_watermark_observed,
      observed_at: observed_at
    }
    |> SourceWatermarkEvent.new()
    |> Event.from_source_watermark_event()
  end

  defp catalog_revision(organization_id, mission_id, catalog_revision_id, opts) do
    Revision.new(%{
      catalog_revision_id: catalog_revision_id,
      organization_id: organization_id,
      mission_id: mission_id,
      catalog_database_id: "bus-catalog",
      revision_number: Keyword.fetch!(opts, :revision_number),
      revision_label: Keyword.fetch!(opts, :revision_label),
      catalog_family: :telemetry,
      artifact_id: "#{catalog_revision_id}-artifact",
      import_run_id: Keyword.fetch!(opts, :import_run_id),
      telemetry_snapshot_id: Keyword.fetch!(opts, :telemetry_snapshot_id),
      command_snapshot_id: nil,
      content_sha256: "#{catalog_revision_id}-sha",
      created_by: %{"service_identity_id" => "svc-importer"},
      metadata: %{"source_artifact_name" => "#{catalog_revision_id}.json"}
    })
  end

  defp telemetry_binding_set(mission_id, binding_set_id, apid) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: binding_set_id <> "-packet",
        packet_name: binding_set_id,
        apid: apid,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: binding_set_id,
      version: 1,
      rules: [
        BindingRule.new(%{
          handler_key: :definition_bound_telemetry,
          selector: %{match: %{packet_kind: :space_packet, apid: apid}},
          handler_configuration: packet_definition
        })
      ]
    })
  end

  defp application_binding_set(mission_id, binding_set_id, opts) do
    source_endpoint_ref = Keyword.fetch!(opts, :source_endpoint_ref)
    apid = Keyword.fetch!(opts, :apid)
    metric_name = Keyword.fetch!(opts, :metric_name)

    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: binding_set_id,
      version: 1,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "#{binding_set_id}-packet-counter",
          family_key: :packet_counter,
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref,
          capability_config:
            CapabilityConfig.inline(%{
              "metric_name" => metric_name,
              "flush_interval_ms" => 25
            })
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "#{binding_set_id}-packet-counter-rule",
          capability_instance_id: "#{binding_set_id}-packet-counter",
          selector: %{
            scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
            match: %{packet_kind: :space_packet, apid: apid}
          },
          priority: 10,
          fanout_mode: :multi
        })
      ]
    })
  end

  defp persist_source_endpoint_scope(organization_id, mission_id, source_endpoint_ref) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-001",
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: "SC-001"
      })

    assert {:ok, _spacecraft} = Cadence.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: source_endpoint_ref,
        organization_id: organization_id,
        mission_id: mission_id,
        spacecraft_id: "sc-001",
        source_ref: "provider/#{source_endpoint_ref}"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(organization_id, source_endpoint)
  end
end
