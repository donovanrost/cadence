defmodule CadenceWeb.OpsDashboardShowLive.WidgetEditingEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.WidgetEditingEvents
  alias Phoenix.LiveView.Socket

  test "toggle_edit delegates to enter edit mode when not editing" do
    opts = [
      enter_edit_mode_event: fn socket, opts ->
        assign(socket, :widget_event, {:enter_edit, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = WidgetEditingEvents.toggle_edit(socket(%{edit_mode?: false}), opts)

    assert socket.assigns.widget_event == {:enter_edit, :ok}
  end

  test "toggle_edit delegates to exit edit mode when editing" do
    opts = [
      exit_edit_mode_event: fn socket, opts ->
        assign(socket, :widget_event, {:exit_edit, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = WidgetEditingEvents.toggle_edit(socket(%{edit_mode?: true}), opts)

    assert socket.assigns.widget_event == {:exit_edit, :ok}
  end

  test "layout_changed delegates layouts and opts" do
    opts = [
      layout_changed_event: fn socket, layouts, opts ->
        assign(socket, :widget_event, {:layout_changed, layouts, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = WidgetEditingEvents.layout_changed(socket(), [%{"i" => "layout"}], opts)

    assert socket.assigns.widget_event == {:layout_changed, [%{"i" => "layout"}], :ok}
  end

  test "open_add_widget delegates" do
    socket =
      WidgetEditingEvents.open_add_widget(
        socket(),
        open_add_widget_event: fn socket -> assign(socket, :widget_event, :open_add_widget) end
      )

    assert socket.assigns.widget_event == :open_add_widget
  end

  test "open_widget_config delegates placement id" do
    socket =
      WidgetEditingEvents.open_widget_config(
        socket(),
        "placement-1",
        open_widget_config_event: fn socket, placement_id ->
          assign(socket, :widget_event, {:open_widget_config, placement_id})
        end
      )

    assert socket.assigns.widget_event == {:open_widget_config, "placement-1"}
  end

  test "validate_widget delegates params" do
    socket =
      WidgetEditingEvents.validate_widget(
        socket(),
        %{"type" => "value_tile"},
        validate_widget_event: fn socket, params ->
          assign(socket, :widget_event, {:validate_widget, params})
        end
      )

    assert socket.assigns.widget_event == {:validate_widget, %{"type" => "value_tile"}}
  end

  test "pick_point delegates point id" do
    socket =
      WidgetEditingEvents.pick_point(
        socket(),
        "HK.counter",
        pick_point_event: fn socket, point_id ->
          assign(socket, :widget_event, {:pick_point, point_id})
        end
      )

    assert socket.assigns.widget_event == {:pick_point, "HK.counter"}
  end

  test "save_widget delegates params and opts" do
    opts = [
      save_widget_event: fn socket, params, opts ->
        assign(socket, :widget_event, {:save_widget, params, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = WidgetEditingEvents.save_widget(socket(), %{"title" => "Counter"}, opts)

    assert socket.assigns.widget_event == {:save_widget, %{"title" => "Counter"}, :ok}
  end

  test "remove_widget delegates placement id and opts" do
    opts = [
      remove_widget_event: fn socket, placement_id, opts ->
        assign(
          socket,
          :widget_event,
          {:remove_widget, placement_id, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket = WidgetEditingEvents.remove_widget(socket(), "placement-1", opts)

    assert socket.assigns.widget_event == {:remove_widget, "placement-1", :ok}
  end

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            edit_mode?: false
          },
          assigns
        )
    }
  end
end
