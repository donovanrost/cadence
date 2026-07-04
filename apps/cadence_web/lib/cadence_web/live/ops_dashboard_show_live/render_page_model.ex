defmodule CadenceWeb.OpsDashboardShowLive.RenderPageModel do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.DashboardPageSummaryModel
  alias CadenceWeb.OpsDashboardShowLive.Navigation
  alias CadenceWeb.OpsDashboardShowLive.RenderGridModel
  alias CadenceWeb.OpsDashboardShowLive.RenderPanelModel
  alias CadenceWeb.OpsDashboardShowLive.RenderRootAttrs
  alias CadenceWeb.OpsDashboardShowLive.RenderSelectionModel
  alias CadenceWeb.OpsDashboardShowLive.RenderShellAssigns
  alias CadenceWeb.OpsDashboardShowLive.RenderSourceModel
  alias CadenceWeb.OpsDashboardShowLive.RenderToolbarModel
  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetModel

  def build(assigns, runtime_diagnostics \\ %{}, runtime_invalidation \\ %{})
      when is_map(assigns) do
    shell_context = RenderShellAssigns.shell_context(assigns)
    current_path = Navigation.show_path(assigns, %{})
    widget_items = RenderWidgetModel.widget_items(assigns)
    source_props = RenderSourceModel.props(assigns)

    summary_props =
      DashboardPageSummaryModel.props(assigns, widget_items, current_path, shell_context)

    root_attrs =
      assigns
      |> RenderRootAttrs.root_attrs(runtime_diagnostics, runtime_invalidation)
      |> Map.merge(summary_props.root_attrs)

    %{
      page_attrs: RenderRootAttrs.page_attrs(root_attrs),
      root_attrs: root_attrs,
      content_attrs: RenderGridModel.content_attrs(),
      grid_props: RenderGridModel.grid_props(assigns),
      current_path: current_path,
      show_context?: shell_context.show_context?,
      toolbar_props: RenderToolbarModel.props(assigns),
      dashboard_warning_props: source_props.dashboard_warning_props,
      dashboard_health: summary_props.dashboard_health,
      source_health_props: source_props.source_health_props,
      source_selection_props: source_props.source_selection_props,
      comparison_rollup: summary_props.comparison_rollup,
      comparison_preset: summary_props.comparison_preset,
      open_review_summary: summary_props.open_review_summary,
      comparison_presets: summary_props.comparison_presets,
      empty_state: RenderGridModel.empty_state(assigns),
      widget_items: widget_items,
      panel_open?: RenderPanelModel.open?(assigns),
      panel_props: RenderPanelModel.props(assigns, runtime_diagnostics, current_path),
      selection: RenderSelectionModel.selection(assigns),
      evidence: RenderSelectionModel.evidence(assigns)
    }
  end
end
