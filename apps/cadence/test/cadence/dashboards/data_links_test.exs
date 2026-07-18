defmodule Cadence.Dashboards.DataLinksTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DataContext,
    DataLink,
    DataLinks,
    EvidenceRef,
    PlannedSourceRequest,
    ScopeContext
  }

  test "parses only resolvable dashboard data-link targets" do
    assert DataLink.parse_resolvable_target("telemetry_sample") == :telemetry_sample
    assert DataLink.parse_resolvable_target("telemetry-sample") == :telemetry_sample
    assert DataLink.parse_resolvable_target(:limit_event) == :limit_event
    assert DataLink.parse_resolvable_target("source-watermark-event") == :source_watermark_event
    assert DataLink.parse_resolvable_target("operational_event") == :operational_event
    assert DataLink.parse_resolvable_target("transport") == :transport
    assert DataLink.parse_resolvable_target("source_endpoint") == :source_endpoint
    assert DataLink.parse_resolvable_target("ground-station") == :ground_station

    assert DataLink.parse_resolvable_target("dashboard-lifecycle-event") ==
             :dashboard_lifecycle_event

    refute DataLink.parse_resolvable_target("command")
    refute DataLink.parse_resolvable_target(:command)
    refute DataLink.parse_resolvable_target("data_source")
    refute DataLink.parse_resolvable_target("explore")
  end

  test "normalizes persisted or serialized link maps into typed links" do
    assert %DataLink{
             link_id: "limit-event:limit-1",
             label: "Limit event",
             target: :limit_event,
             target_id: "limit-1",
             route: nil,
             relationship_kind: :comparison_review_origin,
             context: %{"point_id" => "HK.counter"},
             presentation: :new_tab,
             source: :warning
           } =
             DataLink.normalize(%{
               "link_id" => "limit-event:limit-1",
               "label" => "Limit event",
               "target" => "limit-event",
               "target_id" => "limit-1",
               "relationship_kind" => "comparison-review-origin",
               "context" => %{"point_id" => "HK.counter"},
               "presentation" => "new_tab",
               "source" => "warning"
             })
  end

  test "normalizes only link-shaped values from lists" do
    link = %DataLink{link_id: "sample", target: :telemetry_sample, target_id: "sample-1"}

    assert [
             ^link,
             %DataLink{
               link_id: "point",
               target: :telemetry_point,
               target_id: "HK.counter",
               presentation: :explore,
               source: :frame
             }
           ] =
             DataLink.normalize_many([
               link,
               %{
                 link_id: "point",
                 target: "telemetry_point",
                 target_id: "HK.counter",
                 presentation: "explore",
                 source: "frame"
               },
               "not a link"
             ])
  end

  test "telemetry sample links include effective source identity in context" do
    request = source_request(:telemetry)

    [link] =
      DataLinks.telemetry_sample_links(request, [
        %{sample_id: "sample-1", point_id: "HK.counter"}
      ])

    assert link.context.data.realm == :rehearsal
    assert link.context.data.data_source_id == "rehearsal-tsdb"
    assert link.context.data.source_binding_id == "rehearsal-binding"
    assert link.context.data.dataset == "rehearsal"
    assert link.context.data.view == :all_revisions
    assert link.context.data.validity_state == :conflict
    assert link.context.data.replay_run_id == "replay-run-1"
    assert link.context.time.replay_run_id == "replay-run-1"
    assert link.context.scope.spacecraft_id == "sc-alpha"
  end

  test "operational resource links preserve source identity and row context" do
    request = source_request(:operational_observables)

    links =
      DataLinks.operational_resource_links(request, [
        %{
          observable_id: "comms.transport.connection_state",
          resource_id: "transport-alpha",
          scope_kind: :transport,
          transport_id: "transport-alpha",
          source_endpoint_id: "endpoint-alpha",
          ground_station_id: "dss-14",
          link_id: "link-alpha",
          adapter_key: :tcp_socket
        }
      ])

    assert [
             %DataLink{target: :transport, target_id: "transport-alpha"} = transport_link,
             %DataLink{target: :source_endpoint, target_id: "endpoint-alpha"},
             %DataLink{target: :ground_station, target_id: "dss-14"},
             %DataLink{target: :link, target_id: "link-alpha"}
           ] = links

    assert transport_link.context.logical_source == :operational_observables
    assert transport_link.context.observable_id == "comms.transport.connection_state"
    assert transport_link.context.data.realm == :rehearsal
    assert transport_link.context.data.data_source_id == "ops-tsdb"
    assert transport_link.context.data.source_binding_id == "ops-binding"

    assert transport_link.context.operational_resource == %{
             adapter_key: :tcp_socket,
             ground_station_id: "dss-14",
             link_id: "link-alpha",
             resource_id: "transport-alpha",
             scope_kind: :transport,
             source_endpoint_id: "endpoint-alpha",
             transport_id: "transport-alpha"
           }
  end

  test "limit links include effective source identity in context" do
    request = source_request(:limits)

    [_point_link, event_link | _rest] =
      DataLinks.limit_links(request, "HK.counter", [
        %{
          limit_event_id: "limit-event-1",
          limit_definition_id: "limit-definition-1",
          point_id: "HK.counter",
          sample_id: "sample-1"
        }
      ])

    assert event_link.context.data.realm == :rehearsal
    assert event_link.context.data.data_source_id == "limits-tsdb"
    assert event_link.context.data.source_binding_id == "limits-binding"
    assert event_link.context.data.replay_run_id == "replay-run-1"
    assert event_link.context.scope.spacecraft_id == "sc-alpha"
  end

  test "source watermark event links include effective events source identity in context" do
    request = source_request(:events)

    [link, operational_event_link] =
      DataLinks.source_watermark_event_links(request, [
        %{
          source_watermark_event_id: "watermark-event-1",
          source_watermark_key: "source_watermark:mission-alpha:telemetry:flight-tsdb"
        }
      ])

    assert link.target == :source_watermark_event
    assert link.target_id == "watermark-event-1"
    assert link.context.observable_id == "source_watermark:mission-alpha:telemetry:flight-tsdb"
    assert link.context.data.realm == :rehearsal
    assert link.context.data.data_source_id == "events-tsdb"
    assert link.context.data.source_binding_id == "events-binding"
    assert link.context.scope.spacecraft_id == "sc-alpha"

    assert operational_event_link.target == :operational_event

    assert operational_event_link.target_id ==
             "operational_event:source_watermark_event:watermark-event-1"

    assert operational_event_link.context.observable_id ==
             "source_watermark:mission-alpha:telemetry:flight-tsdb"

    assert operational_event_link.context.data.realm == :rehearsal
    assert operational_event_link.context.data.data_source_id == "events-tsdb"
    assert operational_event_link.context.data.source_binding_id == "events-binding"
    assert operational_event_link.context.scope.spacecraft_id == "sc-alpha"
  end

  test "mission event evidence refs include canonical operational event source refs" do
    assert [
             %EvidenceRef{
               kind: :mission_event,
               id: "mission_event:operational-event-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :events,
               confidence: :projected
             },
             %EvidenceRef{
               kind: :operational_event,
               id: "operational-event-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :events,
               confidence: :direct
             }
           ] =
             DataLinks.mission_event_evidence_refs([
               %{
                 mission_event_id: "mission_event:operational-event-1",
                 occurred_at: ~U[2026-06-21 20:00:00Z],
                 source_record_kind: :operational_event,
                 source_record_id: "operational-event-1"
               }
             ])
  end

  test "command queue entry evidence refs identify durable queue rows" do
    assert [
             %EvidenceRef{
               kind: :command_queue_entry,
               id: "queue-entry-1",
               observed_at: ~U[2026-06-17 12:00:00Z],
               source: :operational_observables,
               confidence: :direct
             }
           ] =
             DataLinks.command_queue_entry_evidence_refs([
               %{
                 command_queue_entry_id: "queue-entry-1",
                 enqueued_at: ~U[2026-06-17 12:00:00Z]
               },
               %{
                 command_queue_entry_id: "queue-entry-1",
                 enqueued_at: ~U[2026-06-17 12:00:00Z]
               },
               %{command_queue_entry_id: nil}
             ])
  end

  test "command verifier instance evidence refs identify durable verifier rows" do
    assert [
             %EvidenceRef{
               kind: :command_verifier_instance,
               id: "verifier-instance-1",
               observed_at: ~U[2026-06-17 12:01:45Z],
               source: :operational_observables,
               confidence: :direct
             }
           ] =
             DataLinks.command_verifier_instance_evidence_refs([
               %{
                 command_verifier_instance_id: "verifier-instance-1",
                 matched_at: ~U[2026-06-17 12:01:45Z]
               },
               %{
                 command_verifier_instance_id: "verifier-instance-1",
                 matched_at: ~U[2026-06-17 12:01:45Z]
               },
               %{command_verifier_instance_id: nil}
             ])
  end

  test "command verifier matched record evidence refs identify durable matched records" do
    assert [
             %EvidenceRef{
               kind: :telemetry_sample,
               id: "sample-1",
               observed_at: ~U[2026-06-17 12:01:45Z],
               source: :operational_observables,
               confidence: :direct
             },
             %EvidenceRef{
               kind: :transport_action_request,
               id: "action-request-1",
               observed_at: ~U[2026-06-17 12:01:46Z],
               source: :operational_observables,
               confidence: :direct
             },
             %EvidenceRef{
               kind: :transport_capability_record,
               id: "transport-record-1",
               observed_at: ~U[2026-06-17 12:01:47Z],
               source: :operational_observables,
               confidence: :direct
             }
           ] =
             DataLinks.command_verifier_matched_record_evidence_refs([
               %{
                 matched_record_kind: :telemetry_sample,
                 matched_record_id: "sample-1",
                 matched_at: ~U[2026-06-17 12:01:45Z]
               },
               %{
                 matched_record_kind: "transport_action_request",
                 matched_record_id: "action-request-1",
                 matched_at: ~U[2026-06-17 12:01:46Z]
               },
               %{
                 matched_record_kind: :transport_capability_record,
                 matched_record_id: "transport-record-1",
                 matched_at: ~U[2026-06-17 12:01:47Z]
               },
               %{
                 matched_record_kind: :transport_action_request,
                 matched_record_id: "action-request-1",
                 matched_at: ~U[2026-06-17 12:01:46Z]
               },
               %{
                 matched_record_kind: nil,
                 matched_record_id: nil,
                 matched_at: ~U[2026-06-17 12:01:48Z]
               }
             ])
  end

  test "source binding interval evidence refs identify selected binding events" do
    assert [
             %EvidenceRef{
               kind: :source_binding_interval,
               id: "effective_interval:source_binding:binding-event-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :telemetry,
               confidence: :projected
             },
             %EvidenceRef{
               kind: :source_binding_event,
               id: "binding-event-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :telemetry,
               confidence: :direct
             },
             %EvidenceRef{
               kind: :source_binding,
               id: "flight-telemetry",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :telemetry,
               confidence: :direct
             }
           ] =
             DataLinks.source_binding_interval_evidence_refs(
               [
                 %{
                   binding_id: "flight-telemetry",
                   data_binding_event_id: "binding-event-1",
                   started_at: ~U[2026-06-21 20:00:00Z]
                 }
               ],
               source: :telemetry
             )
  end

  test "operational interval evidence refs identify projected interval and source event" do
    assert [
             %EvidenceRef{
               kind: :application_binding_interval,
               id: "effective_interval:application_binding:event-1:rule-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :operational_observables,
               confidence: :projected
             },
             %EvidenceRef{
               kind: :operational_interval,
               id: "event-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :operational_observables,
               confidence: :direct
             }
           ] =
             DataLinks.operational_interval_evidence_refs(
               [
                 %{
                   interval_id: "effective_interval:application_binding:event-1:rule-1",
                   kind: :application_binding,
                   source_event_id: "event-1",
                   starts_at: ~U[2026-06-21 20:00:00Z]
                 }
               ],
               source: :operational_observables
             )
  end

  test "transport execution interval evidence refs use a specific interval kind" do
    assert [
             %EvidenceRef{
               kind: :transport_execution_interval,
               id: "effective_interval:transport_execution:event-1:transport-alpha",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :operational_observables,
               confidence: :projected
             },
             %EvidenceRef{
               kind: :operational_interval,
               id: "event-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :operational_observables,
               confidence: :direct
             }
           ] =
             DataLinks.operational_interval_evidence_refs(
               [
                 %{
                   interval_id: "effective_interval:transport_execution:event-1:transport-alpha",
                   kind: :transport_execution,
                   source_event_id: "event-1",
                   starts_at: ~U[2026-06-21 20:00:00Z]
                 }
               ],
               source: :operational_observables
             )
  end

  test "native operational interval evidence refs use specific interval kinds" do
    refs =
      DataLinks.operational_interval_evidence_refs(
        [
          %{
            interval_id: "effective_interval:transport_connection_state:event-1",
            kind: :transport_connection_state,
            source_event_id: "event-1",
            starts_at: ~U[2026-06-21 20:00:00Z]
          },
          %{
            interval_id: "effective_interval:ground_station_connection_state:event-2",
            kind: :ground_station_connection_state,
            source_event_id: "event-2",
            starts_at: ~U[2026-06-21 20:01:00Z]
          },
          %{
            interval_id: "effective_interval:operational_observable_state:event-3",
            kind: :operational_observable_state,
            source_event_id: "event-3",
            starts_at: ~U[2026-06-21 20:02:00Z],
            payload: %{"observable_id" => "ground.station.antenna_pointing_state"}
          },
          %{
            interval_id: "effective_interval:link_rf_lock_state:event-4",
            kind: :link_rf_lock_state,
            source_event_id: "event-4",
            starts_at: ~U[2026-06-21 20:03:00Z]
          },
          %{
            interval_id: "effective_interval:link_frame_sync_state:event-5",
            kind: :link_frame_sync_state,
            source_event_id: "event-5",
            starts_at: ~U[2026-06-21 20:04:00Z]
          }
        ],
        source: :operational_observables
      )

    assert Enum.map(refs, & &1.kind) == [
             :transport_connection_state_interval,
             :operational_interval,
             :ground_station_connection_state_interval,
             :operational_interval,
             :ground_station_antenna_pointing_state_interval,
             :operational_interval,
             :link_rf_lock_state_interval,
             :operational_interval,
             :link_frame_sync_state_interval,
             :operational_interval
           ]

    assert Enum.map(refs, & &1.confidence) == [
             :projected,
             :direct,
             :projected,
             :direct,
             :projected,
             :direct,
             :projected,
             :direct,
             :projected,
             :direct
           ]
  end

  test "limit definition interval evidence refs include activation events and definitions" do
    assert [
             %EvidenceRef{
               kind: :limit_definition_interval,
               id: "limit-interval-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :limits,
               confidence: :direct
             },
             %EvidenceRef{
               kind: :limit_definition_lifecycle_event,
               id: "limit-lifecycle-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :limits,
               confidence: :direct
             },
             %EvidenceRef{
               kind: :limit_definition,
               id: "limit-def-1",
               observed_at: ~U[2026-06-21 20:00:00Z],
               source: :limits,
               confidence: :direct
             },
             %EvidenceRef{
               kind: :limit_definition_lifecycle_event,
               id: "limit-lifecycle-2",
               source: :limits,
               confidence: :best_effort
             }
           ] =
             DataLinks.limit_definition_interval_evidence_refs([
               %{
                 interval_id: "limit-interval-1",
                 limit_definition_lifecycle_event_id: "limit-lifecycle-1",
                 limit_definition_id: "limit-def-1",
                 observed_at: ~U[2026-06-21 20:00:00Z],
                 complete?: true
               },
               %{
                 limit_definition_lifecycle_event_id: "limit-lifecycle-2",
                 limit_definition_id: "limit-def-1",
                 observed_at: ~U[2026-06-21 21:00:00Z],
                 complete?: false
               }
             ])
  end

  test "telemetry revision decision evidence refs use decision timestamps from state projections" do
    assert [
             %EvidenceRef{
               kind: :telemetry_revision_decision_event,
               id: "decision-event-1",
               observed_at: ~U[2026-06-22 12:10:00Z],
               source: :events,
               confidence: :direct
             },
             %EvidenceRef{
               kind: :operational_event,
               id:
                 "operational_event:telemetry_observation_identity_decision_event:decision-event-1",
               observed_at: ~U[2026-06-22 12:10:00Z],
               source: :events,
               confidence: :direct
             }
           ] =
             DataLinks.telemetry_revision_decision_event_evidence_refs([
               %{
                 decision_event_id: "decision-event-1",
                 decided_at: ~U[2026-06-22 12:10:00Z]
               }
             ])
  end

  defp source_request(logical_source) do
    %PlannedSourceRequest{
      request_id: "source-request-#{logical_source}",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      logical_source: logical_source,
      scope_context: %ScopeContext{spacecraft_id: "sc-alpha"},
      time_context: %{mode: :replay_run, replay_run_id: "replay-run-1"},
      data_context: data_context(logical_source)
    }
  end

  defp data_context(:telemetry) do
    %DataContext{
      realm: :rehearsal,
      replay_run_id: "replay-run-1",
      source_contexts: %{
        telemetry: %{
          data_source_id: "rehearsal-tsdb",
          source_binding_id: "rehearsal-binding",
          dataset: "rehearsal",
          view: :all_revisions,
          validity_state: :conflict
        }
      }
    }
  end

  defp data_context(:limits) do
    %DataContext{
      realm: :rehearsal,
      replay_run_id: "replay-run-1",
      source_contexts: %{
        limits: %{
          data_source_id: "limits-tsdb",
          source_binding_id: "limits-binding",
          dataset: "limits"
        }
      }
    }
  end

  defp data_context(:events) do
    %DataContext{
      realm: :rehearsal,
      replay_run_id: "replay-run-1",
      source_contexts: %{
        events: %{
          data_source_id: "events-tsdb",
          source_binding_id: "events-binding",
          dataset: "events"
        }
      }
    }
  end

  defp data_context(:operational_observables) do
    %DataContext{
      realm: :rehearsal,
      replay_run_id: "replay-run-1",
      source_contexts: %{
        operational_observables: %{
          data_source_id: "ops-tsdb",
          source_binding_id: "ops-binding",
          dataset: "operational_observables"
        }
      }
    }
  end
end
