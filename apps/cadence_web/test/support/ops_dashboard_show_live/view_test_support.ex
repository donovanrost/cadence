defmodule CadenceWeb.OpsDashboardShowLive.ViewTestSupport do
  @moduledoc false

  import ExUnit.Assertions, only: [flunk: 1]
  import Phoenix.LiveViewTest, only: [has_element?: 2, render_async: 2]

  alias Phoenix.LiveViewTest.ClientProxy

  @default_timeout 5_000
  @resolved_runtime_selector ~s(#ops-dashboard-show-page[data-runtime-status="idle"][data-runtime-resolved="true"])

  defmacro __using__(_opts) do
    quote do
      alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport, as: DashboardViewTestSupport

      import Phoenix.LiveViewTest, except: [live: 2]
      import DashboardViewTestSupport

      defmacrop live(conn, path) do
        quote do
          DashboardViewTestSupport.await_live_result(
            Phoenix.LiveViewTest.live(unquote(conn), unquote(path))
          )
        end
      end
    end
  end

  def await_live_result(result, timeout \\ @default_timeout) do
    case result do
      {:ok, view, html} ->
        await_dashboard_resolved(view, timeout)
        {:ok, view, html}

      other ->
        other
    end
  end

  def render_dashboard_async(view, timeout \\ @default_timeout) do
    track_dashboard_view(view)
    render_async(view, timeout)
  end

  def await_dashboard_resolved(view, timeout \\ @default_timeout) do
    render_dashboard_async(view, timeout)

    if has_element?(view, @resolved_runtime_selector) do
      view
    else
      flunk("dashboard runtime did not resolve within #{timeout}ms")
    end
  end

  def track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      ExUnit.Callbacks.on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end

    view
  end

  def stop_dashboard_views(views, timeout \\ @default_timeout) when is_list(views) do
    views
    |> Enum.reverse()
    |> Enum.each(&stop_dashboard_view(&1, timeout))

    :ok
  end

  def stop_dashboard_view(%{pid: pid} = view, timeout \\ @default_timeout) when is_pid(pid) do
    live_view_monitor_ref = Process.monitor(pid)

    if Process.alive?(pid) do
      drain_dashboard_view(view, timeout)

      case suspend_process(pid) do
        :ok ->
          try do
            pid
            |> active_async_pids()
            |> Enum.map(&{&1, Process.monitor(&1)})
            |> Enum.each(fn {async_pid, monitor_ref} ->
              await_process_down(monitor_ref, async_pid, timeout, "dashboard async task")
            end)

            terminate_process(pid, timeout)
          after
            resume_process(pid)
          end

        :down ->
          :ok
      end
    end

    await_process_down(live_view_monitor_ref, pid, timeout, "dashboard LiveView")
    stop_client_proxy(view)

    :ok
  end

  defp drain_dashboard_view(view, timeout) do
    render_async(view, timeout)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp active_async_pids(pid) do
    case :sys.get_state(pid) do
      %{socket: %{private: private}} ->
        private
        |> Map.get(:live_async, %{})
        |> Map.values()
        |> Enum.map(fn {_monitor_ref, async_pid, _kind} -> async_pid end)

      _other ->
        []
    end
  catch
    :exit, reason -> process_down_or_exit(pid, reason, [])
  end

  defp suspend_process(pid) do
    :sys.suspend(pid)
  catch
    :exit, reason -> process_down_or_exit(pid, reason, :down)
  end

  defp terminate_process(pid, timeout) do
    :sys.terminate(pid, :normal, timeout)
  catch
    :exit, reason -> process_down_or_exit(pid, reason, :ok)
  end

  defp resume_process(pid) do
    if Process.alive?(pid) do
      :sys.resume(pid)
    else
      :ok
    end
  catch
    :exit, reason -> process_down_or_exit(pid, reason, :ok)
  end

  defp process_down_or_exit(pid, reason, down_result) do
    if Process.alive?(pid) do
      exit(reason)
    else
      down_result
    end
  end

  defp stop_client_proxy(%{proxy: {_proxy_ref, _topic, proxy_pid}}) do
    if Process.alive?(proxy_pid) do
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})
    end
  catch
    :exit, _reason -> :ok
  end

  defp await_process_down(monitor_ref, expected_pid, timeout, process_name) do
    receive do
      {:DOWN, ^monitor_ref, :process, ^expected_pid, _reason} ->
        :ok
    after
      timeout -> flunk("#{process_name} did not stop within #{timeout}ms")
    end
  end
end
