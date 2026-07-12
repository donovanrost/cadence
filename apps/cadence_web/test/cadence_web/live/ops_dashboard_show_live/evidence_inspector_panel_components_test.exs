defmodule CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{DashboardAction, Document}
  alias CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelComponents

  test "evidence_panel renders subject details, evidence links, and actions" do
    link = evidence_link(:telemetry_point, "HK.counter", "Telemetry point")

    html =
      render_component(&EvidenceInspectorPanelComponents.evidence_panel/1,
        inspector: %{
          kind: :source,
          kind_text: "source",
          subject: "request-1",
          status: :resolved,
          status_text: "resolved",
          title: "Source evidence",
          message: nil,
          subject_rows: [%{label: "Source request", value: "request-1"}],
          detail_rows: [
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"}
          ],
          evidence: [],
          links: [link],
          actions: [telemetry_explore_action(), source_inventory_action()]
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=evidence",
        dashboard_lifecycle_events: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["source"] =
             document
             |> LazyHTML.query("#dashboard-evidence-inspector")
             |> LazyHTML.attribute("data-evidence-kind")

    assert ["request-1"] =
             document
             |> LazyHTML.query("#dashboard-evidence-inspector")
             |> LazyHTML.attribute("data-evidence-subject")

    assert ["/missions/mission-1/ops/dashboards/dashboard-1?panel=evidence"] =
             document
             |> LazyHTML.query("#dashboard-evidence-copy-link")
             |> LazyHTML.attribute("data-clipboard-text")

    assert "questdb-flight" =
             document
             |> LazyHTML.query(~s([data-evidence-detail="Data source"]))
             |> selected_text()

    assert ["telemetry point"] =
             document
             |> LazyHTML.query("[data-evidence-link-target]")
             |> LazyHTML.attribute("data-evidence-link-target")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["evidence_panel"] =
             document
             |> LazyHTML.query("#dashboard-evidence-explore")
             |> LazyHTML.attribute("data-dashboard-action-source")

    assert [explore_href] =
             document
             |> LazyHTML.query("#dashboard-evidence-explore")
             |> LazyHTML.attribute("href")

    assert explore_href =~ "/missions/mission-1/ops/telemetry/explore"
    assert explore_href =~ "source_dashboard_id=dashboard-1"

    assert ["source_inventory"] =
             document
             |> LazyHTML.query("#dashboard-evidence-source-inventory")
             |> LazyHTML.attribute("data-dashboard-action-target")

    assert [source_inventory_href] =
             document
             |> LazyHTML.query("#dashboard-evidence-source-inventory")
             |> LazyHTML.attribute("href")

    assert source_inventory_href =~ "/missions/mission-1/ops/data-sources"
    assert source_inventory_href =~ "source_dashboard_id=dashboard-1"
  end

  test "evidence_panel renders dashboard health activity link" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        payload: %{
          "schema" => "dashboard_health_snapshot_capture.v1",
          "snapshot_id" => "dashboard_health_snapshot_abc123",
          "snapshot_schema" => "dashboard_health_snapshot.v1"
        }
      )

    html =
      render_component(&EvidenceInspectorPanelComponents.evidence_panel/1,
        inspector: %{
          kind: :dashboard_health,
          kind_text: "dashboard health",
          subject: "dashboard health blocked",
          status: :blocked,
          status_text: "blocked",
          title: "Dashboard Health Evidence",
          message: "Captured dashboard health rollup for sharing and investigation.",
          subject_rows: [
            %{label: "Health snapshot schema", value: "dashboard_health_snapshot.v1"},
            %{label: "Health snapshot", value: "dashboard_health_snapshot_abc123"}
          ],
          detail_rows: [%{label: "Affected widgets", value: "3"}],
          evidence: [],
          links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&selected_placement=placement-stale",
        dashboard_lifecycle_events: [event]
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query("#dashboard-evidence-health-activity-link")
             |> LazyHTML.attribute("data-dashboard-health-activity-link")

    assert ["dashboard_health_snapshot_abc123"] =
             document
             |> LazyHTML.query("#dashboard-evidence-health-activity-link")
             |> LazyHTML.attribute("data-dashboard-health-activity-snapshot-id")

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-evidence-health-activity-link")
             |> LazyHTML.attribute("href")

    assert URI.parse(href).path == "/missions/mission-1/ops/dashboards/dashboard-1"
    assert URI.decode_query(URI.parse(href).query)["activity_filter"] == "health_snapshots"
  end

  defp evidence_link(target, target_id, label) do
    %{
      link_id: "#{target}:#{target_id}:request-1",
      label: label,
      target_text: target |> Atom.to_string() |> String.replace("_", " "),
      target_id: target_id,
      context: %{
        data: %{
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        time: %{
          mode: "archive",
          axis: "receipt_time"
        }
      }
    }
  end

  defp telemetry_explore_action do
    %DashboardAction{
      action_id: "explore",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{
        "point_id" => "HK.counter",
        "sample_id" => "sample-1",
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "source_binding_id" => "binding-flight"
      },
      source: :frame
    }
  end

  defp source_inventory_action do
    %DashboardAction{
      action_id: "source-inventory",
      label: "Source inventory",
      target: :source_inventory,
      kind: :invoke,
      query: %{
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "source_binding_id" => "binding-flight"
      },
      source: :frame
    }
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
