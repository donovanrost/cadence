defmodule CadenceWeb.OpsDashboardShowLive.EvidencePresentationOverviewTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, PlacementFrames, ResolveWarning}
  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation

  test "summarizes source watermark event data links" do
    assert %{
             target: :source_watermark_event,
             target_text: "source watermark event",
             target_id: "watermark-event-1",
             source_text: "frame"
           } =
             EvidencePresentation.link_summary(%DataLink{
               link_id: "source_watermark_event:watermark-event-1",
               label: "Source watermark",
               target: :source_watermark_event,
               target_id: "watermark-event-1",
               source: :frame
             })
  end

  test "dashboard health evidence presents shareable rollup context" do
    assert %{
             kind: :dashboard_health,
             kind_text: "dashboard health",
             title: "Dashboard Health Evidence",
             subject: "dashboard health blocked",
             status_text: "blocked",
             subject_rows: subject_rows,
             detail_rows: detail_rows,
             evidence: [],
             links: [],
             actions: []
           } =
             EvidencePresentation.evidence_inspector(nil, %{
               "kind" => "dashboard_health",
               "dashboard-health-schema" => "dashboard_health_snapshot.v1",
               "dashboard-health-snapshot-id" => "dashboard_health_snapshot_abc123",
               "dashboard-health-state" => "blocked",
               "dashboard-health-severity" => "error",
               "dashboard-health-widgets" => "4",
               "dashboard-health-ready" => "1",
               "dashboard-health-degraded" => "1",
               "dashboard-health-stale" => "1",
               "dashboard-health-blocked" => "1",
               "dashboard-health-affected" => "3",
               "dashboard-health-states" => "ready,degraded,stale,blocked",
               "dashboard-health-affected-placements" =>
                 "degraded-placement,stale-placement,blocked-placement",
               "dashboard-health-blocked-placements" => "blocked-placement",
               "dashboard-health-stale-placements" => "stale-placement",
               "dashboard-health-degraded-placements" => "degraded-placement"
             })

    assert %{label: "Health snapshot schema", value: "dashboard_health_snapshot.v1"} in subject_rows
    assert %{label: "Health snapshot", value: "dashboard_health_snapshot_abc123"} in subject_rows
    assert %{label: "Widgets", value: "4"} in detail_rows
    assert %{label: "Affected widgets", value: "3"} in detail_rows
    assert %{label: "Blocked placements", value: "blocked-placement"} in detail_rows
    assert %{label: "Stale placements", value: "stale-placement"} in detail_rows
  end

  test "evidence inspector resolves placement warnings through runtime result accessors" do
    result = %{
      "frames_by_placement" => %{
        "placement-counter" => %PlacementFrames{
          warnings: [
            %ResolveWarning{
              code: :source_degraded,
              severity: :warning,
              message: "Telemetry source degraded",
              details: %{source_binding_id: "binding-flight"}
            }
          ]
        }
      }
    }

    assert %{
             kind: :warning,
             subject: "source_degraded",
             status_text: "warning",
             message: "Telemetry source degraded",
             detail_rows: detail_rows
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "warning",
               "placement-id" => "placement-counter",
               "warning-code" => "source_degraded"
             })

    assert %{label: "Source binding id", value: "binding-flight"} in detail_rows
  end
end
