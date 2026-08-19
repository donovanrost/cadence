defmodule CadenceWeb.OpsDashboardShowLive.EngineResolution do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Telemetry.Storage, as: TelemetryStorage

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Frame,
    PlacementFrames,
    Resolution,
    ResolutionContext,
    RuntimeCache
  }

  alias CadenceWeb.OpsDashboardShowLive.{
    DataViewComparison,
    RuntimeDataRequest,
    RuntimeResult,
    WidgetData
  }

  @spec request(Phoenix.LiveView.Socket.t(), atom()) :: RuntimeDataRequest.t()
  def request(socket, resolve_mode) do
    RuntimeDataRequest.from_socket(socket, resolve_mode)
  end

  @spec comparison_request(Phoenix.LiveView.Socket.t(), atom()) :: RuntimeDataRequest.t() | nil
  def comparison_request(socket, resolve_mode) do
    DataViewComparison.request(socket, resolve_mode)
  end

  @spec resolution_context() :: ResolutionContext.t()
  def resolution_context do
    source_execution_opts =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    cache_config = Application.get_env(:cadence, :dashboard_runtime_cache, [])
    cache_server = if Process.whereis(RuntimeCache), do: RuntimeCache, else: nil

    build_resolution_context(source_execution_opts, cache_config, cache_server)
  end

  @doc false
  @spec build_resolution_context(keyword(), keyword(), GenServer.server() | nil) ::
          ResolutionContext.t()
  def build_resolution_context(source_execution_opts, cache_config, cache_server)
      when is_list(source_execution_opts) and is_list(cache_config) do
    cache_enabled? =
      Keyword.get(cache_config, :enabled?, true) == true and not is_nil(cache_server)

    source_execution_opts = put_dashboard_runtime_source_opts(source_execution_opts)

    ResolutionContext.new!(
      persisted?: true,
      validate_dashboard_contract?: true,
      persist_limit_selected_clock_audit_events?: true,
      runtime_cache: if(cache_enabled?, do: cache_server, else: false),
      plan_cache?: cache_enabled?,
      source_result_cache?:
        cache_enabled? and Keyword.get(cache_config, :source_result_cache?, true) == true,
      frame_cache?: cache_enabled? and Keyword.get(cache_config, :frame_cache?, true) == true,
      source_execution_opts: source_execution_opts
    )
  end

  @spec resolve_request_bundle(
          RuntimeDataRequest.t(),
          RuntimeDataRequest.t() | nil,
          ResolutionContext.t()
        ) ::
          RuntimeResult.result() | DataViewComparison.t()
  def resolve_request_bundle(primary_request, nil, context) do
    resolve_request(primary_request, context)
  end

  def resolve_request_bundle(primary_request, comparison_request, context) do
    primary_request
    |> resolve_request(context)
    |> DataViewComparison.new(resolve_request(comparison_request, context))
  end

  @spec resolve_request(
          RuntimeDataRequest.t() | DashboardResolveRequest.t(),
          ResolutionContext.t()
        ) ::
          Cadence.Dashboards.DashboardResolveResult.t()
  def resolve_request(%RuntimeDataRequest{} = request, %ResolutionContext{} = context) do
    request
    |> RuntimeDataRequest.to_engine_request()
    |> resolve_request(context)
  end

  def resolve_request(%DashboardResolveRequest{} = request, %ResolutionContext{} = context) do
    Resolution.resolve(request, context)
  end

  @spec apply_result(Phoenix.LiveView.Socket.t(), RuntimeResult.result()) ::
          Phoenix.LiveView.Socket.t()
  def apply_result(socket, %DataViewComparison{} = result) do
    case RuntimeResult.resolve_mode(result.primary_result) do
      resolve_mode when resolve_mode in [:initial, :context_change] ->
        socket
        |> apply_full_result(result.primary_result)
        |> DataViewComparison.assign_result(result.comparison_result)

      :live_tick ->
        socket
        |> apply_live_tick_result(result.primary_result)
        |> DataViewComparison.assign_result(nil)

      _other ->
        socket
        |> apply_full_result(result.primary_result)
        |> DataViewComparison.assign_result(result.comparison_result)
    end
  end

  def apply_result(socket, result) do
    case RuntimeResult.resolve_mode(result) do
      resolve_mode when resolve_mode in [:initial, :context_change] ->
        apply_full_result(socket, result)

      :live_tick ->
        apply_live_tick_result(socket, result)

      _other ->
        apply_full_result(socket, result)
    end
  end

  @spec refresh_ms(Phoenix.LiveView.Socket.t(), pos_integer()) :: pos_integer()
  def refresh_ms(socket, default_ms) do
    socket.assigns.dashboard_document
    |> then(&get_in(&1.defaults, ["time", "refresh_ms"]))
    |> case do
      refresh_ms when is_integer(refresh_ms) and refresh_ms > 0 -> refresh_ms
      _other -> default_ms
    end
  end

  defp put_dashboard_runtime_source_opts(opts) do
    opts
    |> put_default_source_opt(
      :telemetry,
      :backfill_lifecycle_events_fun,
      &TelemetryStorage.list_backfill_lifecycle_events/2
    )
  end

  defp put_default_source_opt(opts, logical_source, key, value) do
    source_opts = normalize_source_opts(Keyword.get(opts, :source_opts, %{}))
    adapter_opts = normalize_adapter_opts(Map.get(source_opts, logical_source, []))

    Keyword.put(
      opts,
      :source_opts,
      Map.put(source_opts, logical_source, Keyword.put_new(adapter_opts, key, value))
    )
  end

  defp normalize_source_opts(source_opts) when is_map(source_opts), do: source_opts
  defp normalize_source_opts(_source_opts), do: %{}

  defp normalize_adapter_opts(adapter_opts) when is_list(adapter_opts), do: adapter_opts
  defp normalize_adapter_opts(_adapter_opts), do: []

  defp apply_full_result(socket, result) do
    frames_by_placement = RuntimeResult.frames_by_placement(result)

    socket
    |> assign(:dashboard_engine_result, result)
    |> assign(:dashboard_engine_frames_by_placement, frames_by_placement)
    |> DataViewComparison.assign_result(nil)
    |> assign_widget_data(frames_by_placement)
  end

  defp apply_live_tick_result(socket, result) do
    current_frames = RuntimeResult.frames_by_placement(result)

    merged_frames =
      merge_frames(socket.assigns.dashboard_engine_frames_by_placement, result)

    widget_frames = live_tick_widget_frames(current_frames, merged_frames)

    socket
    |> assign(:dashboard_engine_result, result)
    |> assign(:dashboard_engine_frames_by_placement, merged_frames)
    |> DataViewComparison.assign_result(nil)
    |> assign_widget_data(widget_frames)
  end

  defp merge_frames(previous_frames, result) when is_map(previous_frames) do
    Map.merge(previous_frames, RuntimeResult.frames_by_placement(result), fn
      _placement_id, previous, current ->
        merge_placement_frames(previous, current)
    end)
  end

  defp merge_frames(_previous_frames, result),
    do: RuntimeResult.frames_by_placement(result)

  defp merge_placement_frames(%PlacementFrames{} = previous, %PlacementFrames{} = current) do
    %PlacementFrames{
      current
      | primary: merge_primary_frames(previous.primary, current.primary),
        overlays: merge_overlay_frames(previous.overlays, current.overlays),
        warnings: if(current.warnings == [], do: previous.warnings, else: current.warnings)
    }
  end

  defp merge_primary_frames(previous, []), do: previous

  defp merge_primary_frames([%Frame{shape: :wide} | _rest] = previous, [
         %Frame{shape: :scalar} | _current_rest
       ]) do
    previous
  end

  defp merge_primary_frames(_previous, current), do: current

  defp merge_overlay_frames(previous, current) do
    Map.merge(previous, current, fn _role, previous_frames, current_frames ->
      if current_frames == [], do: previous_frames, else: current_frames
    end)
  end

  defp live_tick_widget_frames(current_frames, merged_frames) do
    Map.merge(merged_frames, current_frames, fn _placement_id, merged, current ->
      if current.primary == [], do: merged, else: current
    end)
  end

  defp assign_widget_data(socket, frames_by_placement) do
    active_ids = MapSet.new(Enum.map(socket.assigns.dashboard_render_items, & &1.placement_id))

    engine_data =
      socket.assigns.dashboard_render_items
      |> Map.new(fn item ->
        data = WidgetData.data(nil, frames_by_placement[item.placement_id], item.widget)
        {item.placement_id, data}
      end)
      |> Enum.reject(fn {_widget_id, data} -> is_nil(data) end)
      |> Map.new()

    widget_data =
      socket.assigns.widget_data
      |> Map.drop(stale_widget_ids(socket.assigns.widget_data, active_ids))
      |> Map.merge(engine_data)

    assign(socket, :widget_data, widget_data)
  end

  defp stale_widget_ids(widget_data, active_ids) do
    for {widget_id, data} <- widget_data,
        is_map(data),
        not MapSet.member?(active_ids, widget_id),
        do: widget_id
  end
end
