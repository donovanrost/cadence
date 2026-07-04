defmodule CadenceWeb.OpsDashboardShowLive.RuntimeShellTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeShell
  alias Phoenix.LiveView.Socket

  test "activate subscribes and schedules a tick when connected" do
    test_pid = self()

    socket =
      RuntimeShell.activate(
        socket(%{dashboard_live_refresh_ms: 250}),
        %{organization_id: "org-1"},
        %{mission_id: "mission-1"},
        %{dashboard_id: "dashboard-1"},
        true,
        subscribe_runtime_invalidations: fn scope, mission, document ->
          send(test_pid, {:subscribed, scope, mission, document})
        end,
        send_after: fn pid, message, delay ->
          send(test_pid, {:scheduled, pid, message, delay})
          :timer_ref
        end
      )

    assert socket.assigns.dashboard_tick_timer_ref == :timer_ref

    assert_received {:subscribed, %{organization_id: "org-1"}, %{mission_id: "mission-1"},
                     %{dashboard_id: "dashboard-1"}}

    assert_received {:scheduled, _pid, :tick, 250}
  end

  test "activate does nothing before the LiveView is connected" do
    socket =
      RuntimeShell.activate(
        socket(),
        %{organization_id: "org-1"},
        %{mission_id: "mission-1"},
        %{dashboard_id: "dashboard-1"},
        false,
        subscribe_runtime_invalidations: fn _scope, _mission, _document ->
          raise "should not subscribe"
        end,
        send_after: fn _pid, _message, _delay -> raise "should not schedule" end
      )

    assert socket.assigns.dashboard_tick_timer_ref == nil
  end

  test "handle_tick cancels any existing timer, schedules the next tick, and refreshes" do
    test_pid = self()
    old_timer_ref = make_ref()

    socket =
      RuntimeShell.handle_tick(
        socket(%{dashboard_tick_timer_ref: old_timer_ref, dashboard_live_refresh_ms: nil}),
        tick_ms: 500,
        cancel_timer: fn timer_ref ->
          send(test_pid, {:canceled, timer_ref})
          :ok
        end,
        send_after: fn pid, message, delay ->
          send(test_pid, {:scheduled, pid, message, delay})
          :next_timer_ref
        end,
        handle_live_refresh: fn socket, opts ->
          assign(socket, :refreshed_with_tick_ms, Keyword.fetch!(opts, :tick_ms))
        end
      )

    assert socket.assigns.dashboard_tick_timer_ref == :next_timer_ref
    assert socket.assigns.refreshed_with_tick_ms == 500
    assert_received {:canceled, ^old_timer_ref}
    assert_received {:scheduled, _pid, :tick, 500}
  end

  test "handle_tick in edit mode re-arms the timer without touching assigns" do
    test_pid = self()
    old_timer_ref = make_ref()

    original =
      socket(%{
        edit_mode?: true,
        dashboard_tick_timer_ref: old_timer_ref,
        dashboard_live_refresh_ms: nil
      })

    socket =
      RuntimeShell.handle_tick(
        original,
        tick_ms: 500,
        cancel_timer: fn _timer_ref -> raise "should not cancel while editing" end,
        send_after: fn pid, message, delay ->
          send(test_pid, {:scheduled, pid, message, delay})
          :next_timer_ref
        end,
        handle_live_refresh: fn _socket -> raise "should not refresh while editing" end
      )

    # Any assign change re-renders and patches the DOM GridStack is mutating,
    # so edit-mode ticks must leave the socket exactly as they found it.
    assert socket.assigns == original.assigns
    assert_received {:scheduled, _pid, :tick, 500}
  end

  test "resolve_succeeded finishes the original resolve id and hydrates selection" do
    socket =
      RuntimeShell.resolve_succeeded(
        socket(),
        :requested_id,
        :returned_id,
        %{result: true},
        selection_hydration_opts: [sentinel: :ok],
        resolve_finished: fn socket, resolve_id, result ->
          assign(socket, :runtime_event, {:resolved, resolve_id, result})
        end,
        hydrate_selection: fn socket, selection_opts ->
          assign(socket, :hydrated_with, selection_opts)
        end
      )

    assert socket.assigns.runtime_event == {:resolved, :requested_id, %{result: true}}
    assert socket.assigns.hydrated_with == [sentinel: :ok]
  end

  test "resolve_failed delegates failure details" do
    socket =
      RuntimeShell.resolve_failed(
        socket(),
        :resolve_id,
        {:shutdown, :timeout},
        resolve_failed: fn socket, resolve_id, reason ->
          assign(socket, :runtime_event, {:failed, resolve_id, reason})
        end
      )

    assert socket.assigns.runtime_event == {:failed, :resolve_id, {:shutdown, :timeout}}
  end

  test "handle_invalidation delegates invalidation handling" do
    socket =
      RuntimeShell.handle_invalidation(
        socket(),
        %{kind: :source_changed},
        handle_invalidation: fn socket, invalidation ->
          assign(socket, :runtime_event, {:invalidated, invalidation})
        end
      )

    assert socket.assigns.runtime_event == {:invalidated, %{kind: :source_changed}}
  end

  test "terminate cancels the pending tick timer and active resolves" do
    test_pid = self()
    timer_ref = make_ref()

    socket =
      RuntimeShell.terminate(
        socket(%{dashboard_tick_timer_ref: timer_ref}),
        cancel_timer: fn timer_ref ->
          send(test_pid, {:canceled, timer_ref})
          :ok
        end,
        cancel_active_resolves: fn socket, reason ->
          assign(socket, :runtime_event, {:canceled_resolves, reason})
        end
      )

    assert socket.assigns.dashboard_tick_timer_ref == nil

    assert socket.assigns.runtime_event ==
             {:canceled_resolves, {:shutdown, :dashboard_live_view_terminated}}

    assert_received {:canceled, ^timer_ref}
  end

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            dashboard_tick_timer_ref: nil,
            dashboard_live_refresh_ms: nil
          },
          assigns
        )
    }
  end
end
