defmodule CadenceWeb.OpsDashboardShowLive.RenderGridModel do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RenderShellAssigns

  def content_attrs do
    %{class: "flex-1 min-h-0 overflow-y-auto"}
  end

  def grid_props(assigns) when is_map(assigns) do
    context = RenderShellAssigns.shell_context(assigns)

    %{
      id: "dashboard-grid-#{context.dashboard_id}",
      "phx-hook": "DashboardGrid",
      "data-edit-mode": context.edit_mode_text,
      class: "grid-stack gs-12"
    }
  end

  def empty_state(assigns) when is_map(assigns) do
    context = RenderShellAssigns.shell_context(assigns)

    %{
      visible?: context.render_items_empty?,
      wrapper_class: "p-8",
      card_class:
        "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
      icon_class: "hero-squares-plus mx-auto h-10 w-10 text-base-content/30 block",
      title: "No widgets",
      message: "Add point-bound widgets, then arrange them in Edit Layout.",
      action_event: "open_add_widget",
      action_icon: "hero-plus",
      action_label: "Add widget"
    }
  end
end
