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
    widget_groups = RenderGridModel.widget_groups(assigns, widget_items)
    source_props = RenderSourceModel.props(assigns)

    summary_props =
      DashboardPageSummaryModel.props(assigns, widget_items, current_path, shell_context)

    comparison_available? =
      summary_props.comparison_rollup.visible? == true or summary_props.comparison_presets != []

    comparison_inspector_open? =
      comparison_available? and not Map.get(assigns, :edit_mode?, false) and
        Map.get(assigns, :comparison_inspector_open?, false)

    toolbar_props =
      assigns
      |> RenderToolbarModel.props()
      |> Map.merge(%{
        comparison_available?: comparison_available?,
        comparison_open?: comparison_inspector_open?,
        comparison_open_count: Map.get(summary_props.comparison_rollup, :open_count, 0)
      })

    root_attrs =
      assigns
      |> RenderRootAttrs.root_attrs(runtime_diagnostics, runtime_invalidation)
      |> Map.merge(summary_props.root_attrs)
      |> Map.merge(editor_root_attrs(assigns))

    %{
      page_attrs: RenderRootAttrs.page_attrs(root_attrs),
      root_attrs: root_attrs,
      content_attrs: RenderGridModel.content_attrs(),
      grid_props: RenderGridModel.grid_props(assigns),
      current_path: current_path,
      show_context?: shell_context.show_context?,
      toolbar_props: toolbar_props,
      dashboard_warning_props: source_props.dashboard_warning_props,
      dashboard_health: summary_props.dashboard_health,
      source_health_props: source_props.source_health_props,
      source_selection_props: source_props.source_selection_props,
      comparison_rollup: summary_props.comparison_rollup,
      comparison_preset: summary_props.comparison_preset,
      open_review_summary: summary_props.open_review_summary,
      comparison_presets: summary_props.comparison_presets,
      comparison_inspector_open?: comparison_inspector_open?,
      empty_state: RenderGridModel.empty_state(assigns),
      widget_items: widget_items,
      widget_groups: widget_groups,
      panel_open?: RenderPanelModel.open?(assigns),
      panel_props: RenderPanelModel.props(assigns, runtime_diagnostics, current_path),
      selection: RenderSelectionModel.selection(assigns),
      evidence: RenderSelectionModel.evidence(assigns)
    }
  end

  defp editor_root_attrs(%{editor_route?: true} = assigns) do
    %{
      "phx-hook" => "DashboardEditorGuard",
      "data-dashboard-editor" => "true",
      "data-editor-dirty" => to_string(Map.get(assigns, :editor_dirty?, false)),
      "data-editor-conflict" => to_string(not is_nil(Map.get(assigns, :editor_conflict)))
    }
  end

  defp editor_root_attrs(_assigns), do: %{"data-dashboard-editor" => "false"}
end
