defmodule CadenceWeb.OpsDashboardShowLive.RenderWidgetModel do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.MarkerCategories
  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetAssigns
  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef
  alias CadenceWeb.OpsDashboardShowLive.SourcePresentation
  alias CadenceWeb.OpsDashboardShowLive.WidgetComparisonSummary
  alias CadenceWeb.OpsDashboardShowLive.WidgetLifecycleAttrs
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  def selected_data_ref_for_placement(selected_ref, placement_id) do
    SelectedDataRef.for_placement(selected_ref, placement_id)
  end

  def widget_items(assigns) when is_map(assigns) do
    context = RenderWidgetAssigns.widget_context(assigns)

    context.render_items
    |> Enum.map(fn item ->
      props = widget_props_from_context(context, item)

      %{
        item: item,
        shell_attrs: widget_shell_attrs(item, props),
        content_class: context.content_class,
        props: props,
        component_props: widget_component_props_from_context(context, item, props)
      }
    end)
  end

  def widget_shell_attrs(item, props \\ %{})

  def widget_shell_attrs(%{placement_id: placement_id, layout: layout} = item, props) do
    %{
      id: "widget-#{placement_id}",
      class: "grid-stack-item",
      "gs-id": placement_id,
      "gs-x": layout.x,
      "gs-y": layout.y,
      "gs-w": layout.w,
      "gs-h": layout.h,
      "gs-auto-position": if(is_nil(layout.x), do: "true"),
      "data-dashboard-widget-type": widget_type(item)
    }
    |> Map.merge(WidgetLifecycleAttrs.attrs(Map.get(props, :data), Map.get(props, :warnings, [])))
    |> Map.merge(review_focus_attrs(placement_id, props))
  end

  def widget_content_class(assigns) when is_map(assigns) do
    RenderWidgetAssigns.widget_content_class(assigns)
  end

  def widget_component_props(assigns, %{placement_id: placement_id, widget: widget}, props)
      when is_map(assigns) and is_map(props) do
    context = RenderWidgetAssigns.widget_context(assigns)

    widget_component_props_from_context(
      context,
      %{placement_id: placement_id, widget: widget},
      props
    )
  end

  def widget_props(assigns, %{placement_id: placement_id, widget: widget}) when is_map(assigns) do
    assigns
    |> RenderWidgetAssigns.widget_context()
    |> widget_props_from_context(%{placement_id: placement_id, widget: widget})
  end

  defp widget_component_props_from_context(
         context,
         %{placement_id: placement_id, widget: widget},
         props
       )
       when is_map(context) and is_map(props) do
    %{
      widget: widget,
      placement_id: placement_id,
      mission_id: context.mission_id,
      data: props.data,
      compare_data: props.compare_data,
      point: props.point,
      spacecraft: context.spacecraft,
      backfill: props.backfill,
      compare_backfill: props.compare_backfill,
      limit_markers: props.limit_markers,
      event_markers: props.event_markers,
      annotations: props.annotations,
      selected_data_ref: props.selected_data_ref,
      time_mode: context.time_mode,
      time_from: context.time_from,
      time_to: context.time_to,
      time_axis: context.time_axis,
      window_seconds: context.window_seconds,
      replay_run_id: context.replay_run_id,
      data_realm: context.data_realm,
      data_view: context.data_view,
      compare_data_view: context.compare_data_view,
      data_source_id: context.data_source_id,
      source_binding_id: context.source_binding_id,
      comparison_summary: props.comparison_summary,
      context_spacecraft_id: props.context_spacecraft_id,
      chart_epoch: props.chart_epoch,
      edit_mode?: props.edit_mode,
      warnings: props.warnings
    }
  end

  defp widget_props_from_context(context, %{placement_id: placement_id, widget: widget})
       when is_map(context) do
    placement_frames = placement_value(context.frames_by_placement, placement_id)
    compare_placement_frames = placement_value(context.compare_frames_by_placement, placement_id)

    props = %{
      data:
        WidgetPresentation.data(
          placement_value(context.widget_data_by_placement, placement_id),
          placement_frames,
          widget
        ),
      compare_data: WidgetPresentation.data(nil, compare_placement_frames, widget),
      point: point_for_widget(context, widget),
      backfill:
        WidgetPresentation.backfill(
          placement_value(context.backfills_by_placement, placement_id),
          placement_frames,
          widget
        ),
      compare_backfill: WidgetPresentation.compare_backfill(compare_placement_frames, widget),
      limit_markers:
        placement_frames
        |> WidgetPresentation.limit_markers(widget)
        |> MarkerCategories.filter_limit_markers(context.hidden_marker_categories),
      event_markers:
        placement_frames
        |> WidgetPresentation.event_markers(widget)
        |> MarkerCategories.filter_event_markers(context.hidden_marker_categories),
      annotations: WidgetPresentation.annotations(placement_frames, widget),
      selected_data_ref: selected_data_ref_for_placement(context.selected_data_ref, placement_id),
      context_spacecraft_id: context.context_spacecraft_id,
      chart_epoch: context.chart_epoch,
      edit_mode: context.edit_mode?,
      warnings: SourcePresentation.placement_warning_summaries(placement_frames),
      review_focus: review_focus_for_placement(context.review_focus, placement_id)
    }

    Map.put(
      props,
      :comparison_summary,
      WidgetComparisonSummary.summary(
        Map.merge(props, %{
          widget: widget,
          data_view: context.data_view,
          compare_data_view: context.compare_data_view
        })
      )
    )
  end

  defp placement_value(values, placement_id) when is_map(values) do
    Map.get(values, placement_id)
  end

  defp review_focus_attrs(placement_id, %{review_focus: %{mode: mode} = focus}) do
    %{
      :class => review_focus_class(placement_id, focus),
      "data-dashboard-review-placement-focus" => Atom.to_string(mode),
      "data-dashboard-review-placement-id" => placement_id,
      "data-dashboard-review-request-ids" => Enum.join(focus.request_ids, ","),
      "data-dashboard-review-placement-selected" =>
        if(focus.selected_placement_id == placement_id, do: "true", else: "false")
    }
  end

  defp review_focus_attrs(_placement_id, _props), do: %{}

  defp review_focus_class(placement_id, %{selected_placement_id: placement_id}) do
    "grid-stack-item dashboard-review-placement-focus dashboard-review-placement-selected"
  end

  defp review_focus_class(_placement_id, _focus) do
    "grid-stack-item dashboard-review-placement-focus"
  end

  defp review_focus_for_placement(%{placement_ids: placement_ids} = focus, placement_id)
       when is_list(placement_ids) do
    if placement_id in placement_ids do
      focus
    end
  end

  defp review_focus_for_placement(_focus, _placement_id), do: nil

  defp point_for_widget(context, widget) do
    point_id = get_in(widget.binding, [:point_id])
    Map.get(context.points_by_id, point_id)
  end

  defp widget_type(%{widget: %{type: type}}) when is_atom(type), do: Atom.to_string(type)
  defp widget_type(%{widget: %{type: type}}) when is_binary(type), do: type
  defp widget_type(_item), do: ""
end
