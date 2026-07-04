defmodule CadenceWeb.OpsDashboardShowLive.DashboardHealthRollupTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DashboardHealthRollup

  test "rollup prioritizes blocked, stale, degraded, and ready widget health" do
    rollup =
      DashboardHealthRollup.rollup([
        widget_item("ready-placement", "Ready", :ready, :fresh),
        widget_item("degraded-placement", "No Data", :no_data, :no_data),
        widget_item("stale-placement", "Stale", :ready, :stale),
        widget_item("blocked-placement", "Blocked", :ready, :unavailable)
      ])

    assert rollup.state == :blocked
    assert rollup.state_text == "blocked"
    assert rollup.label == "Blocked"
    assert rollup.severity == :error
    assert rollup.widget_count == 4
    assert rollup.ready_count == 1
    assert rollup.degraded_count == 1
    assert rollup.stale_count == 1
    assert rollup.blocked_count == 1
    assert rollup.affected_count == 3
    assert rollup.affected_placements == "degraded-placement,stale-placement,blocked-placement"
    assert rollup.blocked_placements == "blocked-placement"
    assert rollup.stale_placements == "stale-placement"
    assert rollup.degraded_placements == "degraded-placement"

    assert Enum.map(rollup.groups, & &1.key) == ["blocked", "stale", "degraded", "ready"]
  end

  test "rollup classifies queryable degraded source health as degraded" do
    rollup =
      [widget_item("source-degraded-placement", "Source Degraded", :ready, :degraded)]
      |> DashboardHealthRollup.rollup()

    assert rollup.state == :degraded
    assert rollup.degraded_count == 1
    assert rollup.degraded_placements == "source-degraded-placement"
    assert [%{key: "degraded", items: [%{reason: "source_degraded"}]}] = rollup.groups
  end

  test "root attrs expose dashboard health summary" do
    rollup =
      [widget_item("blocked-placement", "Blocked", :ready, :retention_gap)]
      |> DashboardHealthRollup.rollup()
      |> DashboardHealthRollup.with_snapshot(%{})

    attrs = DashboardHealthRollup.root_attrs(rollup)

    assert attrs["data-dashboard-health-snapshot-schema"] == "dashboard_health_snapshot.v1"
    assert attrs["data-dashboard-health-snapshot-id"] == rollup.snapshot_id
    assert String.starts_with?(rollup.snapshot_id, "dashboard_health_snapshot_")
    assert attrs["data-dashboard-health-state"] == "blocked"
    assert attrs["data-dashboard-health-severity"] == "error"
    assert attrs["data-dashboard-health-widgets"] == 1
    assert attrs["data-dashboard-health-blocked"] == 1
    assert attrs["data-dashboard-health-blocked-placements"] == "blocked-placement"
  end

  test "snapshot builds event-ready dashboard health payload" do
    snapshot =
      [
        widget_item("ready-placement", "Ready", :ready, :fresh),
        widget_item("blocked-placement", "Blocked", :ready, :unavailable)
      ]
      |> DashboardHealthRollup.rollup()
      |> DashboardHealthRollup.snapshot(%{
        organization_id: "org-1",
        mission_id: "mission-1",
        dashboard_id: "dashboard-1",
        realm: :flight,
        data_view: "canonical",
        time_mode: "live",
        scope_kind: "contact",
        scope_id: "contact-1",
        source_binding_id: "binding-flight",
        limit_mode: "observed"
      })

    assert snapshot["schema"] == "dashboard_health_snapshot.v1"
    assert String.starts_with?(snapshot["snapshot_id"], "dashboard_health_snapshot_")
    assert snapshot["organization_id"] == "org-1"
    assert snapshot["mission_id"] == "mission-1"
    assert snapshot["dashboard_id"] == "dashboard-1"
    assert snapshot["state"] == "blocked"
    assert snapshot["severity"] == "error"

    assert snapshot["runtime_context"] == %{
             "realm" => "flight",
             "data_view" => "canonical",
             "time_mode" => "live",
             "scope_kind" => "contact",
             "scope_id" => "contact-1",
             "source_binding_id" => "binding-flight",
             "limit_mode" => "observed"
           }

    assert snapshot["counts"] == %{
             "widgets" => 2,
             "ready" => 1,
             "degraded" => 0,
             "stale" => 0,
             "blocked" => 1,
             "affected" => 1
           }

    assert snapshot["placement_ids"] == %{
             "affected" => ["blocked-placement"],
             "blocked" => ["blocked-placement"],
             "stale" => [],
             "degraded" => []
           }

    assert [
             %{"placement_id" => "ready-placement", "state" => "ready"},
             %{
               "placement_id" => "blocked-placement",
               "state" => "blocked",
               "source_state" => "unavailable",
               "reason" => "source_unavailable"
             }
           ] = snapshot["items"]
  end

  test "snapshot id is deterministic for canonical payload content" do
    snapshot =
      [widget_item("blocked-placement", "Blocked", :ready, :unavailable)]
      |> DashboardHealthRollup.rollup()
      |> DashboardHealthRollup.snapshot(%{
        organization_id: "org-1",
        mission_id: "mission-1",
        dashboard_id: "dashboard-1",
        time_mode: "live"
      })

    same_snapshot =
      [widget_item("blocked-placement", "Blocked", :ready, :unavailable)]
      |> DashboardHealthRollup.rollup()
      |> DashboardHealthRollup.snapshot(%{
        dashboard_id: "dashboard-1",
        mission_id: "mission-1",
        organization_id: "org-1",
        time_mode: "live"
      })

    changed_snapshot =
      [widget_item("blocked-placement", "Blocked", :ready, :unavailable)]
      |> DashboardHealthRollup.rollup()
      |> DashboardHealthRollup.snapshot(%{
        organization_id: "org-1",
        mission_id: "mission-1",
        dashboard_id: "dashboard-1",
        time_mode: "archive"
      })

    assert snapshot["snapshot_id"] == same_snapshot["snapshot_id"]
    assert snapshot["snapshot_id"] == DashboardHealthRollup.snapshot_id(snapshot)
    refute snapshot["snapshot_id"] == changed_snapshot["snapshot_id"]
  end

  defp widget_item(placement_id, title, lifecycle_state, source_state) do
    %{
      item: %{
        placement_id: placement_id,
        widget: %{widget_id: placement_id, title: title}
      },
      props: %{
        data: %{
          lifecycle_state: lifecycle_state,
          source_status: %{state: source_state}
        },
        warnings: []
      }
    }
  end
end
