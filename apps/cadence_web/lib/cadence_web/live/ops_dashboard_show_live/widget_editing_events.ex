defmodule CadenceWeb.OpsDashboardShowLive.WidgetEditingEvents do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.WidgetEditing

  def toggle_edit(socket, opts \\ []) do
    if socket.assigns.edit_mode? do
      exit_edit_mode_fn(opts).(socket, opts)
    else
      enter_edit_mode_fn(opts).(socket, opts)
    end
  end

  def layout_changed(socket, layouts, opts \\ []) when is_list(layouts) do
    layout_changed_fn(opts).(socket, layouts, opts)
  end

  def open_add_widget(socket, opts \\ []) do
    open_add_widget_fn(opts).(socket)
  end

  def open_widget_config(socket, placement_id, opts \\ []) do
    open_widget_config_fn(opts).(socket, placement_id)
  end

  def validate_widget(socket, params, opts \\ []) do
    validate_widget_fn(opts).(socket, params)
  end

  def pick_point(socket, point_id, opts \\ []) do
    pick_point_fn(opts).(socket, point_id)
  end

  def save_widget(socket, params, opts \\ []) do
    save_widget_fn(opts).(socket, params, opts)
  end

  def remove_widget(socket, placement_id, opts \\ []) do
    remove_widget_fn(opts).(socket, placement_id, opts)
  end

  def refresh_widget_data(socket) do
    WidgetEditing.refresh_widget_data(socket)
  end

  defp enter_edit_mode_fn(opts),
    do: Keyword.get(opts, :enter_edit_mode_event, &WidgetEditing.enter_edit_mode/2)

  defp exit_edit_mode_fn(opts),
    do: Keyword.get(opts, :exit_edit_mode_event, &WidgetEditing.exit_edit_mode/2)

  defp layout_changed_fn(opts),
    do: Keyword.get(opts, :layout_changed_event, &WidgetEditing.layout_changed/3)

  defp open_add_widget_fn(opts),
    do: Keyword.get(opts, :open_add_widget_event, &WidgetEditing.open_add_widget/1)

  defp open_widget_config_fn(opts),
    do: Keyword.get(opts, :open_widget_config_event, &WidgetEditing.open_widget_config/2)

  defp validate_widget_fn(opts),
    do: Keyword.get(opts, :validate_widget_event, &WidgetEditing.validate_widget/2)

  defp pick_point_fn(opts),
    do: Keyword.get(opts, :pick_point_event, &WidgetEditing.pick_point/2)

  defp save_widget_fn(opts),
    do: Keyword.get(opts, :save_widget_event, &WidgetEditing.save_widget/3)

  defp remove_widget_fn(opts),
    do: Keyword.get(opts, :remove_widget_event, &WidgetEditing.remove_widget/3)
end
