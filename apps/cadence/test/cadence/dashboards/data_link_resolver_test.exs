defmodule Cadence.Dashboards.DataLinkResolverTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Catalog.Revision
  alias Cadence.Comms.{GroundStation, RoutingRule, Transport}
  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact}

  alias Cadence.Dashboards.{
    DashboardAction,
    DataBinding,
    DataLink,
    DataLinkInspector,
    DataLinkResolver,
    DataSource,
    DataSources,
    LifecycleEvent,
    SourceHealth,
    SourceWatermarks
  }

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandVerifierInstance
  }

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.{Definition, DefinitionLifecycle}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow

  alias Cadence.Dashboards.DocumentStore.LifecycleEventRow,
    as: DashboardLifecycleEventRow

  alias Cadence.Runtime.{
    ManagedActionRequest,
    ManagedCapabilityRecord,
    TransportActionRequest,
    TransportCapabilityRecord
  }

  alias Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionEventRow,
    as: TelemetryObservationIdentityDecisionEventRow

  alias Cadence.Persistence.Schemas.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandVerifierInstanceRow,
    TelemetrySampleRow
  }

  alias Cadence.Projections.MissionEvents
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.Storage
  alias Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent

  test "resolves command queue entry links from persisted mission-scoped queue rows" do
    organization_id = "org-command-queue-entry-link"
    mission_id = "mission-command-queue-entry-link"
    persist_mission_scope(organization_id, mission_id)

    queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: "queue-entry-1",
        organization_id: organization_id,
        mission_id: mission_id,
        command_request_id: "command-request-1",
        source_endpoint_ref: "source-endpoint-alpha",
        queue_lane_key: "source-endpoint-alpha",
        priority: 2,
        queue_sequence: 7,
        lifecycle_state: :pending,
        enqueued_by: %{user_id: "resolver-test"},
        enqueued_at: ~U[2026-06-30 12:00:00Z],
        metadata: %{transport_action_request_id: "transport-action-request-1"}
      })

    command_request =
      CommandRequest.new(%{
        command_request_id: "command-request-1",
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_ref: "source-endpoint-alpha",
        command_snapshot_id: "command-snapshot-1",
        command_id: "noop-command",
        command_name: "NOOP",
        command_display_name: "NOOP",
        lifecycle_state: :queued,
        priority: 2,
        requested_by: %{user_id: "resolver-test"},
        requested_at: ~U[2026-06-30 11:59:00Z],
        metadata: %{}
      })

    assert %CommandRequestRow{} = Repo.insert!(CommandRequestRow.changeset(command_request))

    assert %CommandQueueEntryRow{} =
             Repo.insert!(CommandQueueEntryRow.changeset(queue_entry))

    release_attempt =
      CommandReleaseAttempt.new(%{
        command_release_attempt_id: "release-attempt-1",
        organization_id: organization_id,
        mission_id: mission_id,
        command_queue_entry_id: "queue-entry-1",
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
        verification_state: :pending,
        released_by: %{user_id: "resolver-test"},
        attempted_at: ~U[2026-06-30 12:00:30Z],
        released_at: ~U[2026-06-30 12:00:31Z],
        metadata: %{}
      })

    assert %CommandReleaseAttemptRow{} =
             Repo.insert!(CommandReleaseAttemptRow.changeset(release_attempt))

    link = %DataLink{
      label: "Command queue entry",
      target: :command_queue_entry,
      target_id: "queue-entry-1",
      context: %{source_request_id: "events-request-1", logical_source: :operational_observables},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :command_queue_entry
    assert row_value(inspector.rows, "Command queue entry") == "queue-entry-1"
    assert row_value(inspector.rows, "Lifecycle state") == "pending"
    assert row_value(inspector.rows, "Command request") == "command-request-1"
    assert row_value(inspector.rows, "Source endpoint") == "source-endpoint-alpha"
    assert row_value(inspector.rows, "Queue lane") == "source-endpoint-alpha"
    assert row_value(inspector.rows, "Priority") == "2"
    assert row_value(inspector.rows, "Queue sequence") == "7"
    assert row_value(inspector.rows, "Enqueued at") =~ "2026-06-30T12:00:00"
    assert row_value(inspector.rows, "Enqueued by") =~ "resolver-test"
    assert row_value(inspector.rows, "Metadata") =~ "transport-action-request-1"

    assert related_link(inspector.related_links, :command_request, "command-request-1")

    request_link = %DataLink{
      label: "Command request",
      target: :command_request,
      target_id: "command-request-1",
      context: %{source_request_id: "events-request-1", logical_source: :operational_observables},
      source: :annotation
    }

    assert {:ok, request_inspector} =
             DataLinkResolver.resolve(request_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert request_inspector.status == :resolved
    assert request_inspector.target == :command_request
    assert row_value(request_inspector.rows, "Command request") == "command-request-1"
    assert row_value(request_inspector.rows, "Lifecycle state") == "queued"
    assert row_value(request_inspector.rows, "Source endpoint") == "source-endpoint-alpha"
    assert row_value(request_inspector.rows, "Command") == "NOOP"
    assert row_value(request_inspector.rows, "Command display name") == "NOOP"
    assert row_value(request_inspector.rows, "Command id") == "noop-command"
    assert row_value(request_inspector.rows, "Command snapshot") == "command-snapshot-1"
    assert row_value(request_inspector.rows, "Priority") == "2"
    assert row_value(request_inspector.rows, "Requested at") =~ "2026-06-30T11:59:00"
    assert row_value(request_inspector.rows, "Requested by") =~ "resolver-test"
    assert related_link(request_inspector.related_links, :command_queue_entry, "queue-entry-1")

    assert related_link(
             request_inspector.related_links,
             :command_release_attempt,
             "release-attempt-1"
           )
  end

  test "resolves telemetry sample links from persisted mission-scoped samples" do
    %{
      organization_id: organization_id,
      mission_id: mission_id,
      sample_id: sample_id,
      evidence_id: evidence_id
    } = persist_sample_scope!("resolver-sample", 41)

    link = %DataLink{
      link_id: "telemetry_sample:#{sample_id}:source-request-1",
      label: "Telemetry sample",
      target: :telemetry_sample,
      target_id: sample_id,
      context: %{
        source_request_id: "source-request-1",
        logical_source: :telemetry,
        observable_id: "HK.counter",
        time: %{axis: :receipt_time},
        data: %{
          realm: :flight,
          view: :all_revisions,
          data_source_id: "flight-tsdb",
          source_binding_id: "flight-binding"
        },
        selection: %{
          series_role: :compare,
          compare_of: "HK.counter"
        }
      },
      source: :warning
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert %DataLinkInspector{} = inspector
    assert inspector.status == :resolved
    assert inspector.target == :telemetry_sample
    assert inspector.link_id == "telemetry_sample:#{sample_id}:source-request-1"

    assert inspector.source_context == %{
             realm: "flight",
             data_view: "all_revisions",
             data_source_id: "flight-tsdb",
             source_binding_id: "flight-binding",
             time_axis: "receipt_time"
           }

    assert row_value(inspector.rows, "Sample") == sample_id
    assert row_value(inspector.rows, "Point") == "HK.counter"
    assert row_value(inspector.rows, "Raw") == "41"
    assert row_value(inspector.context_rows, "Source request") == "source-request-1"
    assert row_value(inspector.context_rows, "Data realm") == "flight"
    assert row_value(inspector.context_rows, "Data view") == "all_revisions"
    assert row_value(inspector.context_rows, "Series role") == "compare"
    assert row_value(inspector.context_rows, "Compare of") == "HK.counter"
    assert row_value(inspector.context_rows, "Data source") == "flight-tsdb"
    assert row_value(inspector.context_rows, "Source binding") == "flight-binding"

    assert [
             %DashboardAction{
               target: :telemetry_explore,
               kind: :invoke,
               query: %{
                 "point_id" => "HK.counter",
                 "sample_id" => ^sample_id,
                 "realm" => "flight",
                 "data_view" => "all_revisions",
                 "data_source_id" => "flight-tsdb",
                 "source_binding_id" => "flight-binding"
               },
               source: :data_link_panel
             }
           ] = inspector.actions

    assert related_link(inspector.related_links, :telemetry_point, "HK.counter")
    evidence_link = related_link(inspector.related_links, :raw_evidence, evidence_id)
    assert %DataLink{} = evidence_link

    assert {:ok, evidence_inspector} =
             DataLinkResolver.resolve(evidence_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert evidence_inspector.status == :resolved
    assert row_value(evidence_inspector.rows, "Evidence") == evidence_id
    assert row_value(evidence_inspector.rows, "Raw bytes") == "8"
    assert row_value(evidence_inspector.context_rows, "Data source") == "flight-tsdb"
    assert row_value(evidence_inspector.context_rows, "Source binding") == "flight-binding"
    assert related_link(evidence_inspector.related_links, :telemetry_sample, sample_id)
  end

  test "resolves comparison finding links from dashboard runtime context" do
    link = %DataLink{
      label: "Comparison finding",
      target: :comparison_finding,
      target_id: "placement-1",
      context: %{
        time: %{mode: :archive, axis: :generation_time},
        data: %{
          realm: :flight,
          view: :all_revisions,
          data_source_id: "flight-tsdb",
          source_binding_id: "flight-binding"
        },
        comparison: %{
          state: :increased,
          delta: "+2",
          primary_sample_id: "sample-primary-1",
          compare_sample_id: "sample-compare-1",
          primary_data_view: :all_revisions,
          compare_data_view: :canonical,
          primary_data_management: "recomputed_analysis",
          compare_data_management: "degraded",
          primary_count: 1,
          compare_count: 1,
          widget_id: "widget-1",
          widget_title: "Counter"
        }
      },
      source: :annotation
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: "org-comparison-finding",
               mission_id: "mission-comparison-finding"
             )

    assert inspector.status == :context_only
    assert inspector.target == :comparison_finding
    assert row_value(inspector.rows, "Comparison finding") == "placement-1"
    assert row_value(inspector.rows, "State") == "increased"
    assert row_value(inspector.rows, "Delta") == "+2"
    assert row_value(inspector.rows, "Primary sample") == "sample-primary-1"
    assert row_value(inspector.rows, "Compare sample") == "sample-compare-1"
    assert row_value(inspector.rows, "Primary data view") == "all_revisions"
    assert row_value(inspector.rows, "Compare data view") == "canonical"
    assert row_value(inspector.rows, "Primary data management") == "recomputed_analysis"
    assert row_value(inspector.rows, "Compare data management") == "degraded"
    assert row_value(inspector.context_rows, "Data realm") == "flight"
    assert row_value(inspector.context_rows, "Data view") == "all_revisions"

    assert [
             %DataLink{target: :telemetry_sample, target_id: "sample-primary-1"},
             %DataLink{target: :telemetry_sample, target_id: "sample-compare-1"}
           ] = inspector.related_links
  end

  test "resolves comparison finding links with observation identity context from linked samples" do
    %{
      organization_id: organization_id,
      mission_id: mission_id,
      primary_sample_id: primary_sample_id,
      compare_sample_id: compare_sample_id
    } = persist_comparison_samples!("resolver-comparison-identity")

    attach_storage_provenance!(primary_sample_id, %{
      "observation_identity_id" => "identity-primary-1",
      "observation_id" => "observation-primary-1",
      "validity_state" => "conflict",
      "revision" => 2,
      "realm" => "flight",
      "data_source_id" => "flight-tsdb",
      "binding_id" => "flight-binding",
      "observable_id" => "HK.counter"
    })

    attach_storage_provenance!(compare_sample_id, %{
      "observation_identity_id" => "identity-compare-1",
      "observation_id" => "observation-compare-1",
      "validity_state" => "canonical",
      "revision" => 1,
      "realm" => "flight",
      "data_source_id" => "flight-tsdb",
      "binding_id" => "flight-binding",
      "observable_id" => "HK.counter"
    })

    link = %DataLink{
      label: "Comparison finding",
      target: :comparison_finding,
      target_id: "placement-identity-1",
      context: %{
        observable_id: "HK.counter",
        data: %{
          realm: :flight,
          view: :all_revisions,
          data_source_id: "flight-tsdb",
          source_binding_id: "flight-binding"
        },
        comparison: %{
          state: :changed,
          delta: "+1",
          primary_sample_id: primary_sample_id,
          compare_sample_id: compare_sample_id,
          primary_data_view: :all_revisions,
          compare_data_view: :canonical,
          primary_count: 1,
          compare_count: 1,
          widget_id: "widget-identity-1",
          widget_title: "Counter"
        }
      },
      source: :annotation
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :context_only
    assert row_value(inspector.rows, "Observation identity") == "identity-primary-1"
    assert row_value(inspector.rows, "Realm") == "flight"
    assert row_value(inspector.rows, "Data source") == "flight-tsdb"
    assert row_value(inspector.rows, "Source binding") == "flight-binding"
    assert row_value(inspector.rows, "Decision reason") == "dashboard_comparison_finding"
    assert row_value(inspector.rows, "Correction authority") == "comparison"
    assert row_value(inspector.rows, "New canonical observation") == "observation-primary-1"
    assert row_value(inspector.rows, "New canonical sample") == primary_sample_id
    assert row_value(inspector.rows, "New canonical revision") == "2"
    assert row_value(inspector.rows, "New validity state") == "conflict"
    assert row_value(inspector.rows, "Previous canonical observation") == "observation-compare-1"
    assert row_value(inspector.rows, "Previous canonical sample") == compare_sample_id
    assert row_value(inspector.rows, "Previous canonical revision") == "1"
    assert row_value(inspector.rows, "Previous validity state") == "canonical"
  end

  test "does not resolve telemetry samples outside the requested organization and mission" do
    %{sample_id: sample_id} = persist_sample_scope!("resolver-scope-a", 12)
    persist_mission_scope("org-resolver-scope-b", "mission-resolver-scope-b")

    link = %DataLink{label: "Telemetry sample", target: :telemetry_sample, target_id: sample_id}

    assert {:error, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: "org-resolver-scope-b",
               mission_id: "mission-resolver-scope-b"
             )

    assert inspector.status == :missing
    assert inspector.target_id == sample_id
  end

  test "surfaces replay context on context-only telemetry point links" do
    organization_id = "org-resolver-replay-context"
    mission_id = "mission-resolver-replay-context"
    persist_mission_scope(organization_id, mission_id)

    link = %DataLink{
      label: "Telemetry point",
      target: :telemetry_point,
      target_id: "HK.counter",
      context: %{
        logical_source: :telemetry,
        observable_id: "HK.counter",
        time: %{mode: :replay_run, replay_run_id: "replay-run-1"},
        data: %{
          realm: :replay,
          replay_run_id: "replay-run-1",
          data_source_id: "replay-tsdb",
          source_binding_id: "replay-binding"
        }
      },
      source: :warning
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :context_only
    assert row_value(inspector.context_rows, "Time mode") == "replay_run"
    assert row_value(inspector.context_rows, "Replay run") == "replay-run-1"
    assert row_value(inspector.context_rows, "Data realm") == "replay"

    assert [
             %DashboardAction{
               target: :telemetry_explore,
               query: %{
                 "point_id" => "HK.counter",
                 "time_mode" => "replay_run",
                 "replay_run_id" => "replay-run-1",
                 "realm" => "replay",
                 "data_source_id" => "replay-tsdb",
                 "source_binding_id" => "replay-binding"
               }
             }
           ] = inspector.actions
  end

  test "resolves operational resource links for transport source endpoint and ground station" do
    organization_id = "org-resolver-operational-resources"
    mission_id = "mission-resolver-operational-resources"
    persist_mission_scope(organization_id, mission_id)

    transport =
      Transport.new(%{
        mission_id: mission_id,
        transport_id: "transport-alpha",
        display_name: "Lab TCP",
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => "endpoint-alpha",
          "ground_station_id" => "dss-14",
          "link_assignment_id" => "link-alpha"
        }
      })

    source_endpoint =
      SourceEndpoint.new(%{
        mission_id: mission_id,
        source_endpoint_id: "endpoint-alpha",
        display_name: "Goldstone DSS-14",
        metadata: %{"ground_station_id" => "dss-14", "link_assignment_id" => "link-alpha"}
      })

    ground_station =
      GroundStation.new(%{
        mission_id: mission_id,
        ground_station_id: "dss-14",
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "goldstone",
        metadata: %{
          "transport_id" => "transport-alpha",
          "source_endpoint_id" => "endpoint-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(organization_id, transport)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(organization_id, source_endpoint)

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(organization_id, ground_station)

    context = %{
      source_request_id: "ops-request-1",
      logical_source: :operational_observables,
      observable_id: "comms.transport.connection_state",
      data: %{
        realm: :flight,
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables"
      },
      operational_resource: %{
        resource_id: "transport-alpha",
        scope_kind: :transport,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket
      }
    }

    assert {:ok, transport_inspector} =
             DataLinkResolver.resolve(
               %DataLink{
                 label: "Transport",
                 target: :transport,
                 target_id: "transport-alpha",
                 context: context,
                 source: :frame
               },
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert transport_inspector.status == :resolved
    assert row_value(transport_inspector.rows, "Transport") == "transport-alpha"
    assert row_value(transport_inspector.rows, "Source endpoint") == "endpoint-alpha"
    assert row_value(transport_inspector.rows, "Ground station") == "dss-14"
    assert row_value(transport_inspector.rows, "Link") == "link-alpha"

    assert related_link(transport_inspector.related_links, :source_endpoint, "endpoint-alpha")
    assert related_link(transport_inspector.related_links, :ground_station, "dss-14")

    assert %DashboardAction{
             label: "View source inventory",
             target: :source_inventory,
             kind: :invoke,
             query: %{
               "selected_target" => "transport",
               "selected_id" => "transport-alpha",
               "transport_id" => "transport-alpha",
               "source_endpoint_id" => "endpoint-alpha",
               "ground_station_id" => "dss-14",
               "link_id" => "link-alpha",
               "realm" => "flight",
               "data_source_id" => "managed_operational_observables",
               "source_binding_id" => "default_flight_operational_observables",
               "logical_source" => "operational_observables"
             },
             source: :data_link_panel
           } = action_for(transport_inspector.actions, :source_inventory)

    assert action_for(transport_inspector.actions, :source_health).query == %{
             "realm" => "flight",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "logical_source" => "operational_observables"
           }

    assert {:ok, source_endpoint_inspector} =
             DataLinkResolver.resolve(
               %DataLink{
                 label: "Source endpoint",
                 target: :source_endpoint,
                 target_id: "endpoint-alpha",
                 context: context,
                 source: :frame
               },
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert source_endpoint_inspector.status == :resolved
    assert row_value(source_endpoint_inspector.rows, "Source endpoint") == "endpoint-alpha"
    assert row_value(source_endpoint_inspector.rows, "Ground station") == "dss-14"
    assert row_value(source_endpoint_inspector.rows, "Link") == "link-alpha"
    assert related_link(source_endpoint_inspector.related_links, :transport, "transport-alpha")
    assert related_link(source_endpoint_inspector.related_links, :ground_station, "dss-14")

    assert {:ok, ground_station_inspector} =
             DataLinkResolver.resolve(
               %DataLink{
                 label: "Ground station",
                 target: :ground_station,
                 target_id: "dss-14",
                 context: context,
                 source: :frame
               },
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert ground_station_inspector.status == :resolved
    assert row_value(ground_station_inspector.rows, "Ground station") == "dss-14"
    assert row_value(ground_station_inspector.rows, "Display name") == "Goldstone DSS-14"
    assert row_value(ground_station_inspector.rows, "Provider") == "DSN"
    assert row_value(ground_station_inspector.rows, "Transport") == "transport-alpha"
    assert row_value(ground_station_inspector.rows, "Source endpoint") == "endpoint-alpha"
    assert related_link(ground_station_inspector.related_links, :transport, "transport-alpha")

    assert related_link(
             ground_station_inspector.related_links,
             :source_endpoint,
             "endpoint-alpha"
           )
  end

  test "resolves link assignment links through durable routing rule setup context" do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    organization_id = "org-resolver-link-assignment-#{suffix}"
    mission_id = "mission-resolver-link-assignment-#{suffix}"
    spacecraft_id = "spacecraft-alpha-#{suffix}"
    transport_id = "transport-alpha-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        display_name: "Alpha",
        scid: 42
      })

    assert {:ok, spacecraft} = Cadence.persist_spacecraft(organization_id, spacecraft)

    transport =
      Transport.new(%{
        mission_id: mission_id,
        transport_id: transport_id,
        display_name: "Lab TCP",
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      })

    assert {:ok, transport} = Cadence.persist_transport(organization_id, transport)

    routing_rule =
      RoutingRule.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Alpha live telemetry via Lab TCP",
        purpose_label: "Live telemetry",
        direction: :inbound,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        role: :primary
      })

    assert {:ok, routing_rule} = Cadence.create_routing_rule(organization_id, routing_rule)
    assert is_binary(routing_rule.materialized_link_assignment_id)
    link_assignment_id = routing_rule.materialized_link_assignment_id
    source_endpoint_id = "spacecraft_runtime:#{spacecraft_id}"

    link = %DataLink{
      label: "Link",
      target: :link,
      target_id: link_assignment_id,
      context: %{
        source_request_id: "ops-link-request-1",
        logical_source: :operational_observables,
        data: %{
          realm: :flight,
          data_source_id: "managed_operational_observables",
          source_binding_id: "default_flight_operational_observables"
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
    assert row_value(inspector.rows, "Link") == link_assignment_id
    assert row_value(inspector.rows, "Spacecraft") == spacecraft.spacecraft_id
    assert row_value(inspector.rows, "Source endpoint") == source_endpoint_id
    assert row_value(inspector.rows, "Routing rule") == routing_rule.routing_rule_id
    assert row_value(inspector.rows, "Routing purpose") == "Live telemetry"
    assert row_value(inspector.rows, "Transport") == transport.transport_id

    assert related_link(inspector.related_links, :transport, transport.transport_id)
    assert related_link(inspector.related_links, :source_endpoint, source_endpoint_id)

    assert %DashboardAction{
             target: :source_inventory,
             query: %{
               "selected_target" => "link",
               "selected_id" => ^link_assignment_id,
               "transport_id" => ^transport_id,
               "source_endpoint_id" => ^source_endpoint_id,
               "link_id" => ^link_assignment_id,
               "realm" => "flight",
               "data_source_id" => "managed_operational_observables",
               "source_binding_id" => "default_flight_operational_observables",
               "logical_source" => "operational_observables"
             }
           } = action_for(inspector.actions, :source_inventory)

    assert %DashboardAction{
             label: "View routing rule",
             target: :routing_rule,
             query: %{"routing_rule_id" => routing_rule_id}
           } = action_for(inspector.actions, :routing_rule)

    assert routing_rule_id == routing_rule.routing_rule_id
  end

  test "resolves limit event and limit definition links" do
    %{organization_id: organization_id, mission_id: mission_id, sample_id: sample_id} =
      persist_sample_scope!("resolver-limits", 25)

    definition =
      Definition.new(%{
        mission_id: mission_id,
        limit_definition_id: "counter-limits",
        point_id: "HK.counter",
        thresholds: %{"yellow_high" => 10, "red_high" => 20}
      })

    assert {:ok, _definition} = Cadence.persist_limit_definition(definition)
    assert {:ok, _run} = Cadence.evaluate_telemetry_limits(mission_id)

    event = Cadence.latest_telemetry_limit_state(organization_id, mission_id, "HK.counter", [])

    event_link = %DataLink{
      label: "Limit event",
      target: :limit_event,
      target_id: event.limit_event_id,
      context: %{source_request_id: "limits-request-1", observable_id: "HK.counter"},
      source: :warning
    }

    definition_link = %DataLink{
      label: "Limit definition",
      target: :limit_definition,
      target_id: "counter-limits",
      context: %{source_request_id: "limits-request-1", observable_id: "HK.counter"},
      source: :warning
    }

    assert {:ok, event_inspector} =
             DataLinkResolver.resolve(event_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert event_inspector.status == :resolved
    assert row_value(event_inspector.rows, "Limit event") == event.limit_event_id
    assert row_value(event_inspector.rows, "Normalized state") == "red"
    assert row_value(event_inspector.rows, "Violation") == "true"
    assert related_link(event_inspector.related_links, :telemetry_sample, sample_id)
    assert related_link(event_inspector.related_links, :limit_definition, "counter-limits")

    sample_link = %DataLink{
      label: "Telemetry sample",
      target: :telemetry_sample,
      target_id: sample_id,
      context: %{source_request_id: "limits-request-1", observable_id: "HK.counter"},
      source: :warning
    }

    assert {:ok, sample_inspector} =
             DataLinkResolver.resolve(sample_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert related_link(sample_inspector.related_links, :limit_event, event.limit_event_id)

    assert {:ok, definition_inspector} =
             DataLinkResolver.resolve(definition_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert definition_inspector.status == :resolved
    assert row_value(definition_inspector.rows, "Definition") == "counter-limits"
    assert row_value(definition_inspector.rows, "Point") == "HK.counter"
    assert row_value(definition_inspector.rows, "Version") == "1"
    assert related_link(definition_inspector.related_links, :telemetry_point, "HK.counter")
  end

  test "resolves limit definition lifecycle event links from persisted activations" do
    organization_id = "org-resolver-limit-lifecycle"
    mission_id = "mission-resolver-limit-lifecycle"
    persist_mission_scope(organization_id, mission_id)

    first_definition =
      Definition.new(%{
        mission_id: mission_id,
        limit_definition_id: "counter-limits-lifecycle",
        point_id: "HK.counter",
        version: 1,
        limit_set_name: "ops",
        thresholds: %{"yellow_high" => 10}
      })

    replacement_definition =
      Definition.new(%{
        mission_id: mission_id,
        limit_definition_id: "counter-limits-lifecycle",
        point_id: "HK.counter",
        version: 2,
        limit_set_name: "ops",
        thresholds: %{"yellow_high" => 20}
      })

    assert {:ok, ^first_definition} = Cadence.persist_limit_definition(first_definition)

    assert {:ok, ^replacement_definition} =
             Cadence.persist_limit_definition(replacement_definition)

    [event | _older_events] =
      DefinitionLifecycle.list_definition_lifecycle_events(
        organization_id,
        mission_id,
        point_id: "HK.counter",
        limit_definition_id: "counter-limits-lifecycle"
      )

    link = %DataLink{
      label: "Limit definition lifecycle event",
      target: :limit_definition_lifecycle_event,
      target_id: event.limit_definition_lifecycle_event_id,
      context: %{source_request_id: "limits-request-1", logical_source: :limits},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :limit_definition_lifecycle_event

    assert row_value(inspector.rows, "Limit definition lifecycle event") ==
             event.limit_definition_lifecycle_event_id

    assert row_value(inspector.rows, "Event type") == "activated"
    assert row_value(inspector.rows, "Limit definition") == "counter-limits-lifecycle"
    assert row_value(inspector.rows, "Limit definition version") == "2"
    assert row_value(inspector.rows, "Previous limit definition version") == "1"
    assert row_value(inspector.rows, "Point") == "HK.counter"
    assert row_value(inspector.rows, "Limit set") == "ops"

    assert related_link(inspector.related_links, :telemetry_point, "HK.counter")
    assert related_link(inspector.related_links, :limit_definition, "counter-limits-lifecycle")

    assert related_link(
             inspector.related_links,
             :operational_event,
             "operational_event:limit_definition_lifecycle_event:#{event.limit_definition_lifecycle_event_id}"
           )

    interval_link = %DataLink{
      label: "Limit definition interval",
      target: :limit_definition_interval,
      target_id: "effective_interval:limit_definition:#{event.definition_activation_key}",
      context: %{source_request_id: "limits-request-1", logical_source: :limits},
      source: :frame
    }

    assert {:ok, interval_inspector} =
             DataLinkResolver.resolve(interval_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert interval_inspector.status == :resolved
    assert interval_inspector.target == :limit_definition_interval

    assert row_value(interval_inspector.rows, "Limit definition interval") ==
             "effective_interval:limit_definition:#{event.definition_activation_key}"

    assert row_value(interval_inspector.rows, "Lifecycle event") ==
             event.limit_definition_lifecycle_event_id

    assert row_value(interval_inspector.rows, "Limit definition") ==
             "counter-limits-lifecycle"

    assert related_link(
             interval_inspector.related_links,
             :limit_definition_lifecycle_event,
             event.limit_definition_lifecycle_event_id
           )
  end

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

    assert {:ok, _binding_set} = Cadence.persist_binding_set(organization_id, binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
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
             Cadence.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_contact} =
             Cadence.cancel_scheduled_contact(
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
    assert {:ok, _operational_event} = Cadence.fetch_operational_event(operational_event_id)

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

  test "resolves source binding event links from persisted data bindings" do
    organization_id = "org-resolver-source-binding-event"
    mission_id = "mission-resolver-source-binding-event"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, _data_source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "mission-questdb-lifecycle",
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
      binding_id: "flight-telemetry-lifecycle",
      organization_id: organization_id,
      mission_id: mission_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-lifecycle",
      dataset: "flight",
      priority: 0,
      metadata: %{reason: :primary}
    }

    assert {:ok, _persisted_binding} =
             DataSources.persist_data_binding(binding,
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-21 20:00:00Z],
               payload: %{change_request_id: "CR-99"}
             )

    [event] = DataSources.list_data_binding_events("flight-telemetry-lifecycle")

    link = %DataLink{
      label: "Source binding event",
      target: :source_binding_event,
      target_id: event.data_binding_event_id,
      context: %{source_request_id: "telemetry-request-1", logical_source: :telemetry},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :source_binding_event
    assert row_value(inspector.rows, "Source binding event") == event.data_binding_event_id
    assert row_value(inspector.rows, "Binding") == "flight-telemetry-lifecycle"
    assert row_value(inspector.rows, "Event type") == "registered"
    assert row_value(inspector.rows, "Current logical source") == "telemetry"
    assert row_value(inspector.rows, "Current realm") == "flight"
    assert row_value(inspector.rows, "Current data source") == "mission-questdb-lifecycle"
    assert row_value(inspector.rows, "Current dataset") == "flight"
    assert row_value(inspector.rows, "Actor") == "operator-1"
    assert row_value(inspector.context_rows, "Logical source") == "telemetry"

    assert related_link(
             inspector.related_links,
             :operational_event,
             "operational_event:dashboard_data_binding_event:#{event.data_binding_event_id}"
           )

    interval_link = %DataLink{
      label: "Source binding interval",
      target: :source_binding_interval,
      target_id: "effective_interval:source_binding:#{event.data_binding_event_id}",
      context: %{source_request_id: "telemetry-request-1", logical_source: :telemetry},
      source: :frame
    }

    assert {:ok, interval_inspector} =
             DataLinkResolver.resolve(interval_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert interval_inspector.status == :resolved
    assert interval_inspector.target == :source_binding_interval

    assert row_value(interval_inspector.rows, "Source binding interval") ==
             interval_link.target_id

    assert row_value(interval_inspector.rows, "Binding") == "flight-telemetry-lifecycle"
    assert row_value(interval_inspector.rows, "Data binding event") == event.data_binding_event_id
    assert row_value(interval_inspector.rows, "Data source") == "mission-questdb-lifecycle"

    assert related_link(
             interval_inspector.related_links,
             :source_binding_event,
             event.data_binding_event_id
           )
  end

  test "resolves source watermark event links from persisted transition events" do
    organization_id = "org-resolver-source-watermark"
    mission_id = "mission-resolver-source-watermark"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, event, _status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: organization_id,
                 mission_id: mission_id,
                 logical_source: :telemetry,
                 data_source_id: "flight-questdb",
                 source_binding_id: "flight-telemetry",
                 realm: :flight,
                 dataset: "flight",
                 replay_run_id: "replay-run-watermark",
                 complete_through: ~U[2026-06-21 12:05:00Z],
                 previous_complete_through: ~U[2026-06-21 12:00:00Z],
                 latest_receipt_time: ~U[2026-06-21 12:05:30Z],
                 previous_latest_receipt_time: ~U[2026-06-21 12:00:30Z],
                 retention_starts_at: ~U[2026-06-21 11:00:00Z],
                 sample_count: 42,
                 confidence: :authoritative,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-21 12:06:00Z],
                 payload: %{write_id: "write-1"}
               },
               invalidate_runtime_cache?: false
             )

    link = %DataLink{
      label: "Source watermark event",
      target: :source_watermark_event,
      target_id: event.source_watermark_event_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :source_watermark_event
    assert row_value(inspector.rows, "Source watermark event") == event.source_watermark_event_id
    assert row_value(inspector.rows, "Source watermark key") == event.source_watermark_key
    assert row_value(inspector.rows, "Logical source") == "telemetry"
    assert row_value(inspector.rows, "Data source") == "flight-questdb"
    assert row_value(inspector.rows, "Source binding") == "flight-telemetry"
    assert row_value(inspector.rows, "Replay run") == "replay-run-watermark"
    assert row_value(inspector.rows, "Event type") == "observed"
    assert row_value(inspector.rows, "Complete through") == "2026-06-21T12:05:00.000000Z"
    assert row_value(inspector.rows, "Latest receipt time") == "2026-06-21T12:05:30.000000Z"
    assert row_value(inspector.rows, "Retention starts at") == "2026-06-21T11:00:00.000000Z"
    assert row_value(inspector.rows, "Sample count") == "42"
    assert row_value(inspector.rows, "Confidence") == "authoritative"
    assert row_value(inspector.rows, "Reason") == "telemetry_storage_write"
    assert row_value(inspector.context_rows, "Logical source") == "events"
  end

  test "resolves telemetry revision decision event links" do
    organization_id = "org-resolver-revision-decision"
    mission_id = "mission-resolver-revision-decision"
    persist_mission_scope(organization_id, mission_id)

    Repo.insert!(%OpsDashboardRow{
      dashboard_id: "dashboard-resolver-revision",
      organization_id: organization_id,
      mission_id: mission_id,
      name: "Revision decision dashboard",
      document: %{
        "dashboard_id" => "dashboard-resolver-revision",
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "name" => "Revision decision dashboard",
        "metadata" => %{"version" => 4}
      },
      latest_version: 4,
      draft_version: 4,
      lifecycle_state: "active"
    })

    comparison_review_request =
      LifecycleEvent.new(%{
        dashboard_lifecycle_event_id: "correction-workflow-1",
        organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: "dashboard-resolver-revision",
        event_type: :comparison_review_requested,
        dashboard_version: 4,
        actor_id: "ops-1",
        occurred_at: ~U[2026-06-22 12:09:00Z],
        payload: %{
          "schema" => "dashboard_comparison_review_request.v1",
          "request_kind" => "comparison_open_findings_review",
          "open_count" => 4,
          "open_placement_ids" => ["placement-1", "placement-2", "placement-3", "placement-4"]
        }
      })

    assert {:ok, _row} =
             comparison_review_request
             |> DashboardLifecycleEventRow.changeset()
             |> Repo.insert()

    decision_event =
      ObservationIdentityDecisionEvent.new(%{
        decision_event_id: "resolver-decision-event-1",
        observation_identity_id: "resolver-identity-1",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :flight,
        data_source_id: "flight-questdb",
        binding_id: "flight-telemetry",
        observable_id: "HK.counter",
        point_id: "HK.counter",
        spacecraft_id: "sc-resolver-revision",
        decision: :mark_canonical,
        decision_reason: "operator_selected_corrected_value",
        actor_id: "ops-1",
        actor_kind: "operator",
        evidence_ref: %{
          "kind" => "ticket",
          "id" => "OPS-123",
          "source_panel" => "data_link_inspector",
          "source_target" => "comparison_finding",
          "source_target_id" => "placement-1",
          "source_link_label" => "Comparison finding",
          "comparison_finding" => %{
            "placement_id" => "placement-1",
            "state" => "increased",
            "delta" => "+2",
            "primary_sample_id" => "sample-primary-1",
            "compare_sample_id" => "sample-compare-1",
            "primary_data_view" => "all_revisions",
            "compare_data_view" => "canonical",
            "primary_data_management" => "recomputed_analysis",
            "compare_data_management" => "degraded",
            "widget_id" => "widget-1",
            "widget_title" => "Counter"
          },
          "correction_workflow" => %{
            "kind" => "telemetry_correction_authority_workflow",
            "id" => "correction-workflow-1",
            "authority" => "operator",
            "requested_by" => "dashboard_comparison_review"
          },
          "bulk_workflow_item" => %{
            "kind" => "telemetry_correction_authority_workflow_item",
            "workflow_id" => "correction-workflow-1",
            "item_index" => 2,
            "item_count" => 4,
            "observation_identity_id" => "resolver-identity-1",
            "selection_kind" => "open_comparison_findings"
          }
        },
        previous_state: %{
          "validity_state" => "conflict",
          "canonical_sample_id" => "sample-before",
          "canonical_revision" => 1
        },
        new_state: %{
          "validity_state" => "canonical",
          "canonical_sample_id" => "sample-after",
          "canonical_revision" => 2
        },
        occurred_at: ~U[2026-06-22 12:10:00Z]
      })

    assert {:ok, _row} =
             decision_event
             |> TelemetryObservationIdentityDecisionEventRow.changeset()
             |> Repo.insert()

    link = %DataLink{
      label: "Telemetry revision decision event",
      target: :telemetry_revision_decision_event,
      target_id: decision_event.decision_event_id,
      context: %{
        source_request_id: "events-request-1",
        logical_source: :events,
        observable_id: "HK.counter",
        data: %{
          realm: :flight,
          data_source_id: "flight-questdb",
          source_binding_id: "flight-telemetry"
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
    assert inspector.target == :telemetry_revision_decision_event
    assert row_value(inspector.rows, "Revision decision event") == "resolver-decision-event-1"
    assert row_value(inspector.rows, "Observation identity") == "resolver-identity-1"
    assert row_value(inspector.rows, "Decision") == "mark_canonical"
    assert row_value(inspector.rows, "Decision reason") == "operator_selected_corrected_value"
    assert row_value(inspector.rows, "Data source") == "flight-questdb"
    assert row_value(inspector.rows, "Source binding") == "flight-telemetry"
    assert row_value(inspector.rows, "Observable") == "HK.counter"
    assert row_value(inspector.rows, "Point") == "HK.counter"
    assert row_value(inspector.rows, "Source panel") == "data_link_inspector"
    assert row_value(inspector.rows, "Source target") == "comparison_finding"
    assert row_value(inspector.rows, "Source target id") == "placement-1"
    assert row_value(inspector.rows, "Source link label") == "Comparison finding"
    assert row_value(inspector.rows, "Correction workflow") == "correction-workflow-1"
    assert row_value(inspector.rows, "Correction authority") == "operator"
    assert row_value(inspector.rows, "Correction requested by") == "dashboard_comparison_review"
    assert row_value(inspector.rows, "Bulk workflow") == "correction-workflow-1"
    assert row_value(inspector.rows, "Bulk workflow item") == "2"
    assert row_value(inspector.rows, "Bulk workflow item count") == "4"

    assert row_value(inspector.rows, "Bulk workflow observation identity") ==
             "resolver-identity-1"

    assert row_value(inspector.rows, "Bulk workflow selection") == "open_comparison_findings"
    assert row_value(inspector.rows, "Comparison finding") == "placement-1"
    assert row_value(inspector.rows, "Comparison state") == "increased"
    assert row_value(inspector.rows, "Comparison delta") == "+2"
    assert row_value(inspector.rows, "Comparison primary sample") == "sample-primary-1"
    assert row_value(inspector.rows, "Comparison compare sample") == "sample-compare-1"
    assert row_value(inspector.rows, "Comparison primary data view") == "all_revisions"
    assert row_value(inspector.rows, "Comparison compare data view") == "canonical"

    assert row_value(inspector.rows, "Comparison primary data management") ==
             "recomputed_analysis"

    assert row_value(inspector.rows, "Comparison compare data management") == "degraded"
    assert row_value(inspector.rows, "Comparison widget") == "widget-1"
    assert row_value(inspector.rows, "Comparison widget title") == "Counter"
    assert row_value(inspector.rows, "Previous validity state") == "conflict"
    assert row_value(inspector.rows, "New validity state") == "canonical"
    assert row_value(inspector.rows, "Previous canonical sample") == "sample-before"
    assert row_value(inspector.rows, "New canonical sample") == "sample-after"
    assert row_value(inspector.context_rows, "Source request") == "events-request-1"
    assert row_value(inspector.context_rows, "Logical source") == "events"
    assert related_link(inspector.related_links, :telemetry_point, "HK.counter")
    assert related_link(inspector.related_links, :telemetry_sample, "sample-before")
    assert related_link(inspector.related_links, :telemetry_sample, "sample-after")

    workflow_link =
      related_link(inspector.related_links, :dashboard_lifecycle_event, "correction-workflow-1")

    assert workflow_link
    assert workflow_link.relationship_kind == :comparison_review_origin

    assert {:ok, workflow_inspector} =
             DataLinkResolver.resolve(workflow_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert workflow_inspector.status == :resolved
    assert workflow_inspector.target == :dashboard_lifecycle_event

    assert row_value(workflow_inspector.rows, "Dashboard lifecycle event") ==
             "correction-workflow-1"

    assert row_value(workflow_inspector.rows, "Event type") == "comparison_review_requested"
    assert row_value(workflow_inspector.rows, "Dashboard") == "dashboard-resolver-revision"
    assert row_value(workflow_inspector.rows, "Dashboard version") == "4"

    assert {:error, missing_inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: "mission-other"
             )

    assert missing_inspector.status == :missing
  end

  test "resolves telemetry backfill lifecycle event links" do
    organization_id = "org-resolver-backfill-lifecycle"
    mission_id = "mission-resolver-backfill-lifecycle"
    persist_mission_scope(organization_id, mission_id)

    Repo.insert!(%OpsDashboardRow{
      dashboard_id: "dashboard-resolver-1",
      organization_id: organization_id,
      mission_id: mission_id,
      name: "Resolver dashboard",
      document: %{
        "dashboard_id" => "dashboard-resolver-1",
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "name" => "Resolver dashboard",
        "metadata" => %{"version" => 7}
      },
      latest_version: 7,
      draft_version: 7,
      lifecycle_state: "active"
    })

    comparison_review_request =
      LifecycleEvent.new(%{
        dashboard_lifecycle_event_id: "review-request-resolver",
        organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: "dashboard-resolver-1",
        event_type: :comparison_review_requested,
        dashboard_version: 7,
        actor_id: "ops-1",
        occurred_at: ~U[2026-06-22 12:19:00Z],
        payload: %{
          "schema" => "dashboard_comparison_review_request.v1",
          "request_kind" => "comparison_open_findings_review",
          "open_count" => 2,
          "open_placement_ids" => ["placement-1", "placement-2"]
        }
      })

    assert {:ok, _row} =
             comparison_review_request
             |> DashboardLifecycleEventRow.changeset()
             |> Repo.insert()

    assert {:ok, event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-backfill-event-1",
                 backfill_run_id: "resolver-backfill-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :flight,
                 replay_run_id: "replay-run-backfill",
                 data_source_id: "flight-questdb",
                 binding_id: "flight-telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 spacecraft_id: "sc-resolver-backfill",
                 event_type: :backfill_completed,
                 source_from: ~U[2026-06-22 11:00:00Z],
                 source_to: ~U[2026-06-22 12:00:00Z],
                 receipt_from: ~U[2026-06-22 12:10:00Z],
                 receipt_to: ~U[2026-06-22 12:20:00Z],
                 sample_count: 42,
                 authority: :authoritative,
                 reason: :operator_backfill,
                 actor_id: "ops-1",
                 actor_kind: "operator",
                 occurred_at: ~U[2026-06-22 12:21:00Z],
                 payload: %{
                   "ticket" => "OPS-123",
                   "workflow" => "backfill",
                   "stage" => "completed",
                   "run_id" => "resolver-backfill-run-1",
                   "dashboard_context" => %{
                     "dashboard_id" => "dashboard-resolver-1",
                     "dashboard_version" => "7",
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-run-backfill",
                     "dashboard_data_view" => "all_revisions",
                     "dashboard_limit_mode" => "observed"
                   },
                   "comparison_review_origin" => %{
                     "request_event_id" => comparison_review_request.dashboard_lifecycle_event_id,
                     "request_kind" => "comparison_open_findings_review",
                     "open_count" => "2",
                     "open_placement_ids" => "placement-1,placement-2",
                     "scope_kind" => "transport",
                     "scope_ids" => "transport-alpha,transport-beta",
                     "contact_ids" => "contact-alpha,contact-beta",
                     "resource_ids" => "transport-alpha",
                     "transport_ids" => "transport-alpha",
                     "source_endpoint_ids" => "endpoint-alpha",
                     "ground_station_ids" => "dss-14",
                     "scope_link_ids" => "link-alpha"
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission_id,
               "resolver-backfill-run-1",
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => "resolver-backfill-run-1"}
               }
             )

    link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: event.backfill_lifecycle_event_id,
      context: %{
        source_request_id: "events-request-1",
        logical_source: :events,
        observable_id: "HK.counter",
        data: %{
          realm: :flight,
          data_source_id: "flight-questdb",
          source_binding_id: "flight-telemetry"
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
    assert inspector.target == :telemetry_backfill_lifecycle_event
    assert row_value(inspector.rows, "Backfill lifecycle event") == "resolver-backfill-event-1"
    assert row_value(inspector.rows, "Backfill run") == "resolver-backfill-run-1"
    assert row_value(inspector.rows, "Event type") == "backfill_completed"
    assert row_value(inspector.rows, "Workflow") == "backfill"
    assert row_value(inspector.rows, "Workflow stage") == "completed"
    assert row_value(inspector.rows, "Workflow run") == "resolver-backfill-run-1"
    assert row_value(inspector.rows, "Dashboard context") == "dashboard-resolver-1"
    assert row_value(inspector.rows, "Dashboard context version") == "7"
    assert row_value(inspector.rows, "Dashboard context time mode") == "replay_run"
    assert row_value(inspector.rows, "Dashboard context replay run") == "replay-run-backfill"
    assert row_value(inspector.rows, "Dashboard context data view") == "all_revisions"
    assert row_value(inspector.rows, "Dashboard context limit mode") == "observed"
    assert row_value(inspector.rows, "Comparison review request") == "review-request-resolver"

    assert row_value(inspector.rows, "Comparison review kind") ==
             "comparison_open_findings_review"

    assert row_value(inspector.rows, "Comparison review open count") == "2"
    assert row_value(inspector.rows, "Comparison review placements") == "placement-1,placement-2"
    assert row_value(inspector.rows, "Comparison review scope kind") == "transport"

    assert row_value(inspector.rows, "Comparison review scope ids") ==
             "transport-alpha,transport-beta"

    assert row_value(inspector.rows, "Comparison review contact ids") ==
             "contact-alpha,contact-beta"

    assert row_value(inspector.rows, "Comparison review resource ids") == "transport-alpha"
    assert row_value(inspector.rows, "Comparison review transport ids") == "transport-alpha"
    assert row_value(inspector.rows, "Comparison review source endpoint ids") == "endpoint-alpha"
    assert row_value(inspector.rows, "Comparison review ground station ids") == "dss-14"
    assert row_value(inspector.rows, "Comparison review scope link ids") == "link-alpha"
    assert row_value(inspector.rows, "Replay run") == "replay-run-backfill"
    assert row_value(inspector.rows, "Data source") == "flight-questdb"
    assert row_value(inspector.rows, "Source binding") == "flight-telemetry"
    assert row_value(inspector.rows, "Observable") == "HK.counter"
    assert row_value(inspector.rows, "Point") == "HK.counter"
    assert row_value(inspector.rows, "Sample count") == "42"
    assert row_value(inspector.rows, "Authority") == "authoritative"
    assert row_value(inspector.rows, "Reason") == "operator_backfill"
    assert row_value(inspector.rows, "Workflow job") == job.job_id
    assert row_value(inspector.rows, "Workflow job status") == "queued"
    assert row_value(inspector.rows, "Workflow job attempts") == "0"
    assert row_value(inspector.context_rows, "Source request") == "events-request-1"
    assert row_value(inspector.context_rows, "Logical source") == "events"
    assert related_link(inspector.related_links, :telemetry_point, "HK.counter")

    comparison_review_link =
      related_link(
        inspector.related_links,
        :dashboard_lifecycle_event,
        comparison_review_request.dashboard_lifecycle_event_id
      )

    assert comparison_review_link
    assert comparison_review_link.relationship_kind == :comparison_review_origin

    assert {:ok, comparison_review_inspector} =
             DataLinkResolver.resolve(comparison_review_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert comparison_review_inspector.status == :resolved
    assert comparison_review_inspector.target == :dashboard_lifecycle_event

    assert row_value(comparison_review_inspector.rows, "Dashboard lifecycle event") ==
             comparison_review_request.dashboard_lifecycle_event_id

    assert row_value(comparison_review_inspector.rows, "Dashboard") == "dashboard-resolver-1"

    assert row_value(comparison_review_inspector.rows, "Event type") ==
             "comparison_review_requested"

    assert row_value(comparison_review_inspector.rows, "Dashboard version") == "7"

    assert row_value(comparison_review_inspector.rows, "Payload schema") ==
             "dashboard_comparison_review_request.v1"

    assert row_value(comparison_review_inspector.rows, "Comparison review kind") ==
             "comparison_open_findings_review"

    assert row_value(comparison_review_inspector.rows, "Comparison review open count") == "2"

    assert row_value(comparison_review_inspector.rows, "Comparison review placements") ==
             "placement-1,placement-2"

    assert {:error, missing_inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: "mission-other"
             )

    assert missing_inspector.status == :missing
  end

  test "resolves telemetry backfill lifecycle missing replacement inspection rows" do
    organization_id = "org-resolver-backfill-missing-replacement"
    mission_id = "mission-resolver-backfill-missing-replacement"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-missing-replacement-inspection-1",
                 backfill_run_id: "resolver-corrected-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :backfill,
                 replay_run_id: "resolver-missing-replacement-replay-1",
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 event_type: :backfill_missing_replacement_inspected,
                 authority: :advisory,
                 reason: "dashboard_historical_workflow_missing_replacement_inspected",
                 actor_id: "ops-1",
                 actor_kind: "operator",
                 occurred_at: ~U[2026-06-22 12:24:00Z],
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "missing_replacement_inspected",
                   "run_id" => "resolver-corrected-run-1",
                   "request_group_id" => "resolver-missing-group-1",
                   "missing_replacement_action" => "inspect_missing_replacement_job",
                   "missing_replacement_source_event_id" => "resolver-source-failed-event-1",
                   "missing_replacement_source_event_type" => "backfill_failed",
                   "missing_replacement_run_id" => "resolver-corrected-run-1",
                   "missing_replacement_expected_job_type" => "telemetry_historical_data_workflow"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: event.backfill_lifecycle_event_id,
      context: %{logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :telemetry_backfill_lifecycle_event

    assert row_value(inspector.rows, "Backfill lifecycle event") ==
             event.backfill_lifecycle_event_id

    assert row_value(inspector.rows, "Backfill run") == "resolver-corrected-run-1"
    assert row_value(inspector.rows, "Event type") == "backfill_missing_replacement_inspected"
    assert row_value(inspector.rows, "Workflow") == "backfill"
    assert row_value(inspector.rows, "Workflow stage") == "missing_replacement_inspected"
    assert row_value(inspector.rows, "Workflow run") == "resolver-corrected-run-1"
    assert row_value(inspector.rows, "Request group") == "resolver-missing-group-1"

    assert row_value(inspector.rows, "Missing replacement action") ==
             "inspect_missing_replacement_job"

    assert row_value(inspector.rows, "Missing replacement source event") ==
             "resolver-source-failed-event-1"

    assert row_value(inspector.rows, "Missing replacement source event type") ==
             "backfill_failed"

    assert row_value(inspector.rows, "Missing replacement run") == "resolver-corrected-run-1"

    assert row_value(inspector.rows, "Missing replacement expected job type") ==
             "telemetry_historical_data_workflow"

    assert row_value(inspector.rows, "Workflow job status") == "missing"
    assert related_link(inspector.related_links, :telemetry_point, "HK.counter")
  end

  test "resolves grouped telemetry backfill lifecycle job progress" do
    organization_id = "org-resolver-backfill-group-jobs"
    mission_id = "mission-resolver-backfill-group-jobs"
    persist_mission_scope(organization_id, mission_id)

    base_event = %{
      organization_id: organization_id,
      mission_id: mission_id,
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      source_from: ~U[2026-06-22 10:00:00Z],
      source_to: ~U[2026-06-22 11:00:00Z],
      authority: :advisory,
      reason: :operator_requested_bulk_backfill_from_dashboard,
      actor_id: "ops-1",
      actor_kind: "operator"
    }

    requested_items = [
      {"resolver-backfill-group-event-001", "resolver-backfill-group-run-001", "HK.counter", 1},
      {"resolver-backfill-group-event-002", "resolver-backfill-group-run-002", "HK.voltage", 2},
      {"resolver-backfill-group-event-003", "resolver-backfill-group-run-003", "HK.current", 3}
    ]

    events =
      Enum.map(requested_items, fn {event_id, run_id, point_id, item_index} ->
        assert {:ok, event} =
                 Storage.record_backfill_lifecycle_event(
                   Map.merge(base_event, %{
                     backfill_lifecycle_event_id: event_id,
                     backfill_run_id: run_id,
                     observable_id: point_id,
                     point_id: point_id,
                     event_type: :backfill_requested,
                     payload: %{
                       "workflow" => "backfill",
                       "stage" => "requested",
                       "run_id" => run_id,
                       "request_mode" => "bulk_points",
                       "request_group_id" => "resolver-backfill-group",
                       "request_item_index" => item_index,
                       "request_item_count" => 3,
                       "request_item_run_id" => run_id,
                       "comparison_review_origin" => %{
                         "request_event_id" => "review-request-group-resolver",
                         "request_kind" => "comparison_open_findings_review",
                         "open_count" => "3",
                         "open_placement_ids" => "placement-1,placement-2,placement-3"
                       }
                     }
                   }),
                   dashboard_runtime_invalidation?: false
                 )

        event
      end)

    jobs =
      Enum.map(requested_items, fn {_event_id, run_id, _point_id, _item_index} ->
        assert {:ok, job} =
                 Cadence.Jobs.enqueue(
                   :telemetry_historical_data_workflow,
                   mission_id,
                   run_id,
                   %{
                     "workflow" => "backfill",
                     "attrs" => %{"backfill_run_id" => run_id}
                   }
                 )

        job
      end)

    [_counter_job, voltage_job, current_job] = jobs

    assert {:ok, failed_voltage_job} =
             Cadence.Jobs.fail_worker_start(voltage_job.job_id, :source_window_failed)

    assert failed_voltage_job.status == :failed

    assert {:ok, failed_current_job} =
             Cadence.Jobs.fail_worker_start(current_job.job_id, :missing_point_id)

    assert failed_current_job.status == :failed

    assert {:ok, failed_voltage_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-backfill-group-failed-002",
                 backfill_run_id: "resolver-backfill-group-run-002",
                 observable_id: "HK.voltage",
                 point_id: "HK.voltage",
                 event_type: :backfill_failed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "failed",
                   "run_id" => "resolver-backfill-group-run-002",
                   "request_group_id" => "resolver-backfill-group",
                   "request_item_index" => 2,
                   "request_item_count" => 3,
                   "request_item_run_id" => "resolver-backfill-group-run-002"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, failed_current_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-backfill-group-failed-003",
                 backfill_run_id: "resolver-backfill-group-run-003",
                 observable_id: "HK.current",
                 point_id: "HK.current",
                 event_type: :backfill_failed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "failed",
                   "run_id" => "resolver-backfill-group-run-003",
                   "request_group_id" => "resolver-backfill-group",
                   "request_item_index" => 3,
                   "request_item_count" => 3,
                   "request_item_run_id" => "resolver-backfill-group-run-003"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _retry_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-backfill-group-retry-002",
                 backfill_run_id: "resolver-backfill-group-run-002",
                 observable_id: "HK.voltage",
                 point_id: "HK.voltage",
                 event_type: :backfill_retried,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "retried",
                   "run_id" => "resolver-backfill-group-run-002",
                   "request_group_id" => "resolver-backfill-group",
                   "request_item_index" => 2,
                   "request_item_count" => 3,
                   "request_item_run_id" => "resolver-backfill-group-run-002",
                   "retry_source_event_id" => failed_voltage_event.backfill_lifecycle_event_id,
                   "retry_job_id" => voltage_job.job_id,
                   "retry_job_status" => "queued"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _correction_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-backfill-group-correction-003",
                 backfill_run_id: "resolver-backfill-group-run-003-corrected",
                 observable_id: "HK.current",
                 point_id: "HK.current",
                 event_type: :backfill_requested,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "requested",
                   "run_id" => "resolver-backfill-group-run-003-corrected",
                   "request_group_id" => "resolver-backfill-group",
                   "request_item_index" => 3,
                   "request_item_count" => 3,
                   "request_item_run_id" => "resolver-backfill-group-run-003-corrected",
                   "corrects_event_id" => failed_current_event.backfill_lifecycle_event_id,
                   "corrects_run_id" => "resolver-backfill-group-run-003",
                   "corrects_job_id" => current_job.job_id
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    [selected_event | _events] = events

    link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: selected_event.backfill_lifecycle_event_id,
      context: %{logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert row_value(inspector.rows, "Request group") == "resolver-backfill-group"

    assert row_value(inspector.rows, "Comparison review request") ==
             "review-request-group-resolver"

    assert row_value(inspector.rows, "Comparison review open count") == "3"

    assert row_value(inspector.rows, "Comparison review placements") ==
             "placement-1,placement-2,placement-3"

    assert row_value(inspector.rows, "Request group progress") ==
             "0/3 completed, 0 failed, 2 resolved"

    assert row_value(inspector.rows, "Request group job progress") ==
             "queued 1, failed 1, missing 1"

    group_job_items = row_value(inspector.rows, "Request group job items")

    assert group_job_items =~
             "1:HK.counter resolver-backfill-group-run-001 queued #{Enum.at(jobs, 0).job_id}"

    assert group_job_items =~
             "2:HK.voltage resolver-backfill-group-run-002 failed #{Enum.at(jobs, 1).job_id} event="

    assert group_job_items =~
             "2:HK.voltage resolver-backfill-group-run-002 failed #{Enum.at(jobs, 1).job_id}"

    assert group_job_items =~ "completed="

    assert group_job_items =~ "3:HK.current resolver-backfill-group-run-003-corrected missing"

    assert row_value(inspector.rows, "Request group retried items") ==
             "HK.voltage resolver-backfill-group-run-002 retried queued #{voltage_job.job_id}"

    assert row_value(inspector.rows, "Request group corrected items") ==
             "HK.current resolver-backfill-group-run-003 corrected resolver-backfill-group-run-003-corrected requested #{current_job.job_id}"

    assert row_value(inspector.rows, "Request group correction tasks") ==
             "HK.current resolver-backfill-group-run-003 replacement resolver-backfill-group-run-003-corrected stage requested next approve"
  end

  test "resolves late-data policy lifecycle source relationships" do
    organization_id = "org-resolver-late-data-policy"
    mission_id = "mission-resolver-late-data-policy"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, _source_event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-late-source-event-1",
                 backfill_run_id: "resolver-late-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :flight,
                 data_source_id: "flight-questdb",
                 binding_id: "flight-telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 event_type: :backfill_completed,
                 source_from: ~U[2026-06-22 11:00:00Z],
                 source_to: ~U[2026-06-22 12:00:00Z],
                 authority: :authoritative,
                 reason: :operator_backfill,
                 payload: %{"workflow" => "backfill", "stage" => "completed"}
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, policy_event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-late-policy-event-1",
                 backfill_run_id: "resolver-late-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :flight,
                 data_source_id: "flight-questdb",
                 binding_id: "flight-telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 event_type: :late_data_accepted,
                 source_from: ~U[2026-06-22 11:00:00Z],
                 source_to: ~U[2026-06-22 12:00:00Z],
                 authority: :authoritative,
                 reason: :dashboard_late_data_policy,
                 payload: %{
                   "kind" => "late_data_policy_decision",
                   "policy_decision" => "accept",
                   "execution_mode" => "sample_execution",
                   "source_event_id" => "resolver-late-source-event-1",
                   "source_event_type" => "backfill_completed",
                   "selected_sample_count" => 2,
                   "write_validity_state" => "canonical",
                   "record_current_values" => true,
                   "refresh_latest_value" => true,
                   "projection_effect" => "canonical_history_and_current_projection",
                   "dashboard_context" => %{"dashboard_limit_mode" => "compare"}
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: policy_event.backfill_lifecycle_event_id,
      context: %{logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert row_value(inspector.rows, "Late data policy decision") == "accept"
    assert row_value(inspector.rows, "Late data execution mode") == "sample_execution"
    assert row_value(inspector.rows, "Late data source event") == "resolver-late-source-event-1"
    assert row_value(inspector.rows, "Late data source event type") == "backfill_completed"
    assert row_value(inspector.rows, "Late data selected samples") == "2"
    assert row_value(inspector.rows, "Late data write validity") == "canonical"
    assert row_value(inspector.rows, "Late data current projection") == "true"
    assert row_value(inspector.rows, "Late data latest refresh") == "true"
    assert row_value(inspector.rows, "Dashboard context limit mode") == "compare"

    assert row_value(inspector.rows, "Late data projection effect") ==
             "canonical_history_and_current_projection"

    assert related_link(
             inspector.related_links,
             :telemetry_backfill_lifecycle_event,
             "resolver-late-source-event-1"
           )
  end

  test "resolves telemetry backfill lifecycle recovery relationships" do
    organization_id = "org-resolver-backfill-recovery-links"
    mission_id = "mission-resolver-backfill-recovery-links"
    persist_mission_scope(organization_id, mission_id)

    base_event = %{
      organization_id: organization_id,
      mission_id: mission_id,
      realm: :flight,
      data_source_id: "flight-questdb",
      binding_id: "flight-telemetry",
      observable_id: "HK.counter",
      point_id: "HK.counter",
      spacecraft_id: "sc-resolver-backfill",
      source_from: ~U[2026-06-22 11:00:00Z],
      source_to: ~U[2026-06-22 12:00:00Z],
      authority: :authoritative,
      actor_id: "ops-1",
      actor_kind: "operator"
    }

    assert {:ok, source_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-source-event-1",
                 backfill_run_id: "resolver-recovery-run-1",
                 event_type: :backfill_failed,
                 reason: :historical_data_job_failed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "failed",
                   "run_id" => "resolver-recovery-run-1"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, retry_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-retry-event-1",
                 backfill_run_id: "resolver-recovery-run-1",
                 event_type: :backfill_retried,
                 reason: "dashboard_historical_workflow_retried",
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "retried",
                   "run_id" => "resolver-recovery-run-1",
                   "retry_source_event_id" => source_event.backfill_lifecycle_event_id,
                   "retry_source_event_type" => "backfill_failed"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, correction_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-correction-event-1",
                 backfill_run_id: "resolver-recovery-correction-run-1",
                 event_type: :backfill_requested,
                 reason: :dashboard_historical_workflow_correction_requested,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "requested",
                   "run_id" => "resolver-recovery-correction-run-1",
                   "corrects_event_id" => source_event.backfill_lifecycle_event_id,
                   "corrects_run_id" => source_event.backfill_run_id,
                   "correction_source" => "dashboard_data_link_inspector"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, correction_transition_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-correction-transition-1",
                 backfill_run_id: "resolver-recovery-correction-run-1",
                 event_type: :backfill_completed,
                 reason: :dashboard_historical_workflow_correction_completed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "completed",
                   "run_id" => "resolver-recovery-correction-run-1",
                   "corrects_event_id" => source_event.backfill_lifecycle_event_id,
                   "correction_transition_source_event_id" =>
                     correction_event.backfill_lifecycle_event_id
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, policy_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-policy-event-1",
                 backfill_run_id: "resolver-recovery-run-1",
                 event_type: :late_data_accepted,
                 reason: :dashboard_late_data_policy,
                 payload: %{
                   "kind" => "late_data_policy_decision",
                   "policy_decision" => "accept",
                   "source_event_id" => source_event.backfill_lifecycle_event_id
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    source_link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: source_event.backfill_lifecycle_event_id,
      context: %{logical_source: :events},
      source: :frame
    }

    assert {:ok, source_inspector} =
             DataLinkResolver.resolve(source_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert %DataLink{relationship_kind: :retry_event} =
             related_link(
               source_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               retry_event.backfill_lifecycle_event_id
             )

    assert %DataLink{relationship_kind: :correction_request} =
             related_link(
               source_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               correction_event.backfill_lifecycle_event_id
             )

    assert %DataLink{relationship_kind: :correction_transition} =
             related_link(
               source_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               correction_transition_event.backfill_lifecycle_event_id
             )

    assert %DataLink{relationship_kind: :late_data_policy_event} =
             related_link(
               source_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               policy_event.backfill_lifecycle_event_id
             )

    retry_link = %{source_link | target_id: retry_event.backfill_lifecycle_event_id}

    assert {:ok, retry_inspector} =
             DataLinkResolver.resolve(
               %{
                 retry_link
                 | context:
                     Map.put(retry_link.context, :navigation, %{
                       from: %{
                         link_id: source_link.link_id,
                         target: "telemetry_backfill_lifecycle_event",
                         target_id: source_event.backfill_lifecycle_event_id,
                         label: "Source event",
                         relationship_kind: "retry_event",
                         relationship_label: "Retry event HK.counter"
                       }
                     })
               },
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert retry_inspector.navigation == %{
             from: %{
               target: "telemetry_backfill_lifecycle_event",
               target_id: source_event.backfill_lifecycle_event_id,
               label: "Source event",
               relationship_kind: "retry_event",
               relationship_label: "Retry event HK.counter"
             }
           }

    assert %DataLink{relationship_kind: :source_event} =
             related_link(
               retry_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               source_event.backfill_lifecycle_event_id
             )

    correction_link = %{source_link | target_id: correction_event.backfill_lifecycle_event_id}

    assert {:ok, correction_inspector} =
             DataLinkResolver.resolve(correction_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert %DataLink{relationship_kind: :source_event} =
             related_link(
               correction_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               source_event.backfill_lifecycle_event_id
             )

    assert %DataLink{relationship_kind: :correction_transition} =
             related_link(
               correction_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               correction_transition_event.backfill_lifecycle_event_id
             )
  end

  test "resolves telemetry backfill lifecycle failure diagnostics" do
    organization_id = "org-resolver-backfill-failure"
    mission_id = "mission-resolver-backfill-failure"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-backfill-failed-event-1",
                 backfill_run_id: "resolver-backfill-failed-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :backfill,
                 replay_run_id: "replay-run-backfill-failure",
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 event_type: :backfill_failed,
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :advisory,
                 reason: :historical_data_job_failed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "failed",
                   "run_id" => "resolver-backfill-failed-run-1",
                   "source" => %{
                     "point_id" => nil,
                     "source_window" => %{
                       "from_observed_at" => "2026-06-22T10:00:00Z",
                       "to_observed_at" => "2026-06-22T11:00:00Z"
                     },
                     "source_identity" => %{
                       "realm" => "backfill",
                       "replay_run_id" => "replay-run-backfill-failure",
                       "data_source_id" => "managed_questdb_backfill",
                       "source_binding_id" => "backfill_telemetry"
                     },
                     "source_limit" => 10_000,
                     "failure" => %{
                       "code" => "missing_field:point_id",
                       "detail" => "{:missing_field, :point_id}",
                       "retryable" => false,
                       "retry_blockers" => ["missing point_id"],
                       "recovery_action" => "correct_workflow_request"
                     }
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission_id,
               "resolver-backfill-failed-run-1",
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => "resolver-backfill-failed-run-1"}
               }
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_window_failed)
    assert failed_job.status == :failed

    link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: event.backfill_lifecycle_event_id,
      context: %{logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert row_value(inspector.rows, "Workflow failure code") == "missing_field:point_id"
    assert row_value(inspector.rows, "Workflow failure detail") == "{:missing_field, :point_id}"
    assert row_value(inspector.rows, "Workflow retryable") == "false"
    assert row_value(inspector.rows, "Workflow retry blockers") == "missing point_id"
    assert row_value(inspector.rows, "Workflow recovery action") == "correct_workflow_request"
    assert row_value(inspector.rows, "Replay run") == "replay-run-backfill-failure"

    assert row_value(inspector.rows, "Workflow source replay run") ==
             "replay-run-backfill-failure"

    assert row_value(inspector.rows, "Workflow source data source") == "managed_questdb_backfill"
    assert row_value(inspector.rows, "Workflow source binding") == "backfill_telemetry"
    assert row_value(inspector.rows, "Workflow source from") == "2026-06-22T10:00:00Z"
    assert row_value(inspector.rows, "Workflow source to") == "2026-06-22T11:00:00Z"
    assert row_value(inspector.rows, "Workflow source limit") == "10000"
    assert row_value(inspector.rows, "Workflow job") == job.job_id
    assert row_value(inspector.rows, "Workflow job status") == "failed"
  end

  test "does not resolve mission events or contacts outside the requested organization and mission" do
    organization_id = "org-resolver-events-scope-a"
    mission_id = "mission-resolver-events-scope-a"
    persist_mission_scope(organization_id, mission_id)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "resolver-scope-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths("source-endpoint-alpha"),
        starts_at: ~U[2026-06-20 12:00:00Z],
        ends_at: ~U[2026-06-20 12:10:00Z]
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_contact} =
             Cadence.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "weather"
             )

    [mission_event] = Cadence.list_mission_events(organization_id, mission_id, order: :asc)
    persist_mission_scope("org-resolver-events-scope-b", "mission-resolver-events-scope-b")

    assert {:error, event_inspector} =
             DataLinkResolver.resolve(
               %DataLink{
                 label: "Mission event",
                 target: :mission_event,
                 target_id: mission_event.mission_event_id
               },
               organization_id: "org-resolver-events-scope-b",
               mission_id: "mission-resolver-events-scope-b"
             )

    assert event_inspector.status == :missing

    assert {:error, contact_inspector} =
             DataLinkResolver.resolve(
               %DataLink{
                 label: "Contact",
                 target: :contact,
                 target_id: scheduled_contact.scheduled_contact_id
               },
               organization_id: "org-resolver-events-scope-b",
               mission_id: "mission-resolver-events-scope-b"
             )

    assert contact_inspector.status == :missing
  end

  test "returns a missing inspector for stale dashboard link ids" do
    inspector = DataLinkResolver.missing("stale-link-1")

    assert %DataLinkInspector{} = inspector
    assert inspector.status == :missing
    assert inspector.title == "Data link"
    assert inspector.target == :data_link
    assert inspector.target_id == "stale-link-1"
    assert row_value(inspector.rows, "Link") == "stale-link-1"
    assert inspector.related_links == []
  end

  test "returns an unsupported inspector for invalid data-link targets" do
    link = %DataLink{label: "Command", target: :command, target_id: "cmd-1"}

    assert {:error, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: "org-resolver-unsupported",
               mission_id: "mission-resolver-unsupported"
             )

    assert inspector.status == :unsupported
    assert inspector.target == :command
    assert inspector.target_id == "cmd-1"
  end

  defp persist_sample_scope!(suffix, value) do
    organization_id = "org-#{suffix}"
    mission_id = "mission-#{suffix}"
    spacecraft_id = "sc-#{suffix}"
    persist_mission_scope(organization_id, mission_id)
    binding_set = persist_binding_set!(organization_id, mission_id)
    activate_binding_set!(organization_id, mission_id, binding_set)
    ingest!(mission_id, binding_set, spacecraft_id, value)

    sample = Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter", [])

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_id: spacecraft_id,
      sample_id: sample.sample_id,
      evidence_id: sample.evidence_id
    }
  end

  defp persist_comparison_samples!(suffix) do
    organization_id = "org-#{suffix}"
    mission_id = "mission-#{suffix}"
    spacecraft_id = "sc-#{suffix}"
    persist_mission_scope(organization_id, mission_id)
    binding_set = persist_binding_set!(organization_id, mission_id)
    activate_binding_set!(organization_id, mission_id, binding_set)

    ingest!(
      mission_id,
      binding_set,
      spacecraft_id,
      41,
      receipt_time: ~U[2026-06-20 12:00:00Z],
      sequence_count: 1
    )

    primary = Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter", [])

    ingest!(
      mission_id,
      binding_set,
      spacecraft_id,
      42,
      receipt_time: ~U[2026-06-20 12:01:00Z],
      sequence_count: 2
    )

    compare = Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter", [])

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      primary_sample_id: primary.sample_id,
      compare_sample_id: compare.sample_id
    }
  end

  defp attach_storage_provenance!(sample_id, storage) do
    sample_row = Repo.get!(TelemetrySampleRow, sample_id)

    sample_row
    |> Ecto.Changeset.change(provenance: %{"storage" => storage})
    |> Repo.update!()
  end

  defp persist_binding_set!(organization_id, mission_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "#{mission_id}-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted} = Cadence.persist_binding_set(organization_id, binding_set)
    persisted
  end

  defp activate_binding_set!(organization_id, mission_id, binding_set) do
    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               organization_id,
               mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               []
             )
  end

  defp ingest!(mission_id, binding_set, spacecraft_id, value, opts \\ []) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: Keyword.get(opts, :receipt_time, ~U[2026-06-20 12:00:00Z]),
        raw: build_space_packet(42, Keyword.get(opts, :sequence_count, 1), <<value::16>>)
      })

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               evidence,
               binding_set.binding_set_id,
               binding_set.version
             )
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
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

  defp transport_action_request(
         mission_id,
         action_request_id,
         capability_instance_id,
         action_kind,
         requested_at,
         opts
       ) do
    %TransportActionRequest{
      action_request_id: action_request_id,
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
      command_release_attempt_id:
        Keyword.get(opts, :command_release_attempt_id, "release-attempt-1"),
      command_request_id: Keyword.get(opts, :command_request_id, "command-request-1"),
      source_endpoint_ref: Keyword.get(opts, :source_endpoint_ref, "source-endpoint-alpha"),
      command_name: Keyword.get(opts, :command_name, "NOOP"),
      signal_phase: Keyword.get(opts, :signal_phase, :start),
      action_kind: action_kind,
      request_document: Keyword.fetch!(opts, :request_document),
      requested_at: requested_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
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

  defp persist_transport_execution_scope(organization_id, mission_id) do
    transport =
      Transport.new(%{
        mission_id: mission_id,
        transport_id: "uplink-heartbeat",
        display_name: "Uplink Heartbeat",
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      })

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "realized-contact-1",
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        clock_mode: :replay,
        lifecycle_state: :active,
        initial_time: ~U[2026-06-30 12:00:00Z],
        realized_at: ~U[2026-06-30 12:00:00Z],
        paths: [
          Path.new(%{
            path_id: "uplink-path-alpha",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha"
          })
        ]
      })

    assert {:ok, _transport} = Cadence.persist_transport(organization_id, transport)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(organization_id, realized_contact)
  end

  defp contact_paths(source_endpoint_ref) do
    [
      Path.new(%{
        path_id: "resolver-uplink-path",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      Path.new(%{
        path_id: "resolver-downlink-path",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
  end

  defp row_value(rows, label) do
    rows
    |> Enum.find(&(&1.label == label))
    |> Map.fetch!(:value)
  end

  defp related_link(links, target, target_id) do
    Enum.find(links, &(&1.target == target and &1.target_id == target_id))
  end

  defp action_for(actions, target) do
    Enum.find(actions, &(&1.target == target))
  end
end
