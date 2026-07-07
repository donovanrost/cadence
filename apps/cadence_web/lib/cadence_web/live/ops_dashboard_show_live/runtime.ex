defmodule CadenceWeb.OpsDashboardShowLive.Runtime do
  @moduledoc """
  Socket-level dashboard runtime coordination.

  This module applies `Cadence.Dashboards.RuntimeCoordinator` decisions in the
  LiveView process and runs dashboard engine resolves through LiveView async
  tasks.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [cancel_async: 3, start_async: 3]

  alias Cadence.Dashboards.RuntimeCoordinator
  alias CadenceWeb.OpsDashboardShowLive.ChartAppends
  alias CadenceWeb.OpsDashboardShowLive.EngineResolution
  alias CadenceWeb.OpsDashboardShowLive.RuntimeResolveTask

  @type resolve_mode :: :initial | :context_change | :live_tick | :stream_append
  @async_prefix :dashboard_engine_resolve

  @spec assign_runtime(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_runtime(socket) do
    socket
    |> assign(:dashboard_runtime_coordinator, RuntimeCoordinator.new())
    |> assign(:dashboard_runtime_decisions, [])
    |> assign(:dashboard_runtime_resolved?, false)
    |> assign(:dashboard_runtime_pending_appends, %{})
    |> assign(:dashboard_runtime_pending_chart_remounts, %{})
  end

  @spec resolve_engine(Phoenix.LiveView.Socket.t(), resolve_mode(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def resolve_engine(socket, resolve_mode, opts \\ []) when is_list(opts) do
    opts = put_start_timing(opts)

    {coordinator, decisions} =
      socket
      |> coordinator()
      |> RuntimeCoordinator.request_resolve(resolve_mode, opts)

    resolved? =
      if decision_action?(decisions, :start_resolve) do
        false
      else
        socket.assigns.dashboard_runtime_resolved?
      end

    socket
    |> assign_runtime_result(coordinator, decisions, resolved?)
    |> apply_decisions(decisions, opts)
  end

  @spec resolve_finished(Phoenix.LiveView.Socket.t(), term(), term()) ::
          Phoenix.LiveView.Socket.t()
  def resolve_finished(socket, resolve_id, result) do
    opts = finish_timing()

    {coordinator, decisions} =
      socket.assigns.dashboard_runtime_coordinator
      |> RuntimeCoordinator.resolve_finished(resolve_id, opts)

    accepted? = decision_action?(decisions, :accept_result)

    socket =
      if accepted? do
        socket
        |> EngineResolution.apply_result(result)
        |> maybe_remount_charts(resolve_id)
        |> push_live_tick_appends(resolve_id, result)
      else
        socket
      end

    resolved? = accepted? or socket.assigns.dashboard_runtime_resolved?

    socket
    |> cleanup_pending_append(resolve_id)
    |> cleanup_pending_chart_remount(resolve_id)
    |> assign_runtime_result(
      coordinator,
      socket.assigns.dashboard_runtime_decisions ++ decisions,
      resolved?
    )
    |> apply_decisions(decisions, [])
  end

  @spec resolve_failed(Phoenix.LiveView.Socket.t(), term(), term()) :: Phoenix.LiveView.Socket.t()
  def resolve_failed(socket, resolve_id, reason) do
    finished_at = DateTime.utc_now()

    {coordinator, decisions} =
      socket.assigns.dashboard_runtime_coordinator
      |> RuntimeCoordinator.resolve_failed(resolve_id,
        reason: :resolve_failed,
        failed_at: finished_at,
        finished_at: finished_at,
        finished_monotonic_ms: System.monotonic_time(:millisecond)
      )

    resolved? = socket.assigns.dashboard_runtime_resolved?

    socket
    |> cleanup_pending_append(resolve_id)
    |> cleanup_pending_chart_remount(resolve_id)
    |> assign_runtime_result(
      coordinator,
      socket.assigns.dashboard_runtime_decisions ++ annotate_failure(decisions, reason),
      resolved?
    )
    |> apply_decisions(decisions, [])
  end

  @spec resolved?(Phoenix.LiveView.Socket.t()) :: boolean()
  def resolved?(socket), do: Map.get(socket.assigns, :dashboard_runtime_resolved?, false)

  @spec decision_summary([map()] | term()) :: map()
  def decision_summary(decisions) when is_list(decisions) do
    %{
      actions: decision_actions(decisions),
      refresh_starts: decision_mode_reason_summary(decisions, :start_resolve),
      refresh_cancellations: decision_mode_reason_summary(decisions, :cancel_obsolete),
      refresh_coalesced: decision_mode_reason_summary(decisions, :coalesce_tick),
      refresh_noops: decision_mode_reason_summary(decisions, :noop),
      refresh_failures: decision_reason_summary(decisions, :record_degradation),
      refresh_ignored: decision_reason_summary(decisions, :ignore_result),
      refresh_ignored_resolve_ids: decision_resolve_id_summary(decisions, :ignore_result),
      last_refresh_started_at: last_refresh_timing(decisions, :started_at),
      last_refresh_finished_at: last_refresh_timing(decisions, :finished_at),
      last_refresh_duration_ms: last_refresh_timing(decisions, :duration_ms),
      canceled_resolve_count: decision_count(decisions, :cancel_obsolete),
      failed_resolve_count: decision_count(decisions, :record_degradation)
    }
  end

  def decision_summary(_decisions), do: decision_summary([])

  @spec refresh_status(map() | term(), [map()] | term(), boolean()) :: map()
  def refresh_status(
        %{status: :resolving, active_mode: active_mode, active_started_at: active_started_at},
        _decisions,
        _resolved?
      ) do
    %{
      status: "refreshing",
      reason: diagnostic_token(active_mode),
      active_mode: diagnostic_token(active_mode),
      active_started_at: diagnostic_token(active_started_at),
      visible_action: nil
    }
  end

  def refresh_status(_coordinator, decisions, resolved?) when is_list(decisions) do
    case last_visible_refresh_decision(decisions) do
      %{action: :accept_result} ->
        refresh_status_summary("settled", :accepted, nil, nil, :accept_result)

      %{action: :record_degradation, reason: reason} ->
        refresh_status_summary("degraded", reason, nil, nil, :record_degradation)

      %{action: :noop, reason: reason} ->
        if resolved? do
          refresh_status_summary("suppressed", reason, nil, nil, :noop)
        else
          refresh_status_summary("unresolved", reason, nil, nil, :noop)
        end

      _decision ->
        if resolved? do
          refresh_status_summary("settled", :accepted, nil, nil, nil)
        else
          refresh_status_summary("unresolved", :not_resolved, nil, nil, nil)
        end
    end
  end

  def refresh_status(_coordinator, _decisions, true),
    do: refresh_status_summary("settled", :accepted, nil, nil, nil)

  def refresh_status(_coordinator, _decisions, _resolved?),
    do: refresh_status_summary("unresolved", :not_resolved, nil, nil, nil)

  defp decision_actions(decisions) do
    decisions
    |> Enum.map(&Map.get(&1, :action))
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" ", &Atom.to_string/1)
  end

  defp decision_mode_reason_summary(decisions, action) do
    decisions
    |> Enum.filter(&(Map.get(&1, :action) == action))
    |> Enum.map(fn decision ->
      [
        decision |> Map.get(:resolve_mode) |> diagnostic_token(),
        decision |> Map.get(:reason) |> diagnostic_token()
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")
    end)
    |> Enum.reject(&(&1 == ""))
    |> decision_count_summary()
  end

  defp decision_reason_summary(decisions, action) do
    decisions
    |> Enum.filter(&(Map.get(&1, :action) == action))
    |> Enum.map(&(Map.get(&1, :reason) |> diagnostic_token()))
    |> Enum.reject(&is_nil/1)
    |> decision_count_summary()
  end

  defp decision_count(decisions, action),
    do: Enum.count(decisions, &(Map.get(&1, :action) == action))

  defp decision_resolve_id_summary(decisions, action) do
    decisions
    |> Enum.filter(&(Map.get(&1, :action) == action))
    |> Enum.map(&(Map.get(&1, :resolve_id) |> diagnostic_token()))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      summary -> summary
    end
  end

  defp decision_count_summary([]), do: nil

  defp decision_count_summary(values) do
    values
    |> Enum.frequencies()
    |> Enum.sort_by(fn {value, _count} -> value end)
    |> Enum.map_join(" ", fn {value, count} -> "#{value}:#{count}" end)
  end

  defp diagnostic_token(nil), do: nil
  defp diagnostic_token(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp diagnostic_token(value) when is_atom(value), do: Atom.to_string(value)
  defp diagnostic_token(value) when is_binary(value), do: value
  defp diagnostic_token(value) when is_integer(value), do: value
  defp diagnostic_token(value), do: inspect(value)

  defp last_visible_refresh_decision(decisions) do
    Enum.find(Enum.reverse(decisions), fn decision ->
      Map.get(decision, :action) in [:accept_result, :record_degradation, :noop]
    end)
  end

  defp refresh_status_summary(status, reason, active_mode, active_started_at, visible_action) do
    %{
      status: status,
      reason: diagnostic_token(reason),
      active_mode: diagnostic_token(active_mode),
      active_started_at: diagnostic_token(active_started_at),
      visible_action: diagnostic_token(visible_action)
    }
  end

  defp last_refresh_timing(decisions, key) do
    decisions
    |> Enum.reverse()
    |> Enum.find_value(fn decision ->
      if Map.get(decision, :action) in [:accept_result, :record_degradation] do
        decision
        |> Map.get(:details, %{})
        |> Map.get(key)
        |> diagnostic_token()
      end
    end)
  end

  defp put_start_timing(opts) do
    opts
    |> Keyword.put_new(:started_at, DateTime.utc_now())
    |> Keyword.put_new(:started_monotonic_ms, System.monotonic_time(:millisecond))
  end

  defp finish_timing do
    [
      finished_at: DateTime.utc_now(),
      finished_monotonic_ms: System.monotonic_time(:millisecond)
    ]
  end

  @spec cancel_active_resolves(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def cancel_active_resolves(socket, reason) do
    socket
    |> active_resolve_async_names()
    |> Enum.reduce(socket, fn async_name, socket ->
      cancel_async(socket, async_name, reason)
    end)
  end

  def async_name(resolve_id), do: {@async_prefix, resolve_id}

  defp active_resolve_async_names(socket) do
    socket.private
    |> Map.get(:live_async, %{})
    |> Map.keys()
    |> Enum.filter(fn
      {@async_prefix, _resolve_id} -> true
      _other -> false
    end)
  end

  defp apply_decisions(socket, decisions, opts) do
    Enum.reduce(decisions, socket, fn
      %{action: :cancel_obsolete, superseded_resolve_id: resolve_id}, socket ->
        socket
        |> cleanup_pending_append(resolve_id)
        |> cancel_async(async_name(resolve_id), {:shutdown, :obsolete_dashboard_resolve})

      %{action: :start_resolve, resolve_mode: resolve_mode, resolve_id: resolve_id}, socket ->
        start_resolve(socket, resolve_mode, resolve_id, opts)

      _decision, socket ->
        socket
    end)
  end

  defp start_resolve(socket, resolve_mode, resolve_id, opts) do
    request = EngineResolution.request(socket, resolve_mode)
    comparison_request = EngineResolution.comparison_request(socket, resolve_mode)
    browser_test_sandbox_owner_key = browser_test_sandbox_owner_key(socket)

    socket =
      socket
      |> maybe_put_pending_append(resolve_id, resolve_mode, opts)
      |> maybe_put_pending_chart_remount(resolve_id, opts)

    if inline_resolves?() do
      resolve_finished(
        socket,
        resolve_id,
        EngineResolution.resolve_request_bundle(request, comparison_request)
      )
    else
      start_async(socket, async_name(resolve_id), fn ->
        RuntimeResolveTask.resolve(
          resolve_id,
          request,
          comparison_request,
          browser_test_sandbox_owner_key
        )
      end)
    end
  end

  defp browser_test_sandbox_owner_key(socket) do
    Map.get(socket.assigns, :dashboard_browser_test_sandbox_owner_key)
  end

  defp inline_resolves? do
    Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?, false)
  end

  defp push_live_tick_appends(socket, resolve_id, %{resolve_mode: :live_tick}) do
    pending_append =
      socket.assigns.dashboard_runtime_pending_appends
      |> Map.get(resolve_id)

    case pending_append do
      %{previous_data: previous_data, previous_markers: previous_markers} ->
        ChartAppends.push(socket, previous_data, previous_markers)

      previous_data when is_map(previous_data) ->
        ChartAppends.push(socket, previous_data)

      _missing ->
        socket
    end
  end

  defp push_live_tick_appends(socket, _resolve_id, _result), do: socket

  defp assign_runtime_result(socket, coordinator, decisions, resolved?) do
    socket
    |> assign(:dashboard_runtime_coordinator, coordinator)
    |> assign(:dashboard_runtime_decisions, decisions)
    |> assign(:dashboard_runtime_resolved?, resolved?)
  end

  defp coordinator(socket) do
    Map.get(socket.assigns, :dashboard_runtime_coordinator, RuntimeCoordinator.new())
  end

  defp maybe_put_pending_append(socket, resolve_id, :live_tick, opts) do
    case Keyword.get(opts, :append_previous_data) do
      previous_data when is_map(previous_data) ->
        pending_appends =
          socket.assigns.dashboard_runtime_pending_appends
          |> Map.put(resolve_id, %{
            previous_data: previous_data,
            previous_markers: ChartAppends.marker_snapshots(socket)
          })

        assign(socket, :dashboard_runtime_pending_appends, pending_appends)

      _other ->
        socket
    end
  end

  defp maybe_put_pending_append(socket, _resolve_id, _resolve_mode, _opts), do: socket

  defp cleanup_pending_append(socket, resolve_id) do
    pending_appends =
      socket.assigns.dashboard_runtime_pending_appends
      |> Map.delete(resolve_id)

    assign(socket, :dashboard_runtime_pending_appends, pending_appends)
  end

  defp maybe_put_pending_chart_remount(socket, resolve_id, opts) do
    if Keyword.get(opts, :remount_charts_after_resolve?, false) do
      pending_remounts =
        socket.assigns.dashboard_runtime_pending_chart_remounts
        |> Map.put(resolve_id, true)

      assign(socket, :dashboard_runtime_pending_chart_remounts, pending_remounts)
    else
      socket
    end
  end

  defp maybe_remount_charts(socket, resolve_id) do
    if Map.get(socket.assigns.dashboard_runtime_pending_chart_remounts, resolve_id) do
      assign(socket, :chart_epoch, socket.assigns.chart_epoch + 1)
    else
      socket
    end
  end

  defp cleanup_pending_chart_remount(socket, resolve_id) do
    pending_remounts =
      socket.assigns.dashboard_runtime_pending_chart_remounts
      |> Map.delete(resolve_id)

    assign(socket, :dashboard_runtime_pending_chart_remounts, pending_remounts)
  end

  defp decision_action?(decisions, action) do
    Enum.any?(decisions, &(Map.get(&1, :action) == action))
  end

  defp annotate_failure(decisions, reason) do
    Enum.map(decisions, fn
      %{action: :record_degradation, details: details} = decision when is_map(details) ->
        %{decision | details: Map.put(details, :async_exit_reason, reason)}

      decision ->
        decision
    end)
  end
end
