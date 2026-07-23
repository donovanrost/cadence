defmodule Cadence.Dashboards.DataLinkResolverOperationalIntervalsTest do
  use Cadence.RuntimeCase, async: false

  import Cadence.Dashboards.DataLinkResolverFixtures

  alias Cadence.Commanding.{
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandVerifierInstance,
    CommandVerifierInstanceRow
  }

  alias Cadence.Dashboards.{DataLink, DataLinkResolver}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  alias Cadence.Repo

  test "resolves projected operational interval links from canonical events" do
    organization_id = "org-resolver-operational-interval"
    mission_id = "mission-resolver-operational-interval"
    activated_at = ~U[2026-06-21 20:00:00Z]
    persist_mission_scope(organization_id, mission_id)

    event =
      Event.new(%{
        event_id: "operational_event:binding_set_activation:resolver-interval-1",
        organization_id: organization_id,
        mission_id: mission_id,
        occurred_at: activated_at,
        recorded_at: activated_at,
        effective_at: activated_at,
        category: :runtime,
        kind: :binding_set_activated,
        severity: :info,
        actor: %{kind: :system},
        subject: %{kind: :binding_set, id: "runtime-basis"},
        causality: %{
          correlation_id: "runtime-basis",
          source_record_kind: :binding_set_activation,
          source_record_id: "activation-interval-1"
        },
        payload: %{
          binding_set_id: "runtime-basis",
          binding_set_version: 1,
          activation_id: "activation-interval-1"
        },
        current: %{state: :active}
      })

    assert {:ok, persisted_event} = OperationalEvents.persist_event(event)

    target_id = "effective_interval:binding_set:#{persisted_event.event_id}"

    link = %DataLink{
      label: "Binding set interval",
      target: :binding_set_interval,
      target_id: target_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :binding_set_interval
    assert row_value(inspector.rows, "Operational interval") == target_id
    assert row_value(inspector.rows, "Kind") == "binding_set"
    assert row_value(inspector.rows, "Subject") == "runtime-basis"
    assert row_value(inspector.rows, "Source event") == persisted_event.event_id

    assert related_link(
             inspector.related_links,
             :operational_event,
             persisted_event.event_id
           )
  end

  test "resolves application binding interval links with source endpoint handoffs" do
    organization_id = "org-resolver-application-binding-interval"
    mission_id = "mission-resolver-application-binding-interval"
    persist_mission_scope(organization_id, mission_id)
    persist_source_endpoint_scope(organization_id, mission_id, "endpoint-sc-001")

    binding_set =
      application_binding_set(mission_id, "runtime-apps-a",
        source_endpoint_ref: "endpoint-sc-001",
        apid: 42,
        metric_name: "packets_v1"
      )

    assert {:ok, _binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               organization_id,
               mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               activated_at: ~U[2026-06-21 20:00:00Z]
             )

    [interval] =
      OperationalEvents.application_binding_intervals(organization_id, mission_id,
        source_endpoint_ref: "endpoint-sc-001",
        order: :asc
      )

    link = %DataLink{
      label: "Application binding interval",
      target: :application_binding_interval,
      target_id: interval.interval_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :application_binding_interval
    assert row_value(inspector.rows, "Operational interval") == interval.interval_id
    assert row_value(inspector.rows, "Kind") == "application_binding"
    assert row_value(inspector.rows, "Subject") == "runtime-apps-a-packet-counter-rule"
    assert row_value(inspector.rows, "Source event") == interval.source_event_id

    assert related_link(inspector.related_links, :operational_event, interval.source_event_id)
    assert related_link(inspector.related_links, :source_endpoint, "endpoint-sc-001")
  end

  test "resolves catalog revision interval links from canonical revision events" do
    organization_id = "org-resolver-catalog-revision-interval"
    mission_id = "mission-resolver-catalog-revision-interval"
    persist_mission_scope(organization_id, mission_id)

    revision =
      catalog_revision(organization_id, mission_id, "catalog-revision-a",
        revision_number: 1,
        revision_label: "FSW 3.6",
        telemetry_snapshot_id: "telemetry-snapshot-a",
        import_run_id: "import-run-a"
      )

    assert {:ok, persisted_event} =
             revision
             |> Event.from_catalog_revision(~U[2026-06-21 20:00:00Z])
             |> OperationalEvents.persist_event()

    [interval] =
      OperationalEvents.catalog_revision_intervals(organization_id, mission_id,
        catalog_database_id: "bus-catalog",
        order: :asc
      )

    link = %DataLink{
      label: "Catalog revision interval",
      target: :catalog_revision_interval,
      target_id: interval.interval_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :catalog_revision_interval
    assert row_value(inspector.rows, "Operational interval") == interval.interval_id
    assert row_value(inspector.rows, "Kind") == "catalog_revision"
    assert row_value(inspector.rows, "Subject") == "catalog-revision-a"
    assert row_value(inspector.rows, "Source event") == persisted_event.event_id

    assert related_link(inspector.related_links, :operational_event, persisted_event.event_id)
  end

  test "resolves transport execution interval links with transport and contact handoffs" do
    organization_id = "org-resolver-transport-execution-interval"
    mission_id = "mission-resolver-transport-execution-interval"
    persist_mission_scope(organization_id, mission_id)
    persist_transport_execution_scope(organization_id, mission_id)

    assert {:ok, persisted_event} =
             transport_capability_record(
               mission_id,
               "transport-record-1",
               "uplink-heartbeat",
               :initialized,
               ~U[2026-06-30 12:00:00Z],
               state_snapshot: %{active?: true, heartbeat_count: 0}
             )
             |> Event.from_transport_capability_record()
             |> OperationalEvents.persist_event()

    [interval] =
      OperationalEvents.transport_execution_intervals(organization_id, mission_id,
        capability_instance_id: "uplink-heartbeat",
        order: :asc
      )

    link = %DataLink{
      label: "Transport execution interval",
      target: :transport_execution_interval,
      target_id: interval.interval_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :transport_execution_interval
    assert row_value(inspector.rows, "Operational interval") == interval.interval_id
    assert row_value(inspector.rows, "Kind") == "transport_execution"
    assert row_value(inspector.rows, "Subject") == "uplink-heartbeat"
    assert row_value(inspector.rows, "Source event") == persisted_event.event_id

    assert related_link(inspector.related_links, :operational_event, persisted_event.event_id)
    assert related_link(inspector.related_links, :transport, "uplink-heartbeat")
    assert related_link(inspector.related_links, :contact, "realized-contact-1")

    capability_link = %DataLink{
      label: "Transport capability record",
      target: :transport_capability_record,
      target_id: "transport-record-1",
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, capability_inspector} =
             DataLinkResolver.resolve(capability_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert capability_inspector.status == :resolved
    assert capability_inspector.target == :transport_capability_record

    assert row_value(capability_inspector.rows, "Transport capability record") ==
             "transport-record-1"

    assert row_value(capability_inspector.rows, "Operational event") == persisted_event.event_id
    assert row_value(capability_inspector.rows, "Capability instance") == "uplink-heartbeat"
    assert row_value(capability_inspector.rows, "State snapshot") =~ "heartbeat_count"

    assert related_link(
             capability_inspector.related_links,
             :operational_event,
             persisted_event.event_id
           )

    assert {:ok, persisted_action_event} =
             transport_action_request(
               mission_id,
               "transport-action-request-1",
               "uplink-heartbeat",
               :release_command,
               ~U[2026-06-30 12:00:30Z],
               request_document: %{command_request_id: "command-request-1", frame_count: 1},
               metadata: %{release_attempt_id: "release-attempt-1"}
             )
             |> Event.from_transport_action_request()
             |> OperationalEvents.persist_event()

    action_link = %DataLink{
      label: "Transport action request",
      target: :transport_action_request,
      target_id: "transport-action-request-1",
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, action_inspector} =
             DataLinkResolver.resolve(action_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert action_inspector.status == :resolved
    assert action_inspector.target == :transport_action_request

    assert row_value(action_inspector.rows, "Transport action request") ==
             "transport-action-request-1"

    assert row_value(action_inspector.rows, "Operational event") ==
             persisted_action_event.event_id

    assert row_value(action_inspector.rows, "Command release attempt") == "release-attempt-1"
    assert row_value(action_inspector.rows, "Command request") == "command-request-1"
    assert row_value(action_inspector.rows, "Request document") =~ "frame_count"

    assert related_link(
             action_inspector.related_links,
             :operational_event,
             persisted_action_event.event_id
           )

    release_attempt =
      CommandReleaseAttempt.new(%{
        command_release_attempt_id: "release-attempt-1",
        organization_id: organization_id,
        mission_id: mission_id,
        command_queue_entry_id: "command-queue-entry-1",
        command_request_id: "command-request-1",
        source_endpoint_ref: "source-endpoint-alpha",
        realized_contact_id: "realized-contact-1",
        path_id: "path-1",
        transport_binding_id: "transport-binding-1",
        command_snapshot_id: "command-snapshot-1",
        command_id: "noop-command",
        command_name: "NOOP",
        layout_kind: :ccsds_space_packet,
        preferred_uplink_service: "tc",
        apid: 42,
        service_type: 17,
        service_subtype: 1,
        opcode: %{kind: "noop"},
        encoded_binary_base64: Base.encode64("NOOP"),
        encoded_size_bytes: 4,
        lifecycle_state: :released,
        verification_state: :failed,
        released_by: %{user_id: "resolver-test"},
        attempted_at: ~U[2026-06-30 12:00:30Z],
        released_at: ~U[2026-06-30 12:00:31Z],
        metadata: %{transport_action_request_id: "transport-action-request-1"}
      })

    assert %CommandReleaseAttemptRow{} =
             Repo.insert!(CommandReleaseAttemptRow.changeset(release_attempt))

    verifier_instance =
      CommandVerifierInstance.new(%{
        command_verifier_instance_id: "verifier-instance-failed",
        organization_id: organization_id,
        mission_id: mission_id,
        command_request_id: "command-request-1",
        command_release_attempt_id: "release-attempt-1",
        source_endpoint_ref: "source-endpoint-alpha",
        command_snapshot_id: "command-snapshot-1",
        command_id: "noop-command",
        command_name: "NOOP",
        verifier_id: "transport-verifier-1",
        verifier_name: "Transport action rejected",
        phase: :start,
        severity: :error,
        lifecycle_state: :failed,
        matched_record_kind: :transport_action_request,
        matched_record_id: "transport-action-request-1",
        matched_at: ~U[2026-06-30 12:00:35Z],
        failure_reason: "failure_criteria_matched",
        metadata: %{transport_action_request_id: "transport-action-request-1"}
      })

    assert %CommandVerifierInstanceRow{} =
             Repo.insert!(CommandVerifierInstanceRow.changeset(verifier_instance))

    release_attempt_link = %DataLink{
      label: "Command release attempt",
      target: :command_release_attempt,
      target_id: "release-attempt-1",
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, release_attempt_inspector} =
             DataLinkResolver.resolve(release_attempt_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert release_attempt_inspector.status == :resolved
    assert release_attempt_inspector.target == :command_release_attempt

    assert row_value(release_attempt_inspector.rows, "Command release attempt") ==
             "release-attempt-1"

    assert row_value(release_attempt_inspector.rows, "Lifecycle state") == "released"
    assert row_value(release_attempt_inspector.rows, "Verification state") == "failed"
    assert row_value(release_attempt_inspector.rows, "Command request") == "command-request-1"
    assert row_value(release_attempt_inspector.rows, "Command") == "NOOP"
    assert row_value(release_attempt_inspector.rows, "Source endpoint") == "source-endpoint-alpha"

    assert row_value(release_attempt_inspector.rows, "Transport action request") ==
             "transport-action-request-1"

    assert row_value(release_attempt_inspector.rows, "Signal phase") == "start"
    assert row_value(release_attempt_inspector.rows, "Metadata") =~ "transport_action_request_id"

    assert related_link(
             release_attempt_inspector.related_links,
             :command_request,
             "command-request-1"
           )

    assert related_link(
             release_attempt_inspector.related_links,
             :command_queue_entry,
             "command-queue-entry-1"
           )

    assert related_link(
             release_attempt_inspector.related_links,
             :transport_action_request,
             "transport-action-request-1"
           )

    assert related_link(
             release_attempt_inspector.related_links,
             :command_verifier_instance,
             "verifier-instance-failed"
           )

    verifier_link = %DataLink{
      label: "Command verifier instance",
      target: :command_verifier_instance,
      target_id: "verifier-instance-failed",
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, verifier_inspector} =
             DataLinkResolver.resolve(verifier_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert verifier_inspector.status == :resolved
    assert verifier_inspector.target == :command_verifier_instance

    assert row_value(verifier_inspector.rows, "Command verifier instance") ==
             "verifier-instance-failed"

    assert row_value(verifier_inspector.rows, "Lifecycle state") == "failed"
    assert row_value(verifier_inspector.rows, "Matched record kind") == "transport_action_request"
    assert row_value(verifier_inspector.rows, "Matched record") == "transport-action-request-1"
    assert row_value(verifier_inspector.rows, "Failure reason") == "failure_criteria_matched"
    assert row_value(verifier_inspector.rows, "Command release attempt") == "release-attempt-1"

    assert related_link(
             verifier_inspector.related_links,
             :command_release_attempt,
             "release-attempt-1"
           )

    assert related_link(
             verifier_inspector.related_links,
             :command_request,
             "command-request-1"
           )

    assert related_link(
             verifier_inspector.related_links,
             :transport_action_request,
             "transport-action-request-1"
           )
  end

  test "resolves replay-scoped native RF interval links from link context" do
    organization_id = "org-resolver-replay-rf-interval"
    mission_id = "mission-resolver-replay-rf-interval"
    replay_run_id = "resolver-replay-run-1"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, _live_event} =
             %{
               snapshot_id: "frame-sync-live",
               organization_id: organization_id,
               mission_id: mission_id,
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               link_id: "link-alpha",
               source_endpoint_id: "endpoint-alpha",
               ground_station_id: "dss-14",
               state: :acquiring,
               observed_at: ~U[2026-06-30 12:00:00Z]
             }
             |> Event.from_operational_observable_state_snapshot()
             |> OperationalEvents.persist_event()

    assert {:ok, _replay_event} =
             %{
               snapshot_id: "frame-sync-replay",
               organization_id: organization_id,
               mission_id: mission_id,
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               link_id: "link-alpha",
               source_endpoint_id: "endpoint-alpha",
               ground_station_id: "dss-14",
               state: :synchronized,
               replay_run_id: replay_run_id,
               observed_at: ~U[2026-06-30 12:05:00Z]
             }
             |> Event.from_operational_observable_state_snapshot()
             |> OperationalEvents.persist_event()

    [replay_interval] =
      OperationalEvents.link_rf_state_intervals(organization_id, mission_id,
        rf_state_family: :frame_sync,
        replay_run_id: replay_run_id
      )

    link = %DataLink{
      label: "Frame sync interval",
      target: :link_frame_sync_state_interval,
      target_id: replay_interval.interval_id,
      context: %{source_request_id: "rf-request-1", logical_source: :operational_observables},
      source: :frame
    }

    assert {:error, live_inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert live_inspector.status == :missing

    replay_link = %DataLink{
      link
      | context:
          Map.merge(link.context, %{
            data: %{realm: :replay, replay_run_id: replay_run_id},
            time: %{mode: :replay_run, replay_run_id: replay_run_id}
          })
    }

    assert {:ok, replay_inspector} =
             DataLinkResolver.resolve(replay_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert replay_inspector.status == :resolved
    assert replay_inspector.target == :link_frame_sync_state_interval
    assert row_value(replay_inspector.rows, "Operational interval") == replay_interval.interval_id
    assert row_value(replay_inspector.rows, "Kind") == "link_frame_sync_state"
    assert row_value(replay_inspector.rows, "Subject") == "link-alpha"
    assert row_value(replay_inspector.rows, "Source event") == replay_interval.source_event_id
    assert row_value(replay_inspector.context_rows, "Replay run") == replay_run_id

    assert related_link(
             replay_inspector.related_links,
             :operational_event,
             replay_interval.source_event_id
           )
  end

  test "resolves RF state operational events with semantic rows" do
    organization_id = "org-resolver-rf-state-operational-event"
    mission_id = "mission-resolver-rf-state-operational-event"
    replay_run_id = "replay-run-rf-state-operational-event"
    observed_at = ~U[2026-06-30 12:07:00Z]
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, persisted_event} =
             %{
               snapshot_id: "rf-state-operational-event-resolver",
               organization_id: organization_id,
               mission_id: mission_id,
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               transport_id: "transport-alpha",
               source_endpoint_id: "endpoint-alpha",
               ground_station_id: "dss-14",
               link_id: "link-alpha",
               state: :locked,
               replay_run_id: replay_run_id,
               observed_at: observed_at
             }
             |> Event.from_operational_observable_state_snapshot()
             |> OperationalEvents.persist_event()

    link = %DataLink{
      label: "RF state operational event",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{
        source_request_id: "events-request-rf-state",
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
    assert row_value(inspector.rows, "RF state snapshot") == "rf-state-operational-event-resolver"
    assert row_value(inspector.rows, "Observable") == "link.rf_lock_state"
    assert row_value(inspector.rows, "Resource") == "link-alpha"
    assert row_value(inspector.rows, "Link") == "link-alpha"
    assert row_value(inspector.rows, "RF state") == "locked"
    assert row_value(inspector.rows, "Replay run") == replay_run_id
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
  end

  test "resolves antenna pointing operational events with semantic rows" do
    organization_id = "org-resolver-antenna-pointing-operational-event"
    mission_id = "mission-resolver-antenna-pointing-operational-event"
    replay_run_id = "replay-run-antenna-pointing-operational-event"
    observed_at = ~U[2026-06-30 12:09:00Z]
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, persisted_event} =
             %{
               snapshot_id: "antenna-pointing-operational-event-resolver",
               organization_id: organization_id,
               mission_id: mission_id,
               observable_id: "ground.station.antenna_pointing_state",
               resource_id: "dss-14",
               scope_kind: :ground_station,
               transport_id: "transport-alpha",
               source_endpoint_id: "endpoint-alpha",
               ground_station_id: "dss-14",
               state: :tracking,
               replay_run_id: replay_run_id,
               observed_at: observed_at
             }
             |> Event.from_operational_observable_state_snapshot()
             |> OperationalEvents.persist_event()

    link = %DataLink{
      label: "Antenna pointing operational event",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{
        source_request_id: "events-request-antenna-pointing",
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

    assert row_value(inspector.rows, "Operational observable snapshot") ==
             "antenna-pointing-operational-event-resolver"

    assert row_value(inspector.rows, "Observable") == "ground.station.antenna_pointing_state"
    assert row_value(inspector.rows, "Resource") == "dss-14"
    assert row_value(inspector.rows, "Ground station") == "dss-14"
    assert row_value(inspector.rows, "State") == "tracking"
    assert row_value(inspector.rows, "Replay run") == replay_run_id
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
  end

  test "resolves metric sample operational events with semantic rows" do
    organization_id = "org-resolver-metric-sample-operational-event"
    mission_id = "mission-resolver-metric-sample-operational-event"
    replay_run_id = "replay-run-metric-sample-operational-event"
    observed_at = ~U[2026-06-30 12:11:00Z]
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, persisted_event} =
             %{
               sample_id: "metric-sample-operational-event-resolver",
               organization_id: organization_id,
               mission_id: mission_id,
               observable_id: "link.snr_db",
               resource_id: "link-alpha",
               scope_kind: :link,
               transport_id: "transport-alpha",
               source_endpoint_id: "endpoint-alpha",
               ground_station_id: "dss-14",
               link_id: "link-alpha",
               value: 12.25,
               unit: "dB",
               replay_run_id: replay_run_id,
               observed_at: observed_at
             }
             |> Event.from_operational_observable_metric_sample()
             |> OperationalEvents.persist_event()

    link = %DataLink{
      label: "Metric sample operational event",
      target: :operational_event,
      target_id: persisted_event.event_id,
      context: %{
        source_request_id: "events-request-metric-sample",
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

    assert row_value(inspector.rows, "Operational metric sample") ==
             "metric-sample-operational-event-resolver"

    assert row_value(inspector.rows, "Observable") == "link.snr_db"
    assert row_value(inspector.rows, "Resource") == "link-alpha"
    assert row_value(inspector.rows, "Link") == "link-alpha"
    assert row_value(inspector.rows, "Value") == "12.250"
    assert row_value(inspector.rows, "Unit") == "dB"
    assert row_value(inspector.rows, "Replay run") == replay_run_id
    assert row_value(inspector.context_rows, "Replay run") == replay_run_id
  end
end
