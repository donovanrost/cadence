defmodule CadenceWeb.OpsDashboardShowLive.PresentationContractTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardAction,
    DashboardResolveResult,
    Field,
    Frame,
    PlacementFrames,
    PlannedSourceRequest,
    RenderWidget,
    ResolveWarning
  }

  alias Cadence.DataSources.SourceWatermark

  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation
  alias CadenceWeb.OpsDashboardShowLive.SourcePresentation
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  test "source health summaries include cache and circuit status" do
    result = %DashboardResolveResult{
      watermarks: [
        %SourceWatermark{
          logical_source: :telemetry,
          request_id: "req-telemetry",
          source_binding_id: "binding-flight",
          data_source_id: "managed-questdb",
          realm: :flight,
          confidence: :authoritative,
          freshness_state: :fresh
        }
      ],
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-telemetry",
          logical_source: :telemetry,
          metadata: %{
            capability_provenance: %{
              source_binding_id: "binding-flight",
              data_source_id: "managed-questdb",
              realm: :flight
            }
          }
        }
      ],
      plan_metadata: %{
        source_selection_by_request_id: %{
          "req-telemetry" => %{
            selected_source_binding_id: "binding-flight",
            selected_data_source_id: "managed-questdb",
            strategy: :current_binding
          }
        },
        cache: %{
          source_result_cache_by_request_id: %{
            "req-telemetry" => %{status: :stale, reasons: [:source_degraded]}
          },
          frame_cache_by_placement: %{
            "placement-counter" => %{"req-telemetry" => %{status: :refresh}}
          }
        }
      },
      dashboard_warnings: [
        %ResolveWarning{
          code: :source_degraded,
          severity: :error,
          details: %{
            source_request_id: "req-telemetry",
            circuit_state: :open,
            failure_count: 2,
            failure_threshold: 2,
            retry_after_ms: 60_000
          }
        }
      ]
    }

    assert [
             %{
               source_cache_text: "stale rejected",
               source_cache_reasons_text: "source_degraded",
               frame_cache_text: "refresh",
               circuit_state_text: "open",
               execution_status_text: "source_degraded",
               execution_severity_text: "warning",
               execution_operator_action_text: "inspect_source_health",
               execution_runtime_action_text: "wait_for_source_health",
               execution_actionable?: true,
               execution_retryable?: true,
               source_warning_text: "Source degraded",
               detail_rows: detail_rows
             }
           ] = SourcePresentation.source_health_summaries(result)

    assert %{value: "stale rejected"} = Enum.find(detail_rows, &(&1.label == "Source cache"))

    assert %{value: "source_degraded"} =
             Enum.find(detail_rows, &(&1.label == "Source cache reason"))

    assert %{value: "refresh"} = Enum.find(detail_rows, &(&1.label == "Frame cache"))
    assert %{value: "source_degraded"} = Enum.find(detail_rows, &(&1.label == "Execution status"))
    assert %{value: "warning"} = Enum.find(detail_rows, &(&1.label == "Execution severity"))

    assert %{value: "inspect_source_health"} =
             Enum.find(detail_rows, &(&1.label == "Execution action"))

    assert %{value: "wait_for_source_health"} =
             Enum.find(detail_rows, &(&1.label == "Execution runtime action"))

    assert %{value: "true"} = Enum.find(detail_rows, &(&1.label == "Execution actionable"))
    assert %{value: "true"} = Enum.find(detail_rows, &(&1.label == "Execution retryable"))
    assert %{value: "open"} = Enum.find(detail_rows, &(&1.label == "Circuit"))
    assert %{value: "2/2"} = Enum.find(detail_rows, &(&1.label == "Circuit failures"))
    assert %{value: "60000"} = Enum.find(detail_rows, &(&1.label == "Circuit retry after"))

    assert SourcePresentation.dashboard_degraded?(result)

    assert [
             %{
               incident_kind: :source_execution,
               incident_status: :source_degraded,
               incident_status_text: "source_degraded",
               incident_title: "Source Execution",
               execution_dashboard_degraded?: true,
               evidence: incident_evidence
             }
           ] = SourcePresentation.source_incident_summaries(result)

    assert Enum.any?(
             incident_evidence,
             &match?(%{kind: :source_request, id: "req-telemetry"}, &1)
           )

    assert %{status_text: "fresh", actions: source_health_actions} =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-evidence-mode" => "health",
               "source-request-id" => "req-telemetry",
               "logical-source" => "telemetry"
             })

    assert Enum.any?(
             source_health_actions,
             &match?(
               %DashboardAction{
                 target: :source_health,
                 kind: :invoke,
                 query: %{"data_source_id" => "managed-questdb"}
               },
               &1
             )
           )

    assert %{
             status_text: "source_degraded",
             detail_rows: source_execution_detail_rows,
             actions: source_execution_actions
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-evidence-mode" => "execution",
               "cache-evidence-status" => "stale",
               "requested-source-binding-id" => "binding-flight",
               "source-request-id" => "req-telemetry",
               "logical-source" => "telemetry"
             })

    assert %{value: "stale"} =
             Enum.find(source_execution_detail_rows, &(&1.label == "Cache evidence status"))

    assert %{value: "binding-flight"} =
             Enum.find(source_execution_detail_rows, &(&1.label == "Requested source binding"))

    assert %{
             status_text: "unavailable",
             message: unavailable_message,
             detail_rows: unavailable_detail_rows
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-evidence-mode" => "execution",
               "source-evidence-state" => "unavailable",
               "cache-evidence-status" => "stale",
               "requested-source-binding-id" => "binding-flight",
               "source-request-id" => "req-telemetry",
               "logical-source" => "telemetry"
             })

    assert unavailable_message =~ "Widget source status is unavailable"

    assert %{value: "unavailable"} =
             Enum.find(unavailable_detail_rows, &(&1.label == "Widget source status"))

    assert %{value: "execution"} =
             Enum.find(unavailable_detail_rows, &(&1.label == "Widget evidence mode"))

    assert Enum.any?(
             source_execution_actions,
             &match?(
               %DashboardAction{
                 target: :source_inventory,
                 kind: :invoke,
                 query: %{"source_binding_id" => "binding-flight"}
               },
               &1
             )
           )

    assert [
             %{
               code: :source_degraded,
               detail_rows: warning_detail_rows,
               actions: warning_actions
             }
           ] = SourcePresentation.dashboard_warning_summaries(result)

    assert %{value: "source_degraded"} =
             Enum.find(warning_detail_rows, &(&1.label == "Source execution status"))

    assert %{value: "inspect_source_health"} =
             Enum.find(warning_detail_rows, &(&1.label == "Source execution action"))

    refute Enum.any?(warning_detail_rows, &(&1.label =~ "Actions"))

    assert Enum.any?(
             warning_actions,
             &match?(
               %DashboardAction{
                 target: :source_health,
                 kind: :invoke,
                 query: %{"data_source_id" => "managed-questdb"}
               },
               &1
             )
           )
  end

  test "dashboard warning summaries synthesize source execution policy warnings" do
    result = %DashboardResolveResult{
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-telemetry",
          logical_source: :telemetry,
          metadata: %{
            capability_provenance: %{
              source_binding_id: "binding-flight",
              data_source_id: "managed-questdb",
              realm: :flight
            }
          }
        }
      ],
      plan_metadata: %{
        cache: %{
          source_result_cache_by_request_id: %{
            "req-telemetry" => %{status: :source_execution_failed, reason: :timeout}
          }
        }
      },
      dashboard_warnings: []
    }

    assert SourcePresentation.dashboard_degraded?(result)

    assert [
             %{
               incident_kind: :source_execution,
               incident_status: :source_execution_failed,
               incident_status_text: "source_execution_failed",
               execution_dashboard_degraded?: true
             }
           ] =
             result
             |> SourcePresentation.source_incident_summaries()
             |> Enum.map(
               &Map.take(&1, [
                 :incident_kind,
                 :incident_status,
                 :incident_status_text,
                 :execution_dashboard_degraded?
               ])
             )

    assert [
             %{
               code: :source_execution_failed,
               severity: :error,
               label: "Source failed",
               detail_rows: detail_rows,
               evidence: [%{kind: :source_request, id: "req-telemetry"}]
             }
           ] = SourcePresentation.dashboard_warning_summaries(result)

    assert %{value: "source_execution_failed"} =
             Enum.find(detail_rows, &(&1.label == "Source execution status"))

    assert %{value: "inspect_source_failure"} =
             Enum.find(detail_rows, &(&1.label == "Source execution action"))

    assert %{value: "retry_source_execution"} =
             Enum.find(detail_rows, &(&1.label == "Source execution runtime action"))

    assert %{
             kind: :source,
             status_text: "source_execution_failed",
             subject_rows: source_rows,
             detail_rows: source_detail_rows,
             evidence: [%{kind: :source_request, id: "req-telemetry"}]
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-request-id" => "req-telemetry",
               "logical-source" => "telemetry"
             })

    assert %{value: "req-telemetry"} = Enum.find(source_rows, &(&1.label == "Source request"))

    assert %{value: "source_execution_failed"} =
             Enum.find(source_detail_rows, &(&1.label == "Execution status"))
  end

  test "time-series source markers include watermark cursors and revision ranges" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-revisions",
          source: :telemetry,
          shape: :wide,
          fields: [
            %Field{
              name: "time",
              kind: :time,
              values: [~U[2026-06-17 10:00:00Z], ~U[2026-06-17 10:05:00Z]]
            },
            %Field{name: "HK.counter", kind: :number, values: [41, 42]}
          ],
          meta: %{
            source_request_id: "req-revisions",
            logical_source: :telemetry,
            observable_id: "HK.counter",
            point_id: "HK.counter",
            source_binding_id: "binding-flight",
            data_source_id: "questdb-flight",
            dataset: "flight-telemetry",
            realm: :flight,
            data_view: :canonical,
            warning_codes: [:corrected_range, :advisory_backfill],
            revision_state: %{
              identity_count: 2,
              canonical_count: 1,
              superseded_count: 1,
              advisory_count: 1,
              dependency_fingerprint: "telemetry-revision:abc",
              dependency: %{
                fingerprint: "telemetry-revision:abc",
                observation_identity_ids: ["identity-1", "identity-2"]
              }
            },
            telemetry_revision_dependency: %{
              fingerprint: "telemetry-revision:abc",
              observation_identity_ids: ["identity-1", "identity-2"]
            },
            source_request_context: %{
              source_request_id: "req-revisions",
              logical_source: :telemetry,
              time_mode: :archive,
              time_axis: :receipt_time,
              requested_realm: :flight,
              requested_data_view: :canonical,
              requested_data_source_id: "questdb-flight",
              requested_source_binding_id: "binding-flight",
              requested_dataset: "flight-telemetry"
            },
            source_watermarks: [
              %{
                logical_source: :telemetry,
                request_id: "req-revisions",
                source_binding_id: "binding-flight",
                data_source_id: "questdb-flight",
                dataset: "flight-telemetry",
                realm: :flight,
                confidence: :best_effort,
                freshness_state: :fresh,
                complete_through: ~U[2026-06-17 10:04:30Z],
                latest_receipt_time: ~U[2026-06-17 10:05:00Z],
                source_watermark_event_id: "watermark-event-1"
              }
            ]
          }
        }
      ]
    }

    widget = %RenderWidget{type: :time_series}
    markers = WidgetPresentation.event_markers(placement_frames, widget)

    watermark_marker = Enum.find(markers, &(&1.marker_type == "source_watermark_cursor"))

    assert watermark_marker.cursor_kind == "complete_through"
    assert watermark_marker.timestamp_ms == 1_781_690_670_000
    assert watermark_marker.source_watermark_event_id == "watermark-event-1"
    assert watermark_marker.source_request_id == "req-revisions"
    assert watermark_marker.logical_source == "telemetry"
    assert watermark_marker.data_source_id == "questdb-flight"
    assert watermark_marker.source_binding_id == "binding-flight"
    assert watermark_marker.requested_data_view == "canonical"

    revision_markers =
      markers
      |> Enum.filter(&(&1.marker_type == "telemetry_revision_range"))
      |> Enum.sort_by(& &1.warning_code)

    assert Enum.map(revision_markers, & &1.warning_code) == [
             "advisory_backfill",
             "corrected_range"
           ]

    assert Enum.all?(revision_markers, &(&1.starts_at_ms == 1_781_690_400_000))
    assert Enum.all?(revision_markers, &(&1.ends_at_ms == 1_781_690_700_000))
    assert Enum.all?(revision_markers, &(&1.target == "telemetry_revision_state"))
    assert Enum.all?(revision_markers, &(&1.target_id == "telemetry-revision:abc"))
    assert Enum.all?(revision_markers, &(&1.source_request_id == "req-revisions"))
    assert Enum.all?(revision_markers, &(&1.requested_data_source_id == "questdb-flight"))
    assert Enum.all?(revision_markers, &(&1.requested_source_binding_id == "binding-flight"))
    assert Enum.all?(revision_markers, &(&1.identity_count == 2))
    assert Enum.any?(revision_markers, &(&1.revision_state == "corrected"))
    assert Enum.any?(revision_markers, &(&1.revision_state == "backfill"))

    assert %{detail_rows: detail_rows} =
             EvidencePresentation.evidence_inspector(
               %{frames_by_placement: %{"trend" => placement_frames}},
               %{
                 "kind" => "frame",
                 "placement-id" => "trend",
                 "observable-id" => "HK.counter"
               }
             )

    assert %{value: "2"} = Enum.find(detail_rows, &(&1.label == "Revision identities"))
    assert %{value: "1"} = Enum.find(detail_rows, &(&1.label == "Revision superseded"))
    assert %{value: "1"} = Enum.find(detail_rows, &(&1.label == "Revision advisory"))

    assert %{value: "telemetry-revision:abc"} =
             Enum.find(detail_rows, &(&1.label == "Revision dependency"))
  end
end
