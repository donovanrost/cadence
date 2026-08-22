defmodule CadenceWeb.OpsDashboardShowLive.RenderSourceAssignsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RenderSourceAssigns
  alias Phoenix.LiveView.Socket

  test "projects dashboard warning context from sockets and assigns maps" do
    assigns = %{dashboard_engine_result: %{plan_metadata: %{degraded?: true}}}

    expected = %{
      warnings: [],
      degraded?: true
    }

    assert RenderSourceAssigns.dashboard_warning_context(%Socket{assigns: assigns}) == expected
    assert RenderSourceAssigns.dashboard_warning_context(assigns) == expected
  end

  test "projects source health context and empty defaults" do
    assert RenderSourceAssigns.source_health_context(%{dashboard_engine_result: nil}) == %{
             health: []
           }

    assert RenderSourceAssigns.dashboard_warning_context(%{assigns: %{}}) == %{
             warnings: [],
             degraded?: false
           }

    assert RenderSourceAssigns.source_health_context(%{assigns: %{}}) == %{health: []}
  end

  test "source context prefers assigned source summaries over engine-derived values" do
    assigns = %{
      dashboard_engine_result: %{plan_metadata: %{degraded?: true}},
      dashboard_warning_summaries: [%{code: :assigned_warning}],
      dashboard_degraded?: false,
      dashboard_source_health_summaries: [%{state: :assigned_health}],
      dashboard_source_selection_summaries: [%{request_id: "assigned-request"}]
    }

    assert RenderSourceAssigns.source_context(assigns) == %{
             dashboard_warnings: [%{code: :assigned_warning}],
             dashboard_degraded?: false,
             source_health: [%{state: :assigned_health}],
             source_selections: [%{request_id: "assigned-request"}]
           }
  end
end
