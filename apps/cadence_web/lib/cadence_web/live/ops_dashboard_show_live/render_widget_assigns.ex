defmodule CadenceWeb.OpsDashboardShowLive.RenderWidgetAssigns do
  @moduledoc false

  @spec normalize(Phoenix.LiveView.Socket.t() | map()) :: map()
  def normalize(%{assigns: assigns}) when is_map(assigns), do: assigns
  def normalize(assigns) when is_map(assigns), do: assigns

  @spec widget_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def widget_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)
    edit_mode? = Map.get(assigns, :edit_mode?, false)
    time_context = Map.get(assigns, :dashboard_time_context) || %{}

    %{
      render_items: Map.get(assigns, :dashboard_render_items, []),
      review_focus: review_focus(assigns),
      content_class: widget_content_class(edit_mode?),
      edit_mode?: edit_mode?,
      mission_id:
        mission_id(Map.get(assigns, :current_mission)) ||
          mission_id(Map.get(assigns, :dashboard_document)),
      spacecraft: Map.get(assigns, :spacecraft, []),
      selected_data_ref: Map.get(assigns, :dashboard_selected_data_ref),
      time_mode: Map.get(assigns, :dashboard_time_mode),
      time_axis: Map.get(time_context, "axis"),
      replay_run_id: Map.get(assigns, :dashboard_replay_run_id),
      data_realm: Map.get(assigns, :dashboard_data_realm),
      data_view: Map.get(assigns, :dashboard_data_view),
      compare_data_view: Map.get(assigns, :dashboard_compare_data_view),
      data_source_id: Map.get(assigns, :dashboard_data_source_id),
      source_binding_id: Map.get(assigns, :dashboard_source_binding_id),
      context_spacecraft_id: Map.get(assigns, :context_spacecraft_id),
      chart_epoch: Map.get(assigns, :chart_epoch),
      widget_data_by_placement: map_or_empty(Map.get(assigns, :widget_data)),
      backfills_by_placement: map_or_empty(Map.get(assigns, :backfills)),
      frames_by_placement: map_or_empty(Map.get(assigns, :dashboard_engine_frames_by_placement)),
      compare_frames_by_placement:
        map_or_empty(Map.get(assigns, :dashboard_compare_engine_frames_by_placement)),
      points_by_id: map_or_empty(Map.get(assigns, :points_by_id))
    }
  end

  def widget_content_class(edit_mode?) when is_boolean(edit_mode?) do
    [
      "grid-stack-item-content bg-base-200 border flex flex-col overflow-hidden",
      if(edit_mode?,
        do: "border-primary/40 ring-1 ring-primary/20 cursor-move",
        else: "border-base-300 hover:border-primary/60"
      )
    ]
  end

  def widget_content_class(socket_or_assigns) do
    socket_or_assigns
    |> normalize()
    |> Map.get(:edit_mode?, false)
    |> widget_content_class()
  end

  def context_widgets?(render_items) when is_list(render_items) do
    Enum.any?(render_items, &context_widget?/1)
  end

  def context_widgets?(_render_items), do: false

  defp context_widget?(%{widget: %{binding: %{mode: :context}}}), do: true
  defp context_widget?(_item), do: false

  defp review_focus(%{dashboard_activity_filter: :open_comparison_reviews} = assigns) do
    summary = Map.get(assigns, :dashboard_comparison_review_queue, %{})

    %{
      mode: :open_comparison_reviews,
      placement_ids: list_value(summary, :placement_ids),
      request_ids: list_value(summary, :request_ids),
      selected_placement_id: Map.get(assigns, :dashboard_review_placement_id)
    }
  end

  defp review_focus(_assigns), do: nil

  defp list_value(map, key) when is_map(map) do
    case Map.get(map, key, Map.get(map, Atom.to_string(key), [])) do
      value when is_list(value) -> value
      _other -> []
    end
  end

  defp list_value(_map, _key), do: []

  defp mission_id(%{mission_id: mission_id}) when is_binary(mission_id), do: mission_id
  defp mission_id(%{"mission_id" => mission_id}) when is_binary(mission_id), do: mission_id
  defp mission_id(_mission), do: nil

  defp map_or_empty(value) when is_map(value), do: value
  defp map_or_empty(_value), do: %{}
end
