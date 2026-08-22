defmodule CadenceWeb.OpsDashboardShowLive.RuntimeShell do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.LiveRefresh
  alias CadenceWeb.OpsDashboardShowLive.Runtime
  alias CadenceWeb.OpsDashboardShowLive.RuntimeInvalidations
  alias CadenceWeb.OpsDashboardShowLive.SelectionHydration

  @default_tick_ms 1_000

  def activate(socket, current_scope, mission, document, connected?, opts \\ [])

  def activate(socket, current_scope, mission, document, true, opts) do
    subscribe_runtime_invalidations(current_scope, mission, document, opts)
    schedule_tick(socket, opts)
  end

  def activate(socket, _current_scope, _mission, _document, _connected?, _opts), do: socket

  def handle_tick(socket, opts \\ []) do
    if editing?(socket) do
      keep_tick_alive(socket, opts)
    else
      socket
      |> schedule_tick(opts)
      |> handle_live_refresh(opts)
    end
  end

  def handle_invalidation(socket, invalidation, opts \\ []) do
    handle_invalidation_fn(opts).(socket, invalidation)
  end

  def resolve_succeeded(socket, resolve_id, returned_resolve_id, result, opts \\ []) do
    socket
    |> resolve_finished(matching_resolve_id(resolve_id, returned_resolve_id), result, opts)
    |> hydrate_selection(opts)
  end

  def resolve_failed(socket, resolve_id, reason, opts \\ []) do
    resolve_failed_fn(opts).(socket, resolve_id, reason)
  end

  def terminate(socket, opts \\ []) do
    socket
    |> cancel_tick_timer(opts)
    |> cancel_active_resolves(opts)
  end

  def schedule_tick(socket, opts \\ []) do
    socket = cancel_tick_timer(socket, opts)
    timer_ref = send_after_fn(opts).(self(), :tick, tick_interval_ms(socket, opts))
    assign(socket, :dashboard_tick_timer_ref, timer_ref)
  end

  # Edit mode must stay free of assigns churn: every changed assign re-renders
  # and patches the DOM that GridStack is actively mutating. Re-arm the timer
  # without touching the socket so the loop resumes once edit mode ends.
  defp keep_tick_alive(socket, opts) do
    send_after_fn(opts).(self(), :tick, tick_interval_ms(socket, opts))
    socket
  end

  defp editing?(socket), do: Map.get(socket.assigns, :edit_mode?, false)

  defp tick_interval_ms(socket, opts) do
    socket.assigns.dashboard_live_refresh_ms || tick_ms(opts)
  end

  def cancel_tick_timer(socket, opts \\ []) do
    case Map.get(socket.assigns, :dashboard_tick_timer_ref) do
      timer_ref when is_reference(timer_ref) ->
        cancel_timer_fn(opts).(timer_ref)

      _other ->
        :ok
    end

    assign(socket, :dashboard_tick_timer_ref, nil)
  end

  defp matching_resolve_id(resolve_id, resolve_id), do: resolve_id
  defp matching_resolve_id(resolve_id, _returned_resolve_id), do: resolve_id

  defp subscribe_runtime_invalidations(current_scope, mission, document, opts) do
    subscribe_fn(opts).(current_scope, mission, document)
  end

  defp handle_live_refresh(socket, opts) do
    case Keyword.get(opts, :handle_live_refresh) do
      callback when is_function(callback, 2) -> callback.(socket, opts)
      callback when is_function(callback, 1) -> callback.(socket)
      _missing -> LiveRefresh.handle_tick(socket)
    end
  end

  defp resolve_finished(socket, resolve_id, result, opts) do
    resolve_finished_fn(opts).(socket, resolve_id, result)
  end

  defp hydrate_selection(socket, opts) do
    selection_opts = Keyword.get(opts, :selection_hydration_opts, [])
    hydrate_selection_fn(opts).(socket, selection_opts)
  end

  defp cancel_active_resolves(socket, opts) do
    cancel_active_resolves_fn(opts).(socket, {:shutdown, :dashboard_live_view_terminated})
  end

  defp subscribe_fn(opts),
    do: Keyword.get(opts, :subscribe_runtime_invalidations, &RuntimeInvalidations.subscribe/3)

  defp send_after_fn(opts),
    do: Keyword.get(opts, :send_after, &Process.send_after/3)

  defp cancel_timer_fn(opts),
    do: Keyword.get(opts, :cancel_timer, &Process.cancel_timer/1)

  defp resolve_finished_fn(opts),
    do: Keyword.get(opts, :resolve_finished, &Runtime.resolve_finished/3)

  defp resolve_failed_fn(opts),
    do: Keyword.get(opts, :resolve_failed, &Runtime.resolve_failed/3)

  defp hydrate_selection_fn(opts),
    do: Keyword.get(opts, :hydrate_selection, &SelectionHydration.hydrate_from_query/2)

  defp handle_invalidation_fn(opts),
    do: Keyword.get(opts, :handle_invalidation, &RuntimeInvalidations.handle_invalidation/2)

  defp cancel_active_resolves_fn(opts),
    do: Keyword.get(opts, :cancel_active_resolves, &Runtime.cancel_active_resolves/2)

  defp tick_ms(opts) do
    case Keyword.get(opts, :tick_ms, @default_tick_ms) do
      tick_ms when is_integer(tick_ms) and tick_ms > 0 -> tick_ms
      _invalid -> @default_tick_ms
    end
  end
end
