defmodule CadenceWeb.OpsDashboardShowLive.SourcePresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardAction,
    DashboardResolveResult,
    DataLink,
    EvidenceRef,
    PlacementFrames,
    ResolveWarning
  }

  alias CadenceWeb.OpsDashboardShowLive.SourcePresentation

  test "placement_warning_summaries present warning details, evidence, links, and actions" do
    observed_at = ~U[2026-06-25 12:00:00Z]

    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :watermark_unknown,
          severity: :warning,
          message: "Watermark unavailable",
          details: %{
            retry_after_ms: 500,
            actions: [
              %DashboardAction{
                action_id: "inspect-source-health",
                target: :source_health,
                label: "Inspect source health"
              }
            ]
          },
          evidence: [
            %EvidenceRef{
              kind: :source_health_event,
              id: "source-health-1",
              source: :dashboard_engine,
              confidence: :high,
              observed_at: observed_at
            }
          ],
          links: [
            %DataLink{
              link_id: "source-health-link",
              label: "Source health",
              target: :source_health_event,
              target_id: "source-health-1",
              source: :dashboard_engine,
              presentation: :evidence_panel
            }
          ]
        }
      ]
    }

    assert [
             %{
               code: :watermark_unknown,
               code_text: "watermark_unknown",
               severity: :warning,
               severity_text: "warning",
               label: "Freshness unknown",
               message: "Watermark unavailable",
               detail_rows: detail_rows,
               evidence: [evidence],
               links: [link],
               actions: [action]
             }
           ] = SourcePresentation.placement_warning_summaries(placement_frames)

    assert %{label: "Retry after ms", value: "500"} in detail_rows
    assert evidence.kind_text == "source health event"
    assert evidence.observed_at_text == "2026-06-25T12:00:00Z"
    assert link.target_text == "source health event"
    assert action.target == :source_health
  end

  test "placement_warning_summaries label missing operational snapshots distinctly" do
    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :missing_snapshot,
          severity: :warning,
          message: "Operational observable snapshot is missing",
          details: %{
            logical_source: :operational_observables,
            supported_capability: :link_rf_lock_state,
            observable_ids: ["link.rf_lock_state"],
            frame_ids: ["ops-request-1:link_rf_lock_state"]
          }
        }
      ]
    }

    assert [
             %{
               code: :missing_snapshot,
               code_text: "missing_snapshot",
               severity: :warning,
               severity_text: "warning",
               label: "Snapshot missing",
               message: "Operational observable snapshot is missing",
               details: details
             }
           ] = SourcePresentation.placement_warning_summaries(placement_frames)

    assert details.logical_source == :operational_observables
    assert details.supported_capability == :link_rf_lock_state
    assert details.observable_ids == ["link.rf_lock_state"]
  end

  test "placement_warning_summaries label source capability blockers generically" do
    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :unsupported_source_capability,
          severity: :warning,
          details: %{
            requested_sampling: :latest,
            requested_source_products: [:link_rf_metric],
            supported_products: [:operational_metric_history]
          }
        }
      ]
    }

    assert [
             %{
               label: "Unsupported source capability",
               message: "Unsupported source capability",
               detail_rows: detail_rows
             }
           ] = SourcePresentation.placement_warning_summaries(placement_frames)

    assert %{label: "Requested sampling", value: "latest"} in detail_rows
    assert %{label: "Requested source products 1", value: "link_rf_metric"} in detail_rows
    assert %{label: "Supported products 1", value: "operational_metric_history"} in detail_rows
  end

  test "dashboard_degraded? reads explicit plan metadata degradation" do
    assert SourcePresentation.dashboard_degraded?(%{plan_metadata: %{"degraded?" => true}})
    refute SourcePresentation.dashboard_degraded?(%{plan_metadata: %{}})
    refute SourcePresentation.dashboard_degraded?(nil)
  end

  test "source_health_summaries expose redacted source probe diagnostics" do
    result = %DashboardResolveResult{
      watermarks: [
        %Cadence.Dashboards.SourceWatermark{
          logical_source: :telemetry,
          request_id: "req-telemetry",
          source_binding_id: "binding-flight",
          data_source_id: "managed-questdb",
          realm: :flight,
          confidence: :authoritative,
          freshness_state: :fresh,
          latest_receipt_time: ~U[2026-06-24 01:00:00Z],
          meta: %{
            source_health_event_id: "source-health-event-1",
            source_health_reason: :source_adapter_probe_unsupported,
            source_health_probe_kind: "adapter_unsupported",
            source_health_probe_message: "adapter does not support active probes",
            source_health_probe_metadata: %{
              "storage" => "questdb",
              "password" => "plaintext"
            }
          }
        }
      ],
      planned_source_requests: []
    }

    assert [
             %{
               source_health_probe_kind_text: "adapter_unsupported",
               source_health_probe_message_text: "adapter does not support active probes",
               source_health_probe_metadata_text: probe_metadata,
               detail_rows: detail_rows
             }
           ] = SourcePresentation.source_health_summaries(result)

    assert probe_metadata =~ "storage=questdb"
    assert probe_metadata =~ "password=redacted"
    refute probe_metadata =~ "plaintext"

    assert %{label: "Source health event", value: "source-health-event-1"} in detail_rows
    assert %{label: "Probe kind", value: "adapter_unsupported"} in detail_rows
    assert %{label: "Probe metadata", value: probe_metadata} in detail_rows
  end

  test "source_health_summaries handles missing engine result" do
    assert SourcePresentation.source_health_summaries(%DashboardResolveResult{}) == []
  end

  test "source_selection_summaries expose selected and skipped dashboard sources" do
    result = %DashboardResolveResult{
      plan_metadata: %{
        source_selection_by_request_id: %{
          "req-telemetry" => %{
            logical_source: :telemetry,
            strategy: :current_binding,
            selected_source_binding_id: "secondary-flight",
            selected_data_source_id: "secondary-questdb",
            selected_dataset: "flight",
            requested_realm: :flight,
            candidate_count: 2,
            eligible_candidate_count: 1,
            candidates: [
              %{
                binding_id: "primary-flight",
                data_source_id: "primary-questdb",
                logical_source: :telemetry,
                realm: :flight,
                decision: :rejected,
                started_at: ~U[2026-06-21 20:00:00Z],
                ended_at: ~U[2026-06-21 21:00:00Z],
                reasons: [:source_unavailable],
                source_health: :unavailable,
                source_health_reason: :source_connection_failed,
                source_health_freshness: :fresh,
                source_readiness_policy_id: :default,
                capability_posture: %{
                  requested_products: [:link_rf_metric_history],
                  supported_products: [:transport_bitrate_history],
                  unsupported: [
                    %{
                      capability: :products,
                      requested: [:link_rf_metric_history],
                      supported: [:transport_bitrate_history],
                      missing: [:link_rf_metric_history],
                      fallback: :none
                    }
                  ]
                }
              },
              %{
                binding_id: "secondary-flight",
                data_source_id: "secondary-questdb",
                logical_source: :telemetry,
                realm: :flight,
                decision: :selected,
                reasons: []
              }
            ]
          }
        }
      }
    }

    assert [
             %{
               request_id: "req-telemetry",
               logical_source_text: "Telemetry",
               strategy_text: "current_binding",
               selected_binding_id: "secondary-flight",
               selected_data_source_id: "secondary-questdb",
               selected_dataset: "flight",
               requested_realm: "flight",
               candidate_count: 2,
               eligible_candidate_count: 1,
               rejected_candidate_count: 1,
               skipped_candidate_count: 1,
               state: :selected,
               state_text: "selected",
               candidates: [rejected, selected]
             }
           ] = SourcePresentation.source_selection_summaries(result)

    assert rejected.binding_id == "primary-flight"
    assert rejected.decision == :rejected
    assert rejected.reasons_text == "source_unavailable"
    assert rejected.source_health_text == "unavailable"
    assert rejected.source_health_reason_text == "source_connection_failed"
    assert rejected.source_health_freshness_text == "fresh"
    assert rejected.requested_products_text == "link_rf_metric_history"
    assert rejected.supported_products_text == "transport_bitrate_history"
    assert rejected.missing_products_text == "link_rf_metric_history"
    assert rejected.readiness_policy_id_text == "default"
    assert rejected.started_at_text == "2026-06-21T20:00:00Z"
    assert rejected.ended_at_text == "2026-06-21T21:00:00Z"
    assert rejected.inventory_action_label == "Open source inventory"

    assert rejected.inventory_query == %{
             "data_source_id" => "primary-questdb",
             "logical_source" => "telemetry",
             "realm" => "flight",
             "source_binding_id" => "primary-flight"
           }

    assert selected.binding_id == "secondary-flight"
    assert selected.decision == :selected
    assert selected.reasons_text == ""

    assert selected.inventory_query == %{
             "data_source_id" => "secondary-questdb",
             "logical_source" => "telemetry",
             "realm" => "flight",
             "source_binding_id" => "secondary-flight"
           }
  end

  test "dashboard warning summaries preserve typed telemetry actions" do
    action = %DashboardAction{
      action_id: "telemetry-warning-explore:req-telemetry:HK.counter",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{"point_id" => "HK.counter", "realm" => "flight"},
      source: :warning
    }

    result = %DashboardResolveResult{
      dashboard_warnings: [
        %ResolveWarning{
          code: :unsupported_time_axis,
          severity: :warning,
          details: %{
            source_request_id: "req-telemetry",
            point_id: "HK.counter",
            requested_axis: :generation_time,
            fallback_axis: :receipt_time,
            supported_time_axes: [:receipt_time],
            actions: [action]
          }
        }
      ]
    }

    assert [%{actions: actions, detail_rows: detail_rows}] =
             SourcePresentation.dashboard_warning_summaries(result)

    assert Enum.any?(actions, fn
             %DashboardAction{
               action_id: "telemetry-warning-explore:req-telemetry:HK.counter",
               target: :telemetry_explore,
               kind: :invoke,
               query: %{"point_id" => "HK.counter", "realm" => "flight"},
               source: :warning
             } ->
               true

             _action ->
               false
           end)

    refute Enum.any?(detail_rows, &(&1.label =~ "Actions"))
    assert %{value: "generation_time"} = Enum.find(detail_rows, &(&1.label == "Requested axis"))
    assert %{value: "receipt_time"} = Enum.find(detail_rows, &(&1.label == "Executed axis"))
    assert %{value: "receipt_time"} = Enum.find(detail_rows, &(&1.label == "Supported axes"))
  end

  test "dashboard warning summaries label non-canonical data views" do
    result = %DashboardResolveResult{
      dashboard_warnings: [
        %ResolveWarning{
          code: :all_revisions_view,
          severity: :warning,
          message: "Telemetry source is showing all observation revisions",
          details: %{
            data_view: :all_revisions,
            canonical_default?: false,
            point_id: "HK.counter"
          }
        }
      ]
    }

    assert [
             %{
               code: :all_revisions_view,
               label: "All revisions",
               severity: :warning,
               detail_rows: detail_rows
             }
           ] = SourcePresentation.dashboard_warning_summaries(result)

    assert %{value: "all_revisions"} = Enum.find(detail_rows, &(&1.label == "Data view"))
    assert %{value: "false"} = Enum.find(detail_rows, &(&1.label == "Canonical default?"))
    assert %{value: "HK.counter"} = Enum.find(detail_rows, &(&1.label == "Point id"))
  end

  test "dashboard warning summaries do not synthesize fallback source actions" do
    result = %DashboardResolveResult{
      dashboard_warnings: [
        %ResolveWarning{
          code: :missing_source_binding,
          severity: :error,
          details: %{
            logical_source: :telemetry,
            realm: :flight,
            data_source_id: "flight-questdb"
          }
        }
      ]
    }

    assert [%{actions: [], detail_rows: detail_rows}] =
             SourcePresentation.dashboard_warning_summaries(result)

    refute Enum.any?(detail_rows, &(&1.label =~ "Actions"))
  end

  test "dashboard warning summaries explain historical source binding misses" do
    result = %DashboardResolveResult{
      dashboard_warnings: [
        %ResolveWarning{
          code: :missing_source_binding,
          severity: :error,
          details: %{
            logical_source: :telemetry,
            realm: :flight,
            source_binding_at: ~U[2026-06-21 19:30:00Z],
            source_binding_miss_reason: :source_binding_not_started_at_requested_time,
            nearest_source_binding_id: "mission-flight-telemetry",
            nearest_data_source_id: "mission-questdb-v1",
            nearest_source_binding_started_at: ~U[2026-06-21 20:00:00Z],
            nearest_source_binding_ended_at: ~U[2026-06-21 21:00:00Z]
          }
        }
      ]
    }

    assert [%{detail_rows: detail_rows}] = SourcePresentation.dashboard_warning_summaries(result)

    assert %{value: "2026-06-21T19:30:00Z"} =
             Enum.find(detail_rows, &(&1.label == "Source binding at"))

    assert %{value: "source_binding_not_started_at_requested_time"} =
             Enum.find(detail_rows, &(&1.label == "Source binding miss reason"))

    assert %{value: "mission-flight-telemetry"} =
             Enum.find(detail_rows, &(&1.label == "Nearest source binding id"))

    assert %{value: "mission-questdb-v1"} =
             Enum.find(detail_rows, &(&1.label == "Nearest data source id"))

    assert %{value: "2026-06-21T20:00:00Z"} =
             Enum.find(detail_rows, &(&1.label == "Nearest source binding started at"))

    assert %{value: "2026-06-21T21:00:00Z"} =
             Enum.find(detail_rows, &(&1.label == "Nearest source binding ended at"))
  end
end
