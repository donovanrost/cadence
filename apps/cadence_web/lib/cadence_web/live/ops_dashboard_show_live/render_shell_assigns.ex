defmodule CadenceWeb.OpsDashboardShowLive.RenderShellAssigns do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetAssigns

  @spec normalize(Phoenix.LiveView.Socket.t() | map()) :: map()
  def normalize(%{assigns: assigns}) when is_map(assigns), do: assigns
  def normalize(assigns) when is_map(assigns), do: assigns

  @spec shell_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def shell_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)
    render_items = Map.get(assigns, :dashboard_render_items, [])
    edit_mode? = Map.get(assigns, :edit_mode?, false)

    %{
      dashboard_id: dashboard_id(Map.get(assigns, :dashboard_document)),
      render_items: render_items,
      render_items_empty?: render_items == [],
      edit_mode?: edit_mode?,
      edit_mode_text: to_string(edit_mode?),
      panel: Map.get(assigns, :panel),
      panel_open?: not is_nil(Map.get(assigns, :panel)),
      show_context?: RenderWidgetAssigns.context_widgets?(render_items)
    }
  end

  defp dashboard_id(document) when is_map(document) do
    Map.get(document, :dashboard_id, Map.get(document, "dashboard_id"))
  end

  defp dashboard_id(_document), do: nil
end
