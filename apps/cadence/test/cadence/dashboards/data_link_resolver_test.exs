defmodule Cadence.Dashboards.DataLinkResolverTest do
  use Cadence.RuntimeCase, async: false

  import Cadence.Dashboards.DataLinkResolverFixtures

  alias Cadence.Comms.{GroundStation, RoutingRule, Transport}

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest
  }

  alias Cadence.Dashboards.{
    DashboardAction,
    DataLink,
    DataLinkInspector,
    DataLinkResolver
  }

  alias Cadence.Limits.{Definition, DefinitionLifecycle}

  alias Cadence.Persistence.Schemas.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow
  }

  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

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
end
