defmodule CadenceWeb.OpsDashboardShowLive.RuntimeControlEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeControlEvents
  alias Phoenix.LiveView.Socket

  test "context_search delegates query" do
    socket =
      RuntimeControlEvents.context_search(socket(), "comm",
        context_search_event: fn socket, query ->
          assign(socket, :runtime_control_event, {:context_search, query})
        end
      )

    assert socket.assigns.runtime_control_event == {:context_search, "comm"}
  end

  test "set_context delegates spacecraft id and opts" do
    opts = [
      set_context_event: fn socket, spacecraft_id, opts ->
        assign(
          socket,
          :runtime_control_event,
          {:set_context, spacecraft_id, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket = RuntimeControlEvents.set_context(socket(), "spacecraft-1", opts)

    assert socket.assigns.runtime_control_event == {:set_context, "spacecraft-1", :ok}
  end

  test "set_context delegates generic scope params" do
    opts = [
      set_context_event: fn socket, context, opts ->
        assign(
          socket,
          :runtime_control_event,
          {:set_context, context, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    context = %{"scope_kind" => "mission", "scope_id" => "mission-1"}
    socket = RuntimeControlEvents.set_context(socket(), context, opts)

    assert socket.assigns.runtime_control_event == {:set_context, context, :ok}
  end

  test "clear_context delegates opts" do
    opts = [
      clear_context_event: fn socket, opts ->
        assign(socket, :runtime_control_event, {:clear_context, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = RuntimeControlEvents.clear_context(socket(), opts)

    assert socket.assigns.runtime_control_event == {:clear_context, :ok}
  end

  test "set_runtime_context delegates params and opts" do
    opts = [
      set_runtime_context_event: fn socket, params, opts ->
        assign(
          socket,
          :runtime_control_event,
          {:set_runtime_context, params, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    params = %{"realm" => "rehearsal"}
    socket = RuntimeControlEvents.set_runtime_context(socket(), params, opts)

    assert socket.assigns.runtime_control_event == {:set_runtime_context, params, :ok}
  end

  test "resume_live delegates opts" do
    opts = [
      resume_live_event: fn socket, opts ->
        assign(socket, :runtime_control_event, {:resume_live, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = RuntimeControlEvents.resume_live(socket(), opts)

    assert socket.assigns.runtime_control_event == {:resume_live, :ok}
  end

  test "set_time_preset delegates preset and opts" do
    opts = [
      set_time_preset_event: fn socket, preset, opts ->
        assign(
          socket,
          :runtime_control_event,
          {:set_time_preset, preset, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket = RuntimeControlEvents.set_time_preset(socket(), "last_5m", opts)

    assert socket.assigns.runtime_control_event == {:set_time_preset, "last_5m", :ok}
  end

  test "pause_at_selected_time delegates opts" do
    opts = [
      pause_at_selected_time_event: fn socket, opts ->
        assign(
          socket,
          :runtime_control_event,
          {:pause_at_selected_time, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket = RuntimeControlEvents.pause_at_selected_time(socket(), opts)

    assert socket.assigns.runtime_control_event == {:pause_at_selected_time, :ok}
  end

  test "scrub_replay_to_selection delegates opts" do
    opts = [
      scrub_replay_to_selection_event: fn socket, opts ->
        assign(
          socket,
          :runtime_control_event,
          {:scrub_replay_to_selection, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket = RuntimeControlEvents.scrub_replay_to_selection(socket(), opts)

    assert socket.assigns.runtime_control_event == {:scrub_replay_to_selection, :ok}
  end

  test "clear_data_selection delegates opts" do
    opts = [
      clear_data_selection_event: fn socket, opts ->
        assign(
          socket,
          :runtime_control_event,
          {:clear_data_selection, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket = RuntimeControlEvents.clear_data_selection(socket(), opts)

    assert socket.assigns.runtime_control_event == {:clear_data_selection, :ok}
  end

  defp socket do
    %Socket{assigns: %{__changed__: %{}}}
  end
end
