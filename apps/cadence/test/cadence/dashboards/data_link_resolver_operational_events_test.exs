defmodule Cadence.Dashboards.DataLinkResolverOperationalEventsTest do
  use Cadence.RuntimeCase, async: false

  import Cadence.Dashboards.DataLinkResolverFixtures

  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Dashboards.{DataLink, DataLinkResolver, SourceHealth}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Projections.MissionEvents
  alias Cadence.Repo
  alias Cadence.Runtime.{ManagedActionRequest, ManagedCapabilityRecord}

  test "resolves mission event and contact links" do
    organization_id = "org-resolver-events"
    mission_id = "mission-resolver-events"
    persist_mission_scope(organization_id, mission_id)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "resolver-contact-alpha",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths("source-endpoint-alpha"),
        starts_at: ~U[2026-06-20 12:00:00Z],
        ends_at: ~U[2026-06-20 12:10:00Z]
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_contact} =
             Cadence.Contacts.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "weather"
             )

    [mission_event] = Cadence.list_mission_events(organization_id, mission_id, order: :asc)

    mission_event_link = %DataLink{
      label: "Mission event",
      target: :mission_event,
      target_id: mission_event.mission_event_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    contact_link = %DataLink{
      label: "Contact",
      target: :contact,
      target_id: scheduled_contact.scheduled_contact_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, event_inspector} =
             DataLinkResolver.resolve(mission_event_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert event_inspector.status == :resolved
    assert event_inspector.target == :mission_event
    assert row_value(event_inspector.rows, "Mission event") == mission_event.mission_event_id
    assert row_value(event_inspector.rows, "Kind") == "scheduled_contact_canceled"

    assert row_value(event_inspector.rows, "Scheduled contact") ==
             scheduled_contact.scheduled_contact_id

    assert row_value(event_inspector.context_rows, "Logical source") == "events"

    assert related_link(
             event_inspector.related_links,
             :contact,
             scheduled_contact.scheduled_contact_id
           )

    assert {:ok, contact_inspector} =
             DataLinkResolver.resolve(contact_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert contact_inspector.status == :resolved
    assert contact_inspector.target == :contact
    assert row_value(contact_inspector.rows, "Contact") == scheduled_contact.scheduled_contact_id
    assert row_value(contact_inspector.rows, "Contact type") == "scheduled_contact"
    assert row_value(contact_inspector.rows, "Lifecycle state") == "canceled"
    assert row_value(contact_inspector.rows, "Source endpoints") == "source-endpoint-alpha"

    assert row_value(contact_inspector.rows, "Paths") ==
             "resolver-uplink-path,resolver-downlink-path"
  end

  test "resolves canonical operational events and mission event source handoffs" do
    organization_id = "org-resolver-operational-event"
    mission_id = "mission-resolver-operational-event"
    occurred_at = ~U[2026-06-30 12:04:00Z]

    persist_mission_scope(organization_id, mission_id)

    event =
      Event.new(%{
        event_id: "operational_event:binding_set_activation:resolver",
        organization_id: organization_id,
        mission_id: mission_id,
        occurred_at: occurred_at,
        recorded_at: occurred_at,
        effective_at: occurred_at,
        category: :runtime,
        kind: :binding_set_activated,
        severity: :info,
        actor: %{kind: :system, id: "runtime"},
        subject: %{kind: :binding_set, id: "runtime-basis"},
        causality: %{
          correlation_id: "runtime-basis",
          source_record_kind: :binding_set_activation,
          source_record_id: "activation-resolver"
        },
        payload: %{
          binding_set_id: "runtime-basis",
          binding_set_version: 3,
          activation_id: "activation-resolver"
        },
        current: %{state: :active},
        metadata: %{"source" => "resolver-test"}
      })

    assert {:ok, persisted_event} = OperationalEvents.persist_event(event)

    assert {:ok, 1} =
             MissionEvents.persist_entries(Repo, MissionEvents.project_many([persisted_event]))

    [mission_event] = Cadence.list_mission_events(organization_id, mission_id, order: :asc)

    operational_event_link = %DataLink{
      label: "Operational event",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :annotation
    }

    mission_event_link = %DataLink{
      label: "Mission event",
      target: :mission_event,
      target_id: mission_event.mission_event_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, operational_event_inspector} =
             DataLinkResolver.resolve(operational_event_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert operational_event_inspector.status == :resolved
    assert operational_event_inspector.target == :operational_event

    assert row_value(operational_event_inspector.rows, "Operational event") ==
             persisted_event.event_id

    assert row_value(operational_event_inspector.rows, "Kind") == "binding_set_activated"
    assert row_value(operational_event_inspector.rows, "Payload") =~ "runtime-basis"
    assert row_value(operational_event_inspector.context_rows, "Logical source") == "events"

    assert {:ok, mission_event_inspector} =
             DataLinkResolver.resolve(mission_event_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert row_value(mission_event_inspector.rows, "Source record kind") == "operational_event"
    assert row_value(mission_event_inspector.rows, "Source record") == persisted_event.event_id

    assert %DataLink{relationship_kind: :source_event} =
             related_link(
               mission_event_inspector.related_links,
               :operational_event,
               persisted_event.event_id
             )

    persist_mission_scope(
      "org-resolver-operational-event-b",
      "mission-resolver-operational-event-b"
    )

    assert {:error, missing_inspector} =
             DataLinkResolver.resolve(operational_event_link,
               organization_id: "org-resolver-operational-event-b",
               mission_id: "mission-resolver-operational-event-b"
             )

    assert missing_inspector.status == :missing
  end

  test "resolves managed action request operational events with semantic rows" do
    organization_id = "org-resolver-managed-action"
    mission_id = "mission-resolver-managed-action"
    replay_run_id = "replay-run-managed-action"
    requested_at = ~U[2026-06-30 12:01:30Z]

    persist_mission_scope(organization_id, mission_id)

    action_request = %ManagedActionRequest{
      action_request_id: "managed-action-request-resolver",
      mission_id: mission_id,
      capability_instance_id: "managed-capability-alpha",
      family_key: :packet_counter,
      activation_id: "managed-activation-alpha",
      binding_set_id: "managed-binding-set-alpha",
      binding_set_version: 4,
      partition_affinity: :spacecraft,
      partition_value: "spacecraft-alpha",
      action_kind: :schedule_timer,
      packet_id: "managed-packet-alpha",
      evidence_id: "managed-evidence-alpha",
      request_document: %{"delay_ms" => 1_000, "timer_key" => "flush"},
      requested_at: requested_at
    }

    assert {:ok, persisted_event} =
             action_request
             |> Event.from_managed_action_request(replay_run_id)
             |> Map.put(:organization_id, organization_id)
             |> OperationalEvents.persist_event()

    action_link = %DataLink{
      label: "Managed action request",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{
        source_request_id: "events-request-managed-action",
        logical_source: :events,
        data: %{
          realm: :replay,
          replay_run_id: replay_run_id,
          data_source_id: "ops-source-managed-action",
          source_binding_id: "ops-binding-managed-action"
        }
      },
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(action_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :operational_event
    assert inspector.target_id == persisted_event.event_id
    assert row_value(inspector.rows, "Managed action request") == action_request.action_request_id
    assert row_value(inspector.rows, "Operational event") == persisted_event.event_id
    assert row_value(inspector.rows, "Capability instance") == "managed-capability-alpha"
    assert row_value(inspector.rows, "Family") == "packet_counter"
    assert row_value(inspector.rows, "Binding set") == "managed-binding-set-alpha"
    assert row_value(inspector.rows, "Binding set version") == "4"
    assert row_value(inspector.rows, "Partition affinity") == "spacecraft"
    assert row_value(inspector.rows, "Partition value") == "spacecraft-alpha"
    assert row_value(inspector.rows, "Action kind") == "schedule_timer"
    assert row_value(inspector.rows, "Request document") =~ "timer_key"
    assert row_value(inspector.rows, "Requested") == DateTime.to_iso8601(requested_at)
    assert row_value(inspector.rows, "Replay run") == replay_run_id
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
  end

  test "resolves managed capability record operational events with semantic rows" do
    organization_id = "org-resolver-managed-capability"
    mission_id = "mission-resolver-managed-capability"
    replay_run_id = "replay-run-managed-capability"
    recorded_at = ~U[2026-06-30 12:02:30Z]

    persist_mission_scope(organization_id, mission_id)

    capability_record = %ManagedCapabilityRecord{
      capability_record_id: "managed-capability-record-resolver",
      mission_id: mission_id,
      capability_instance_id: "managed-capability-alpha",
      family_key: :packet_counter,
      activation_id: "managed-activation-alpha",
      binding_set_id: "managed-binding-set-alpha",
      binding_set_version: 4,
      partition_affinity: :spacecraft,
      partition_value: "spacecraft-alpha",
      event_kind: :record_handled,
      packet_id: "managed-packet-alpha",
      evidence_id: "managed-evidence-alpha",
      timer_key: nil,
      emitted_record_kinds: [:derived_metric, :limit_state],
      emitted_record_count: 2,
      action_request_count: 1,
      state_snapshot: %{active?: true, heartbeat_count: 1},
      recorded_at: recorded_at,
      metadata: %{
        "action_request_ids" => ["managed-action-request-resolver"],
        "emitted_record_refs" => ["limit-state-1", "derived-metric-1"]
      }
    }

    assert {:ok, persisted_event} =
             capability_record
             |> Event.from_managed_capability_record(replay_run_id)
             |> Map.put(:organization_id, organization_id)
             |> OperationalEvents.persist_event()

    capability_link = %DataLink{
      label: "Managed capability record",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{
        source_request_id: "events-request-managed-capability",
        logical_source: :events,
        data: %{
          realm: :replay,
          replay_run_id: replay_run_id,
          data_source_id: "ops-source-managed-capability",
          source_binding_id: "ops-binding-managed-capability"
        }
      },
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(capability_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :operational_event
    assert inspector.target_id == persisted_event.event_id

    assert row_value(inspector.rows, "Managed capability record") ==
             capability_record.capability_record_id

    assert row_value(inspector.rows, "Operational event") == persisted_event.event_id
    assert row_value(inspector.rows, "Capability instance") == "managed-capability-alpha"
    assert row_value(inspector.rows, "Family") == "packet_counter"
    assert row_value(inspector.rows, "Binding set") == "managed-binding-set-alpha"
    assert row_value(inspector.rows, "Binding set version") == "4"
    assert row_value(inspector.rows, "Partition affinity") == "spacecraft"
    assert row_value(inspector.rows, "Partition value") == "spacecraft-alpha"
    assert row_value(inspector.rows, "Event kind") == "record_handled"
    assert row_value(inspector.rows, "Emitted record kinds") == "derived_metric,limit_state"
    assert row_value(inspector.rows, "Emitted record count") == "2"
    assert row_value(inspector.rows, "Action request count") == "1"
    assert row_value(inspector.rows, "State snapshot") =~ "heartbeat_count"
    assert row_value(inspector.rows, "Record metadata") =~ "managed-action-request-resolver"
    assert row_value(inspector.rows, "Recorded") == "2026-06-30T12:02:30.000000Z"
    assert row_value(inspector.rows, "Replay run") == replay_run_id
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
  end

  test "resolves transport capability record operational events with semantic rows" do
    organization_id = "org-resolver-transport-capability-event"
    mission_id = "mission-resolver-transport-capability-event"
    replay_run_id = "replay-run-transport-capability-event"
    recorded_at = ~U[2026-06-30 12:04:30Z]

    persist_mission_scope(organization_id, mission_id)

    capability_record =
      transport_capability_record(
        mission_id,
        "transport-capability-record-resolver",
        "transport-capability-alpha",
        :control_input_handled,
        recorded_at,
        emitted_record_kinds: [:uplink_frame, :cop1_status],
        emitted_record_count: 2,
        action_request_count: 1,
        state_snapshot: %{cop1_state: "active", heartbeat_count: 4, vcid: 7},
        metadata: %{
          "action_request_ids" => ["transport-action-request-resolver"],
          "emitted_record_refs" => ["uplink-frame-1", "cop1-status-1"]
        }
      )

    assert {:ok, persisted_event} =
             capability_record
             |> Event.from_transport_capability_record(replay_run_id)
             |> Map.put(:organization_id, organization_id)
             |> OperationalEvents.persist_event()

    capability_link = %DataLink{
      label: "Transport capability record",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{
        source_request_id: "events-request-transport-capability",
        logical_source: :events,
        data: %{
          realm: :replay,
          replay_run_id: replay_run_id,
          data_source_id: "ops-source-transport-capability",
          source_binding_id: "ops-binding-transport-capability"
        }
      },
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(capability_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :operational_event
    assert inspector.target_id == persisted_event.event_id

    assert row_value(inspector.rows, "Transport capability record") ==
             capability_record.transport_record_id

    assert row_value(inspector.rows, "Operational event") == persisted_event.event_id
    assert row_value(inspector.rows, "Capability instance") == "transport-capability-alpha"
    assert row_value(inspector.rows, "Family") == "heartbeat_monitor"
    assert row_value(inspector.rows, "Contact") == "realized-contact-1"
    assert row_value(inspector.rows, "Path") == "uplink-path-alpha"
    assert row_value(inspector.rows, "Binding set") == "binding-set-1"
    assert row_value(inspector.rows, "Binding set version") == "4"
    assert row_value(inspector.rows, "Partition affinity") == "source_endpoint"
    assert row_value(inspector.rows, "Partition value") == "source-endpoint-alpha"
    assert row_value(inspector.rows, "Event kind") == "control_input_handled"
    assert row_value(inspector.rows, "Emitted record kinds") == "uplink_frame,cop1_status"
    assert row_value(inspector.rows, "Emitted record count") == "2"
    assert row_value(inspector.rows, "Action request count") == "1"
    assert row_value(inspector.rows, "State snapshot") =~ "heartbeat_count"
    assert row_value(inspector.rows, "Record metadata") =~ "transport-action-request-resolver"
    assert row_value(inspector.rows, "Recorded") == "2026-06-30T12:04:30.000000Z"
    assert row_value(inspector.rows, "Replay run") == replay_run_id
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
  end

  test "resolves transport action request operational events with semantic rows" do
    organization_id = "org-resolver-transport-action-event"
    mission_id = "mission-resolver-transport-action-event"
    replay_run_id = "replay-run-transport-action-event"
    requested_at = ~U[2026-06-30 12:05:30Z]

    persist_mission_scope(organization_id, mission_id)

    action_request =
      transport_action_request(
        mission_id,
        "transport-action-request-resolver",
        "transport-capability-alpha",
        :release_command,
        requested_at,
        command_release_attempt_id: "release-attempt-resolver",
        command_request_id: "command-request-resolver",
        source_endpoint_ref: "source-endpoint-resolver",
        command_name: "NOOP",
        signal_phase: :start,
        request_document: %{
          "command_request_id" => "command-request-resolver",
          "frame_count" => 2
        },
        metadata: %{"release_attempt_id" => "release-attempt-resolver"}
      )

    assert {:ok, persisted_event} =
             action_request
             |> Event.from_transport_action_request(replay_run_id)
             |> Map.put(:organization_id, organization_id)
             |> OperationalEvents.persist_event()

    action_link = %DataLink{
      label: "Transport action request",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{
        source_request_id: "events-request-transport-action",
        logical_source: :events,
        data: %{
          realm: :replay,
          replay_run_id: replay_run_id,
          data_source_id: "ops-source-transport-action",
          source_binding_id: "ops-binding-transport-action"
        }
      },
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(action_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :operational_event
    assert inspector.target_id == persisted_event.event_id

    assert row_value(inspector.rows, "Transport action request") ==
             action_request.action_request_id

    assert row_value(inspector.rows, "Operational event") == persisted_event.event_id
    assert row_value(inspector.rows, "Capability instance") == "transport-capability-alpha"
    assert row_value(inspector.rows, "Family") == "heartbeat_monitor"
    assert row_value(inspector.rows, "Contact") == "realized-contact-1"
    assert row_value(inspector.rows, "Path") == "uplink-path-alpha"
    assert row_value(inspector.rows, "Binding set") == "binding-set-1"
    assert row_value(inspector.rows, "Binding set version") == "4"
    assert row_value(inspector.rows, "Partition affinity") == "source_endpoint"
    assert row_value(inspector.rows, "Partition value") == "source-endpoint-alpha"
    assert row_value(inspector.rows, "Source endpoint") == "source-endpoint-resolver"
    assert row_value(inspector.rows, "Command release attempt") == "release-attempt-resolver"
    assert row_value(inspector.rows, "Command request") == "command-request-resolver"
    assert row_value(inspector.rows, "Command") == "NOOP"
    assert row_value(inspector.rows, "Signal phase") == "start"
    assert row_value(inspector.rows, "Action kind") == "release_command"
    assert row_value(inspector.rows, "Request document") =~ "frame_count"
    assert row_value(inspector.rows, "Requested") == DateTime.to_iso8601(requested_at)
    assert row_value(inspector.rows, "Action metadata") =~ "release-attempt-resolver"
    assert row_value(inspector.rows, "Replay run") == replay_run_id
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
  end

  test "resolves projection-only mission events from canonical operational events" do
    organization_id = "org-resolver-projected-mission-event"
    mission_id = "mission-resolver-projected-mission-event"
    replay_run_id = "resolver-projected-replay-run"
    occurred_at = ~U[2026-06-30 12:08:00Z]

    persist_mission_scope(organization_id, mission_id)

    event =
      Event.new(%{
        event_id: "operational_event:binding_set_activation:resolver-projected",
        organization_id: organization_id,
        mission_id: mission_id,
        occurred_at: occurred_at,
        recorded_at: occurred_at,
        effective_at: occurred_at,
        category: :runtime,
        kind: :binding_set_activated,
        severity: :info,
        actor: %{kind: :replay, id: replay_run_id},
        subject: %{kind: :binding_set, id: "runtime-basis-projected"},
        causality: %{
          correlation_id: "runtime-basis-projected",
          source_record_kind: :binding_set_activation,
          source_record_id: "activation-resolver-projected",
          replay_run_id: replay_run_id
        },
        payload: %{
          binding_set_id: "runtime-basis-projected",
          binding_set_version: 5,
          activation_id: "activation-resolver-projected"
        },
        current: %{state: :active},
        metadata: %{"source" => "resolver-projected-test", "replay_run_id" => replay_run_id}
      })

    assert {:ok, persisted_event} = OperationalEvents.persist_event(event)

    mission_event_link = %DataLink{
      label: "Mission event",
      target: :mission_event,
      target_id: "mission_event:#{persisted_event.event_id}",
      context: %{
        source_request_id: "events-request-1",
        logical_source: :events,
        data: %{
          realm: :replay,
          source_binding_id: "replay_events",
          replay_run_id: replay_run_id
        }
      },
      source: :frame
    }

    assert {:ok, mission_event_inspector} =
             DataLinkResolver.resolve(mission_event_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert mission_event_inspector.status == :resolved
    assert mission_event_inspector.target == :mission_event

    assert row_value(mission_event_inspector.rows, "Mission event") ==
             "mission_event:#{persisted_event.event_id}"

    assert row_value(mission_event_inspector.rows, "Kind") == "binding_set_activated"
    assert row_value(mission_event_inspector.rows, "Source record kind") == "operational_event"
    assert row_value(mission_event_inspector.rows, "Source record") == persisted_event.event_id
    assert row_value(mission_event_inspector.context_rows, "Data realm") == "replay"
    assert row_value(mission_event_inspector.context_rows, "Source binding") == "replay_events"
    assert row_value(mission_event_inspector.context_rows, "Replay run") == replay_run_id

    assert %DataLink{relationship_kind: :source_event} =
             related_link(
               mission_event_inspector.related_links,
               :operational_event,
               persisted_event.event_id
             )
  end

  test "resolves source capability posture operational events with semantic rows" do
    organization_id = "org-resolver-source-capability-posture"
    mission_id = "mission-resolver-source-capability-posture"

    persist_mission_scope(organization_id, mission_id)

    event =
      Event.from_source_capability_posture(%{
        organization_id: organization_id,
        mission_id: mission_id,
        source_capability_posture_id: "dashboard-1:resolve-1:req-telemetry",
        dashboard_id: "dashboard-1",
        dashboard_version: 7,
        resolve_id: "resolve-1",
        source_request_id: "req-telemetry",
        logical_source: :telemetry,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry",
        realm: :flight,
        dataset: "flight",
        status: :fallback,
        requested_sampling: :window,
        supported_sampling: [:latest, :window],
        requested_products: [:link_rf_metric_history],
        supported_products: [:transport_bitrate_history],
        requested_time_axis: :generation_time,
        executed_time_axis: :receipt_time,
        supported_time_axes: [:receipt_time],
        fallbacks: [:receipt_time_axis],
        unsupported: [:generation_time_axis],
        source_execution_status: :resolved,
        source_execution_cache_status: :miss,
        source_execution_operator_action: :inspect_source_capability,
        source_execution_runtime_action: :use_receipt_time_axis,
        source_execution_warning_codes: [:unsupported_source_capability],
        observed_at: ~U[2026-06-30 12:08:00Z]
      })

    assert {:ok, persisted_event} = OperationalEvents.persist_event(event)

    link = %DataLink{
      label: "Source capability posture",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :operational_event
    assert row_value(inspector.rows, "Operational event") == persisted_event.event_id
    assert row_value(inspector.rows, "Kind") == "source_capability_fallback"

    assert row_value(inspector.rows, "Source capability posture") ==
             "dashboard-1:resolve-1:req-telemetry"

    assert row_value(inspector.rows, "Dashboard") == "dashboard-1"
    assert row_value(inspector.rows, "Dashboard version") == "7"
    assert row_value(inspector.rows, "Resolve") == "resolve-1"
    assert row_value(inspector.rows, "Source request") == "req-telemetry"
    assert row_value(inspector.rows, "Logical source") == "telemetry"
    assert row_value(inspector.rows, "Data source") == "flight-questdb"
    assert row_value(inspector.rows, "Source binding") == "flight-telemetry"
    assert row_value(inspector.rows, "Realm") == "flight"
    assert row_value(inspector.rows, "Dataset") == "flight"
    assert row_value(inspector.rows, "Capability status") == "fallback"
    assert row_value(inspector.rows, "Requested sampling") == "window"
    assert row_value(inspector.rows, "Supported sampling") == "latest,window"
    assert row_value(inspector.rows, "Requested products") == "link_rf_metric_history"
    assert row_value(inspector.rows, "Supported products") == "transport_bitrate_history"
    assert row_value(inspector.rows, "Requested time axis") == "generation_time"
    assert row_value(inspector.rows, "Executed time axis") == "receipt_time"
    assert row_value(inspector.rows, "Supported time axes") == "receipt_time"
    assert row_value(inspector.rows, "Fallbacks") == "receipt_time_axis"
    assert row_value(inspector.rows, "Unsupported") == "generation_time_axis"
    assert row_value(inspector.rows, "Source execution status") == "resolved"
    assert row_value(inspector.rows, "Source execution cache status") == "miss"

    assert row_value(inspector.rows, "Source execution operator action") ==
             "inspect_source_capability"

    assert row_value(inspector.rows, "Source execution runtime action") ==
             "use_receipt_time_axis"

    assert row_value(inspector.rows, "Source execution warnings") ==
             "unsupported_source_capability"

    assert row_value(inspector.context_rows, "Source request") == "events-request-1"
    assert row_value(inspector.context_rows, "Logical source") == "events"
  end

  test "resolves source health event links from persisted transition events" do
    organization_id = "org-resolver-source-health"
    mission_id = "mission-resolver-source-health"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, _healthy_event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: organization_id,
                 mission_id: mission_id,
                 logical_source: :telemetry,
                 data_source_id: "flight-questdb",
                 source_binding_id: "flight-telemetry",
                 realm: :flight,
                 dataset: "flight",
                 replay_run_id: "replay-run-source-health",
                 source_health: :healthy,
                 reason: :source_probe_succeeded,
                 observed_at: ~U[2026-06-21 12:00:00Z]
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: organization_id,
                 mission_id: mission_id,
                 logical_source: :telemetry,
                 data_source_id: "flight-questdb",
                 source_binding_id: "flight-telemetry",
                 realm: :flight,
                 dataset: "flight",
                 replay_run_id: "replay-run-source-health",
                 source_health: :degraded,
                 reason: :source_probe_failed,
                 observed_at: ~U[2026-06-21 12:02:00Z],
                 payload: %{probe_id: "probe-1"}
               },
               invalidate_runtime_cache?: false
             )

    link = %DataLink{
      label: "Source health event",
      target: :source_health_event,
      target_id: event.source_health_event_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :source_health_event
    assert row_value(inspector.rows, "Source health event") == event.source_health_event_id
    assert row_value(inspector.rows, "Logical source") == "telemetry"
    assert row_value(inspector.rows, "Data source") == "flight-questdb"
    assert row_value(inspector.rows, "Source binding") == "flight-telemetry"
    assert row_value(inspector.rows, "Replay run") == "replay-run-source-health"
    assert row_value(inspector.rows, "Event type") == "degraded"
    assert row_value(inspector.rows, "Source health") == "degraded"
    assert row_value(inspector.rows, "Previous source health") == "healthy"
    assert row_value(inspector.rows, "Reason") == "source_probe_failed"
    assert row_value(inspector.context_rows, "Logical source") == "events"
  end

  test "resolves source health operational events with semantic rows" do
    organization_id = "org-resolver-source-health-operational-event"
    mission_id = "mission-resolver-source-health-operational-event"
    replay_run_id = "replay-run-source-health-operational-event"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, _healthy_event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: organization_id,
                 mission_id: mission_id,
                 logical_source: :operational_observables,
                 data_source_id: "ops-questdb",
                 source_binding_id: "ops-binding",
                 realm: :replay,
                 dataset: "operational_observables_replay",
                 replay_run_id: replay_run_id,
                 source_health: :healthy,
                 reason: :source_probe_succeeded,
                 observed_at: ~U[2026-06-21 12:00:00Z]
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, source_health_event, _status} =
             SourceHealth.record_source_health(
               %{
                 source_health_event_id: "source-health-operational-event-resolver",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 logical_source: :operational_observables,
                 data_source_id: "ops-questdb",
                 source_binding_id: "ops-binding",
                 realm: :replay,
                 dataset: "operational_observables_replay",
                 replay_run_id: replay_run_id,
                 source_health: :degraded,
                 reason: :source_probe_failed,
                 observed_at: ~U[2026-06-21 12:02:00Z],
                 payload: %{probe_id: "probe-operational-event"}
               },
               invalidate_runtime_cache?: false
             )

    operational_event_id = Event.from_source_health_event(source_health_event).event_id
    assert {:ok, _operational_event} = Cadence.OperationalEvents.fetch_event(operational_event_id)

    link = %DataLink{
      label: "Source health operational event",
      target: :operational_event,
      target_id: operational_event_id,
      context: %{
        source_request_id: "events-request-source-health",
        logical_source: :events,
        data: %{
          realm: :replay,
          replay_run_id: replay_run_id,
          data_source_id: "ops-questdb",
          source_binding_id: "ops-binding"
        }
      },
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :operational_event
    assert inspector.target_id == operational_event_id
    assert row_value(inspector.rows, "Operational event") == operational_event_id

    assert row_value(inspector.rows, "Source health event") ==
             source_health_event.source_health_event_id

    assert row_value(inspector.rows, "Logical source") == "operational_observables"
    assert row_value(inspector.rows, "Data source") == "ops-questdb"
    assert row_value(inspector.rows, "Source binding") == "ops-binding"
    assert row_value(inspector.rows, "Realm") == "replay"
    assert row_value(inspector.rows, "Dataset") == "operational_observables_replay"
    assert row_value(inspector.rows, "Replay run") == replay_run_id
    assert row_value(inspector.rows, "Event type") == "degraded"
    assert row_value(inspector.rows, "Source health") == "degraded"
    assert row_value(inspector.rows, "Previous source health") == "healthy"
    assert row_value(inspector.rows, "Reason") == "source_probe_failed"
    assert row_value(inspector.rows, "Source payload") =~ "probe-operational-event"
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
  end

  test "resolves replay source health interval links within replay scope" do
    organization_id = "org-resolver-source-health-interval"
    mission_id = "mission-resolver-source-health-interval"
    replay_run_id = "replay-run-source-health-interval"
    persist_mission_scope(organization_id, mission_id)

    for {health, observed_at} <- [
          {:healthy, ~U[2026-07-11 12:00:00Z]},
          {:degraded, ~U[2026-07-11 12:02:00Z]}
        ] do
      assert {:ok, _event, _status} =
               SourceHealth.record_source_health(
                 %{
                   organization_id: organization_id,
                   mission_id: mission_id,
                   logical_source: :operational_observables,
                   data_source_id: "ops-replay",
                   source_binding_id: "ops-replay-binding",
                   realm: :replay,
                   dataset: "operational_observables_replay",
                   replay_run_id: replay_run_id,
                   source_health: health,
                   reason: :source_probe_completed,
                   observed_at: observed_at
                 },
                 invalidate_runtime_cache?: false
               )
    end

    [interval | _rest] =
      OperationalEvents.source_health_intervals(organization_id, mission_id,
        replay_run_id: replay_run_id,
        order: :asc
      )

    link = %DataLink{
      label: "Source health interval",
      target: :source_health_interval,
      target_id: interval.interval_id,
      context: %{
        logical_source: :operational_observables,
        data: %{
          realm: :replay,
          replay_run_id: replay_run_id,
          data_source_id: "ops-replay",
          source_binding_id: "ops-replay-binding"
        }
      },
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.target == :source_health_interval
    assert row_value(inspector.rows, "Operational interval") == interval.interval_id
    assert row_value(inspector.rows, "Kind") == "source_health"
    assert row_value(inspector.rows, "Source event") == interval.source_event_id
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
    assert related_link(inspector.related_links, :operational_event, interval.source_event_id)

    wrong_replay_link = put_in(link.context.data.replay_run_id, "another-replay-run")

    assert {:error, missing_inspector} =
             DataLinkResolver.resolve(wrong_replay_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert missing_inspector.status == :missing
  end

  test "resolves connection state operational events with semantic rows" do
    organization_id = "org-resolver-connection-state-operational-event"
    mission_id = "mission-resolver-connection-state-operational-event"
    replay_run_id = "replay-run-connection-state-operational-event"
    observed_at = ~U[2026-06-21 12:04:00Z]
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, persisted_event} =
             %{
               snapshot_id: "connection-state-operational-event-resolver",
               organization_id: organization_id,
               mission_id: mission_id,
               observable_id: "comms.transport.connection_state",
               resource_id: "transport-alpha",
               scope_kind: :transport,
               transport_id: "transport-alpha",
               source_endpoint_id: "endpoint-alpha",
               ground_station_id: "dss-14",
               adapter_key: :tcp_socket,
               connection_state: :degraded,
               normalized_state: :degraded,
               state: :degraded,
               replay_run_id: replay_run_id,
               observed_at: observed_at
             }
             |> Event.from_operational_observable_state_snapshot()
             |> OperationalEvents.persist_event()

    link = %DataLink{
      label: "Connection state operational event",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{
        source_request_id: "events-request-connection-state",
        logical_source: :events,
        data: %{
          realm: :replay,
          replay_run_id: replay_run_id,
          data_source_id: "ops-questdb",
          source_binding_id: "ops-binding"
        }
      },
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :operational_event
    assert inspector.target_id == persisted_event.event_id
    assert row_value(inspector.rows, "Operational event") == persisted_event.event_id

    assert row_value(inspector.rows, "Connection state snapshot") ==
             "connection-state-operational-event-resolver"

    assert row_value(inspector.rows, "Observed") ==
             DateTime.to_iso8601(persisted_event.occurred_at)

    assert row_value(inspector.rows, "Observable") == "comms.transport.connection_state"
    assert row_value(inspector.rows, "Resource") == "transport-alpha"
    assert row_value(inspector.rows, "Scope kind") == "transport"
    assert row_value(inspector.rows, "Transport") == "transport-alpha"
    assert row_value(inspector.rows, "Source endpoint") == "endpoint-alpha"
    assert row_value(inspector.rows, "Ground station") == "dss-14"
    assert row_value(inspector.rows, "Adapter") == "tcp_socket"
    assert row_value(inspector.rows, "Connection state") == "degraded"
    assert row_value(inspector.rows, "Normalized state") == "degraded"
    assert row_value(inspector.rows, "State") == "degraded"
    assert row_value(inspector.rows, "Replay run") == replay_run_id
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
  end
end
