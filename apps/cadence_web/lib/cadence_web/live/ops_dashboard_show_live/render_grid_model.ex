defmodule CadenceWeb.OpsDashboardShowLive.RenderGridModel do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RenderShellAssigns

  def content_attrs do
    %{class: "flex-1 min-w-0 min-h-0 overflow-y-auto"}
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

  def grid_props(assigns, group_id) when is_map(assigns) and is_binary(group_id) do
    assigns
    |> grid_props()
    |> Map.put(:id, "dashboard-grid-#{dashboard_id(assigns)}-#{group_id}")
  end

  def widget_groups(assigns, widget_items) when is_map(assigns) and is_list(widget_items) do
    document = Map.get(assigns, :dashboard_document)
    sections = if is_map(document), do: Map.get(document, :sections, []), else: []
    edit_mode? = Map.get(assigns, :edit_mode?, false)

    if sections == [] do
      [
        %{
          id: "unsectioned",
          section: nil,
          widget_items: widget_items,
          grid_props: grid_props(assigns),
          open?: true,
          show_header?: false
        }
      ]
    else
      unsectioned = Enum.filter(widget_items, &(widget_section_id(&1) in [nil, ""]))

      unsectioned_groups =
        if unsectioned != [] or edit_mode? do
          [
            %{
              id: "unsectioned",
              section: nil,
              widget_items: unsectioned,
              grid_props: grid_props(assigns, "unsectioned"),
              open?: true,
              show_header?: true
            }
          ]
        else
          []
        end

      section_groups =
        sections
        |> Enum.map(fn section ->
          items = Enum.filter(widget_items, &(widget_section_id(&1) == section.section_id))

          %{
            id: section.section_id,
            section: section,
            widget_items: items,
            grid_props: grid_props(assigns, section.section_id),
            open?: edit_mode? or not section.collapsed_by_default?,
            show_header?: true
          }
        end)
        |> Enum.filter(&(&1.widget_items != [] or edit_mode?))

      unsectioned_groups ++ section_groups
    end
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

  defp widget_section_id(%{item: %{placement: placement}}) when is_map(placement),
    do: Map.get(placement, :section_id, Map.get(placement, "section_id"))

  defp widget_section_id(_widget_item), do: nil

  defp dashboard_id(%{dashboard_document: document}) when is_map(document),
    do: Map.get(document, :dashboard_id, Map.get(document, "dashboard_id"))

  defp dashboard_id(_assigns), do: "dashboard"
end
