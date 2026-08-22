defmodule CadenceWeb.OpsDashboardShowLive.SourcePresentationPlacementWarningsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardAction,
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
end
