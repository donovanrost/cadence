defmodule CadenceWeb.OpsDashboardShowLive.LiveDepsTest do
  use ExUnit.Case, async: true

  @moduletag :config

  alias CadenceWeb.OpsDashboardShowLive.LiveDeps
  alias Phoenix.LiveView.Socket

  test "dashboard_list_path returns the mission-scoped dashboard list route" do
    assert LiveDeps.dashboard_list_path(socket()) == "/missions/mission-1/ops/dashboards"
  end

  test "mount flow opts include route and runtime shell dependencies" do
    opts = LiveDeps.mount_flow_opts()

    assert opts[:dashboard_list_path].(socket()) == "/missions/mission-1/ops/dashboards"
    assert opts[:runtime_shell_opts] == [selection_hydration_opts: []]
  end

  test "runtime context opts expose scoped resource validation" do
    runtime_control_opts = LiveDeps.runtime_control_opts()
    route_hydration_opts = LiveDeps.route_hydration_opts()

    assert is_function(runtime_control_opts[:valid_contact?], 3)
    assert is_function(route_hydration_opts[:valid_contact?], 3)
    assert is_function(runtime_control_opts[:valid_operational_resource_scope?], 4)
    assert is_function(route_hydration_opts[:valid_operational_resource_scope?], 4)
  end

  test "late-data policy opts can be configured for test harnesses" do
    previous = Application.get_env(:cadence_web, :ops_dashboard_show_live, [])

    Application.put_env(:cadence_web, :ops_dashboard_show_live,
      late_data_policy_event_opts: [dashboard_runtime_invalidation?: false]
    )

    try do
      assert LiveDeps.late_data_policy_event_opts() == [
               dashboard_runtime_invalidation?: false
             ]
    after
      Application.put_env(:cadence_web, :ops_dashboard_show_live, previous)
    end
  end

  test "widget editing opts expose document and runtime callbacks" do
    opts = LiveDeps.widget_editing_event_opts()

    assert opts[:dashboard_list_path].(socket()) == "/missions/mission-1/ops/dashboards"
    assert is_function(opts[:persist_document], 3)
    assert is_function(opts[:refresh_widget_data], 1)
    assert is_function(opts[:assign_runtime_context], 2)
  end

  test "document lifecycle opts expose dashboard list path" do
    assert LiveDeps.lifecycle_event_opts()[:dashboard_list_path].(socket()) ==
             "/missions/mission-1/ops/dashboards"

    assert is_function(LiveDeps.rename_flow_opts()[:persist_document], 3)
  end

  defp socket do
    %Socket{assigns: %{__changed__: %{}, current_mission: %{mission_id: "mission-1"}}}
  end
end
