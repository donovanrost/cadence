defmodule CadenceWeb.OpsDashboardShowLive.ViewTestSupport do
  @moduledoc false

  import ExUnit.Assertions, only: [flunk: 1]
  import Phoenix.LiveViewTest, only: [has_element?: 2]

  alias CadenceWeb.AsyncLiveViewTestSupport

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
    AsyncLiveViewTestSupport.render_async(view, timeout)
  end

  def await_dashboard_resolved(view, timeout \\ @default_timeout) do
    render_dashboard_async(view, timeout)

    if has_element?(view, @resolved_runtime_selector) do
      view
    else
      flunk("dashboard runtime did not resolve within #{timeout}ms")
    end
  end

  defdelegate track_dashboard_view(view), to: AsyncLiveViewTestSupport, as: :track_async_view

  def stop_dashboard_views(views, timeout \\ @default_timeout) when is_list(views) do
    AsyncLiveViewTestSupport.stop_async_views(views, timeout)
  end

  def stop_dashboard_view(view, timeout \\ @default_timeout) do
    AsyncLiveViewTestSupport.stop_async_view(view, timeout)
  end
end
