defmodule CadenceWeb.OpsDashboardPage.Updates do
  @moduledoc """
  Live delivery for the Ops dashboard page.

  While a dashboard is viewed in live time it is refreshed by runtime
  invalidations and by a refresh tick. A refresh re-prepares the host context,
  which reauthorizes the page and re-resolves the dashboard; LiveVue delivers
  the changed snapshot to the browser as a props diff. Bursts of invalidations
  coalesce into one refresh. Edit mode and frozen time ranges are not live.
  """
  alias Cadence.Dashboards.RuntimeInvalidation
  alias Phoenix.Component
  alias Phoenix.LiveView

  @default_refresh_ms 2_000
  @min_refresh_ms 1_000
  @max_refresh_ms 60_000
  @coalesce_ms 250
  @pubsub Cadence.PubSub

  @doc "The live delivery the browser should expect for a loaded view."
  def policy(%{mode: mode}, %{snapshot: %{context: %{time_mode: "live"} = context}})
      when mode == :view do
    %{active: true, refresh_ms: refresh_ms(context)}
  end

  def policy(_session, _view), do: %{active: false, refresh_ms: nil}

  defp refresh_ms(%{refresh_ms: ms}) when is_integer(ms),
    do: ms |> max(@min_refresh_ms) |> min(@max_refresh_ms)

  defp refresh_ms(_context), do: @default_refresh_ms

  @doc "Starts, retunes or stops delivery to match the page that was just prepared."
  def sync(socket, session, %{data: %{live: %{active: true, refresh_ms: ms}}}) do
    if LiveView.connected?(socket), do: start(socket, session, ms), else: socket
  end

  def sync(socket, _session, _page), do: stop(socket)

  defp start(socket, %{token: token, identity: {org, _, mission, dashboard, _path}}, ms) do
    case socket.assigns[:ops_dashboard_updates] do
      %{token: ^token, refresh_ms: ^ms} ->
        socket

      %{token: ^token} = updates ->
        Process.cancel_timer(updates.timer)
        timer = Process.send_after(self(), {:dashboard_live_tick, token}, ms)

        Component.assign(socket, :ops_dashboard_updates, %{updates | timer: timer, refresh_ms: ms})

      _ ->
        socket = stop(socket)
        filters = %{organization_id: org, mission_id: mission, dashboard_id: dashboard}
        :ok = RuntimeInvalidation.subscribe(filters)

        Component.assign(socket, :ops_dashboard_updates, %{
          token: token,
          topics: topics(org, mission, dashboard),
          scope: {org, mission, dashboard},
          refresh_ms: ms,
          timer: Process.send_after(self(), {:dashboard_live_tick, token}, ms),
          pending: nil
        })
    end
  end

  def stop(socket) do
    case socket.assigns[:ops_dashboard_updates] do
      %{timer: timer, pending: pending, topics: topics} ->
        Process.cancel_timer(timer)
        if pending, do: Process.cancel_timer(pending)
        Enum.each(topics, &Phoenix.PubSub.unsubscribe(@pubsub, &1))
        Component.assign(socket, :ops_dashboard_updates, nil)

      _ ->
        socket
    end
  end

  @doc "A refresh tick. Returns `{:refresh, socket}` when the current page is due."
  def tick(socket, token) do
    case socket.assigns[:ops_dashboard_updates] do
      %{token: ^token, refresh_ms: ms, pending: pending} = updates ->
        if pending, do: Process.cancel_timer(pending)
        timer = Process.send_after(self(), {:dashboard_live_tick, token}, ms)
        updates = %{updates | timer: timer, pending: nil}
        {:refresh, Component.assign(socket, :ops_dashboard_updates, updates)}

      _ ->
        {:ignore, socket}
    end
  end

  @doc "A runtime invalidation; relevant ones coalesce into a single refresh."
  def invalidated(socket, event) do
    case socket.assigns[:ops_dashboard_updates] do
      %{pending: nil, scope: scope, token: token} = updates ->
        if relevant?(event, scope) do
          timer = Process.send_after(self(), {:dashboard_live_flush, token}, @coalesce_ms)
          Component.assign(socket, :ops_dashboard_updates, %{updates | pending: timer})
        else
          socket
        end

      _ ->
        socket
    end
  end

  @doc "A coalesced invalidation. Returns `{:refresh, socket}` when still current."
  def flush(socket, token) do
    case socket.assigns[:ops_dashboard_updates] do
      %{token: ^token} = updates ->
        {:refresh, Component.assign(socket, :ops_dashboard_updates, %{updates | pending: nil})}

      _ ->
        {:ignore, socket}
    end
  end

  # Topics are mission- or dashboard-narrowed; an org-wide event without a
  # dashboard still applies, another dashboard's event does not.
  defp relevant?(%{filters: filters}, {org, mission, dashboard}) when is_map(filters) do
    Map.get(filters, :organization_id, org) == org and
      Map.get(filters, :mission_id, mission) in [nil, mission] and
      Map.get(filters, :dashboard_id, dashboard) in [nil, dashboard]
  end

  defp relevant?(_event, _scope), do: true

  defp topics(org, mission, dashboard) do
    [
      RuntimeInvalidation.organization_topic(org),
      RuntimeInvalidation.mission_topic(org, mission),
      RuntimeInvalidation.dashboard_topic(org, mission, dashboard)
    ]
  end
end
