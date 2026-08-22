defmodule CadenceWeb.OpsDashboardShowLive.DashboardHealthComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.DashboardHealthComponents

  test "dashboard health strip summarizes affected widget groups and evidence" do
    snapshot_id = "dashboard_health_snapshot_abc123"

    html =
      render_component(&DashboardHealthComponents.dashboard_health_strip/1,
        health: dashboard_health(snapshot_id)
      )

    document = LazyHTML.from_fragment(html)

    assert ["blocked"] =
             document
             |> LazyHTML.query("#dashboard-health-rollup")
             |> LazyHTML.attribute("data-dashboard-health-state")

    assert [^snapshot_id] =
             document
             |> LazyHTML.query("#dashboard-health-rollup")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-health-rollup")
             |> LazyHTML.attribute("data-dashboard-health-affected")

    assert ["blocked-placement"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-group="blocked"]))
             |> LazyHTML.attribute("data-dashboard-health-group-placements")

    assert ["#widget-blocked-placement"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-item="blocked-placement"]))
             |> LazyHTML.attribute("href")

    assert ["source_unavailable"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-item="blocked-placement"]))
             |> LazyHTML.attribute("data-dashboard-health-item-reason")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-click")

    assert ["dashboard_health"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-kind")

    assert ["dashboard_health_snapshot.v1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-dashboard-health-schema")

    assert [^snapshot_id] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-dashboard-health-snapshot-id")

    assert ["blocked"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-dashboard-health-state")

    assert ["blocked-placement,degraded-placement"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-dashboard-health-affected-placements")

    assert ["ClipboardButton"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-copy]))
             |> LazyHTML.attribute("phx-hook")

    assert ["dashboard_health_snapshot.v1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-copy]))
             |> LazyHTML.attribute("data-dashboard-health-snapshot-schema")

    assert [^snapshot_id] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-copy]))
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert [snapshot_json] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-copy]))
             |> LazyHTML.attribute("data-clipboard-text")

    assert Jason.decode!(snapshot_json) == dashboard_health_snapshot(snapshot_id)

    assert ["capture_dashboard_health_snapshot"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-capture]))
             |> LazyHTML.attribute("phx-click")

    assert [^snapshot_id] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-capture]))
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert [capture_snapshot_json] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-capture]))
             |> LazyHTML.attribute("phx-value-snapshot")

    assert Jason.decode!(capture_snapshot_json) == Jason.decode!(snapshot_json)
  end

  defp dashboard_health(snapshot_id) do
    %{
      visible?: true,
      snapshot_schema: "dashboard_health_snapshot.v1",
      snapshot_id: snapshot_id,
      snapshot: dashboard_health_snapshot(snapshot_id),
      state: :blocked,
      state_text: "blocked",
      label: "Blocked",
      severity: :error,
      severity_text: "error",
      widget_count: 3,
      ready_count: 1,
      degraded_count: 1,
      stale_count: 0,
      blocked_count: 1,
      affected_count: 2,
      states: "ready,degraded,blocked",
      affected_placements: "blocked-placement,degraded-placement",
      blocked_placements: "blocked-placement",
      stale_placements: "",
      degraded_placements: "degraded-placement",
      groups: [
        %{
          key: "blocked",
          state: :blocked,
          label: "Blocked",
          count: 1,
          placement_ids: "blocked-placement",
          items: [
            %{
              placement_id: "blocked-placement",
              title: "Blocked widget",
              state_text: "blocked",
              lifecycle_state_text: "ready",
              source_state_text: "unavailable",
              warning_codes_text: "",
              reason: "source_unavailable"
            }
          ]
        },
        %{
          key: "degraded",
          state: :degraded,
          label: "Degraded",
          count: 1,
          placement_ids: "degraded-placement",
          items: [
            %{
              placement_id: "degraded-placement",
              title: "No data widget",
              state_text: "degraded",
              lifecycle_state_text: "no_data",
              source_state_text: "no_data",
              warning_codes_text: "",
              reason: "lifecycle_no_data"
            }
          ]
        }
      ]
    }
  end

  defp dashboard_health_snapshot(snapshot_id) do
    %{
      "schema" => "dashboard_health_snapshot.v1",
      "snapshot_id" => snapshot_id,
      "dashboard_id" => "dashboard-1",
      "state" => "blocked",
      "counts" => %{
        "widgets" => 3,
        "ready" => 1,
        "degraded" => 1,
        "stale" => 0,
        "blocked" => 1,
        "affected" => 2
      },
      "placement_ids" => %{
        "affected" => ["blocked-placement", "degraded-placement"],
        "blocked" => ["blocked-placement"],
        "stale" => [],
        "degraded" => ["degraded-placement"]
      }
    }
  end
end
