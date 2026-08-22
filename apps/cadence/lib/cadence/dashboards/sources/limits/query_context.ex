defmodule Cadence.Dashboards.Sources.Limits.QueryContext do
  @moduledoc """
  Builds provider query options and watermark evidence for the limits source.

  This module translates dashboard time, source, and telemetry contexts into
  the bounded read options consumed by limit and telemetry providers.
  """

  alias Cadence.Dashboards.{
    DataContext,
    DataLinks,
    DataSourceRegistry,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    ScopeContext
  }

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.Dashboards.Sources.Limits.RecomputedAnalysis
  alias Cadence.Limits.{DefinitionInterval, Event}
  alias Cadence.Reads.Limits, as: LimitReads

  @default_event_limit 1_000

  @spec latest_opts(PlannedSourceRequest.t(), term()) :: keyword()
  def latest_opts(%PlannedSourceRequest{} = request, source_binding) do
    [
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
      data_source_id: data_source_id(request, source_binding),
      dataset: dataset(source_binding),
      semantics_mode: RecomputedAnalysis.semantics_mode(request),
      spacecraft_id: spacecraft_id(request.scope_context),
      to_receipt_time: latest_as_of_receipt_time(request)
    ]
    |> compact_opts()
  end

  @spec latest_sample_opts(PlannedSourceRequest.t(), term(), keyword()) :: keyword()
  def latest_sample_opts(%PlannedSourceRequest{} = request, source_binding, adapter_opts) do
    request
    |> latest_opts(source_binding)
    |> put_telemetry_sample_source_context(request, adapter_opts)
  end

  @spec history_opts(PlannedSourceRequest.t(), term()) :: {keyword(), [ResolveWarning.t()]}
  def history_opts(%PlannedSourceRequest{} = request, source_binding) do
    {from_receipt_time, to_receipt_time, time_warnings, order} =
      event_history_time_options(request)

    opts =
      [
        realm: realm(request, source_binding),
        replay_run_id: replay_run_id(request),
        data_source_id: data_source_id(request, source_binding),
        dataset: dataset(source_binding),
        semantics_mode: RecomputedAnalysis.semantics_mode(request),
        spacecraft_id: spacecraft_id(request.scope_context),
        from_receipt_time: from_receipt_time,
        to_receipt_time: to_receipt_time,
        limit: event_limit(request),
        order: order
      ]
      |> compact_opts()

    {opts, time_warnings}
  end

  @spec sample_history_opts(PlannedSourceRequest.t(), term(), keyword()) :: keyword()
  def sample_history_opts(%PlannedSourceRequest{} = request, source_binding, adapter_opts) do
    {opts, _time_warnings} = history_opts(request, source_binding)

    put_telemetry_sample_source_context(opts, request, adapter_opts)
  end

  @spec interval_opts(PlannedSourceRequest.t(), term()) :: {keyword(), [ResolveWarning.t()]}
  def interval_opts(%PlannedSourceRequest{} = request, source_binding) do
    {from_receipt_time, to_receipt_time, time_warnings, _order} =
      event_history_time_options(request)

    opts =
      [
        realm: realm(request, source_binding),
        replay_run_id: replay_run_id(request),
        data_source_id: data_source_id(request, source_binding),
        dataset: dataset(source_binding),
        semantics_mode: RecomputedAnalysis.semantics_mode(request),
        from_receipt_time: from_receipt_time,
        to_receipt_time: to_receipt_time
      ]
      |> compact_opts()

    {opts, time_warnings}
  end

  @spec selected_definition_intervals(
          PlannedSourceRequest.t(),
          term(),
          binary() | nil,
          binary(),
          binary(),
          Event.t() | [Event.t()] | nil,
          keyword()
        ) :: [DefinitionInterval.t()]
  def selected_definition_intervals(
        %PlannedSourceRequest{} = request,
        source_binding,
        organization_id,
        mission_id,
        observable_id,
        events_or_event,
        opts
      ) do
    event_times = limit_event_receipt_times(events_or_event)

    with true <- event_times != [],
         interval_fun when is_function(interval_fun, 4) <- selected_interval_fun(opts) do
      {query_opts, _time_warnings} = interval_opts(request, source_binding)

      interval_fun.(organization_id, mission_id, observable_id, query_opts)
      |> Enum.filter(&interval_selected_for_times?(&1, event_times))
      |> Enum.uniq_by(& &1.definition_activation_key)
    else
      _other -> []
    end
  end

  @spec selected_recompute_intervals(
          PlannedSourceRequest.t(),
          term(),
          function(),
          binary() | nil,
          binary(),
          binary()
        ) :: [DefinitionInterval.t()]
  def selected_recompute_intervals(
        %PlannedSourceRequest{} = request,
        source_binding,
        interval_fun,
        organization_id,
        mission_id,
        observable_id
      ) do
    {query_opts, _time_warnings} = interval_opts(request, source_binding)

    interval_fun.(organization_id, mission_id, observable_id, query_opts)
    |> Enum.filter(& &1.complete?)
    |> Enum.sort_by(&interval_sort_key/1, {:desc, DateTime})
  end

  @spec latest_time_warnings(PlannedSourceRequest.t()) :: [ResolveWarning.t()]
  def latest_time_warnings(%PlannedSourceRequest{} = request) do
    cond do
      not time_range_requested?(request.time_context) ->
        []

      latest_as_of_supported?(request) ->
        []

      true ->
        [
          warning(
            request,
            :time_range_ignored,
            :warning,
            "Latest limit-state archive requests require a receipt-time upper bound for as-of resolution",
            %{
              requested_time_mode: context_value(request.time_context, :mode),
              requested_axis: time_axis(request),
              fallback: :latest_projection
            }
          )
        ]
    end
  end

  @spec watermark_for_request(
          PlannedSourceRequest.t(),
          term(),
          binary() | nil,
          binary(),
          keyword()
        ) :: SourceWatermark.t()
  def watermark_for_request(
        %PlannedSourceRequest{} = request,
        source_binding,
        organization_id,
        mission_id,
        opts
      ) do
    case RecomputedAnalysis.semantics_mode(request) do
      :observed -> watermark(request, source_binding, organization_id, mission_id, opts)
      _semantics_mode -> unknown_watermark(request, source_binding)
    end
  end

  defp event_history_time_options(%PlannedSourceRequest{} = request) do
    requested_axis = time_axis(request)
    from_time = first_context_value(request.time_context, [:from, :start, :start_time])
    to_time = first_context_value(request.time_context, [:to, :end, :end_time])

    warnings =
      if requested_axis in [nil, :receipt_time] do
        []
      else
        [
          warning(
            request,
            :unsupported_time_axis,
            :info,
            "Limits event history is ordered by receipt time in v0",
            %{requested_axis: requested_axis, fallback_axis: :receipt_time}
          )
        ]
      end

    {from_time, to_time, warnings, :asc}
  end

  defp latest_as_of_receipt_time(%PlannedSourceRequest{} = request) do
    if latest_as_of_supported?(request) do
      first_context_value(request.time_context, [:to, :end, :end_time])
    end
  end

  defp latest_as_of_supported?(%PlannedSourceRequest{} = request) do
    requested_axis = time_axis(request)
    to_time = first_context_value(request.time_context, [:to, :end, :end_time])

    not is_nil(to_time) and requested_axis in [nil, :receipt_time]
  end

  defp selected_interval_fun(opts) do
    cond do
      interval_fun = Keyword.get(opts, :interval_fun) ->
        interval_fun

      Keyword.get(opts, :persisted?, false) == true ->
        &default_intervals/4

      true ->
        nil
    end
  end

  defp limit_event_receipt_times(events_or_event) do
    events_or_event
    |> List.wrap()
    |> Enum.map(fn
      %Event{receipt_time: %DateTime{} = receipt_time} -> receipt_time
      _other -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp interval_selected_for_times?(%DefinitionInterval{} = interval, event_times) do
    Enum.any?(event_times, &RecomputedAnalysis.interval_contains_time?(interval, &1))
  end

  defp interval_sort_key(%DefinitionInterval{active_from: %DateTime{} = active_from}),
    do: active_from

  defp interval_sort_key(%DefinitionInterval{}), do: DateTime.from_unix!(0)

  defp watermark(request, source_binding, organization_id, mission_id, opts) do
    if watermarks_supported?(source_binding) do
      watermark_fun = Keyword.get(opts, :watermark_fun, &default_watermark/4)
      query_opts = watermark_opts(request, source_binding)

      request.observables
      |> Enum.map(fn observable_id ->
        {observable_id, watermark_fun.(organization_id, mission_id, observable_id, query_opts)}
      end)
      |> request_watermark(request, source_binding)
    else
      unknown_watermark(request, source_binding)
    end
  end

  @spec unknown_watermark(PlannedSourceRequest.t(), term()) :: SourceWatermark.t()
  def unknown_watermark(%PlannedSourceRequest{} = request, source_binding) do
    %SourceWatermark{
      logical_source: :limits,
      request_id: request.request_id,
      source_binding_id: source_binding_id(source_binding),
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      dataset: dataset(source_binding),
      scope: request.scope_context,
      confidence: :unknown
    }
  end

  defp request_watermark(point_results, %PlannedSourceRequest{} = request, source_binding) do
    normalized_results =
      Enum.map(point_results, fn {observable_id, result} ->
        {observable_id, normalize_watermark_result(result)}
      end)

    point_watermarks = Map.new(normalized_results)

    if Enum.all?(normalized_results, fn {_observable_id, result} ->
         Map.get(result, :confidence) in [:authoritative, :best_effort]
       end) do
      %SourceWatermark{
        logical_source: :limits,
        request_id: request.request_id,
        source_binding_id: source_binding_id(source_binding),
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        dataset: dataset(source_binding),
        scope: request.scope_context,
        complete_through: minimum_datetime(normalized_results, :complete_through),
        latest_receipt_time: maximum_datetime(normalized_results, :latest_receipt_time),
        retention_starts_at: minimum_datetime(normalized_results, :retention_starts_at),
        confidence: :best_effort,
        meta: %{point_watermarks: point_watermarks}
      }
    else
      %SourceWatermark{
        unknown_watermark(request, source_binding)
        | meta: %{point_watermarks: point_watermarks}
      }
    end
  end

  defp normalize_watermark_result({:ok, result}) when is_map(result), do: result

  defp normalize_watermark_result({:error, reason}),
    do: %{confidence: :unknown, error: inspect(reason)}

  defp normalize_watermark_result(result) when is_map(result), do: result
  defp normalize_watermark_result(other), do: %{confidence: :unknown, error: inspect(other)}

  defp minimum_datetime(normalized_results, key) do
    normalized_results
    |> Enum.map(fn {_observable_id, result} -> Map.get(result, key) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(nil, &earlier_datetime/2)
  end

  defp maximum_datetime(normalized_results, key) do
    normalized_results
    |> Enum.map(fn {_observable_id, result} -> Map.get(result, key) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(nil, &later_datetime/2)
  end

  defp earlier_datetime(datetime, nil), do: datetime
  defp earlier_datetime(datetime, minimum), do: compare_datetime(datetime, minimum, :lt)
  defp later_datetime(datetime, nil), do: datetime
  defp later_datetime(datetime, maximum), do: compare_datetime(datetime, maximum, :gt)

  defp compare_datetime(datetime, other, comparison) do
    if DateTime.compare(datetime, other) == comparison, do: datetime, else: other
  end

  defp watermark_opts(%PlannedSourceRequest{} = request, source_binding) do
    [
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
      data_source_id: data_source_id(request, source_binding),
      dataset: dataset(source_binding),
      semantics_mode: RecomputedAnalysis.semantics_mode(request),
      spacecraft_id: spacecraft_id(request.scope_context)
    ]
    |> compact_opts()
  end

  defp watermarks_supported?(%{data_source: %{capabilities: capabilities}})
       when is_map(capabilities) do
    Map.get(capabilities, :watermarks?, Map.get(capabilities, "watermarks?")) == true
  end

  defp watermarks_supported?(_source_binding), do: false

  defp put_telemetry_sample_source_context(opts, request, adapter_opts) do
    if explicit_logical_source_context?(request, :telemetry) do
      put_logical_source_context(opts, request, :telemetry)
    else
      put_resolved_telemetry_source_context(opts, request, adapter_opts)
    end
  end

  defp put_logical_source_context(opts, request, logical_source) do
    [:realm, :data_source_id, :source_binding_id, :dataset, :replay_run_id]
    |> Enum.reduce(opts, fn key, acc ->
      case DataContext.source_value(request.data_context, logical_source, key) do
        value when value in [nil, ""] -> acc
        value -> Keyword.put(acc, key, value)
      end
    end)
  end

  defp put_resolved_telemetry_source_context(
         opts,
         %PlannedSourceRequest{} = request,
         adapter_opts
       ) do
    telemetry_request = %PlannedSourceRequest{request | logical_source: :telemetry}

    case DataSourceRegistry.resolve(telemetry_request, registry_opts(adapter_opts)) do
      {:ok, %ResolvedSourceBinding{} = resolved_binding} ->
        resolved_binding
        |> telemetry_source_opts(request)
        |> put_opts(opts)

      {:error, _warning} ->
        opts
    end
  end

  defp telemetry_source_opts(%ResolvedSourceBinding{} = resolved_binding, request) do
    [
      realm: resolved_binding.realm,
      data_source_id: resolved_binding.data_source.data_source_id,
      source_binding_id: resolved_binding.binding.binding_id,
      dataset: resolved_binding.dataset,
      replay_run_id: replay_run_id(request)
    ]
    |> compact_opts()
  end

  defp put_opts(source_opts, opts) do
    Enum.reduce(source_opts, opts, fn {key, value}, acc -> Keyword.put(acc, key, value) end)
  end

  defp registry_opts(adapter_opts) do
    Keyword.take(adapter_opts, [
      :data_sources,
      :data_bindings,
      :source_health_statuses,
      :persisted?,
      :source_binding_at,
      :source_binding_range
    ])
  end

  defp explicit_logical_source_context?(request, logical_source) do
    request.data_context
    |> source_context(logical_source)
    |> case do
      context when is_map(context) ->
        present_context_value?(context_value(context, :data_source_id)) or
          present_context_value?(context_value(context, :source_binding_id))

      _context ->
        false
    end
  end

  defp source_context(context, logical_source) do
    context
    |> DataContext.from_map()
    |> case do
      %DataContext{source_contexts: contexts} when is_map(contexts) ->
        Map.get(contexts, logical_source) || Map.get(contexts, Atom.to_string(logical_source))

      _context ->
        nil
    end
  end

  defp present_context_value?(value), do: value not in [nil, ""]

  defp source_binding_id(%{binding: %{binding_id: binding_id}}), do: binding_id
  defp source_binding_id(_source_binding), do: nil

  defp data_source_id(_request, %{data_source: %{data_source_id: data_source_id}}),
    do: data_source_id

  defp data_source_id(request, _source_binding),
    do: context_value(request.data_context, :data_source_id)

  defp dataset(%{dataset: dataset}), do: dataset
  defp dataset(_source_binding), do: nil

  defp realm(_request, %{realm: realm}), do: realm
  defp realm(request, _source_binding), do: context_value(request.data_context, :realm) || :flight

  defp replay_run_id(%PlannedSourceRequest{} = request) do
    DataContext.source_value(request.data_context, request.logical_source, :replay_run_id) ||
      context_value(request.time_context, :replay_run_id)
  end

  defp event_limit(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :limit) || context_value(sampling, :max_events) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_event_limit)
      _other -> @default_event_limit
    end
  end

  defp spacecraft_id(scope_context), do: ScopeContext.scope_id(scope_context, :spacecraft)

  defp time_axis(%PlannedSourceRequest{time_context: time_context}) do
    time_context |> context_value(:axis) |> normalize_atom()
  end

  defp time_range_requested?(time_context) do
    mode = time_context |> context_value(:mode) |> normalize_atom()

    mode in [:archive, :range] or
      not is_nil(first_context_value(time_context, [:from, :start, :start_time])) or
      not is_nil(first_context_value(time_context, [:to, :end, :end_time]))
  end

  defp warning(request, code, severity, message, details) do
    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: message,
      details: Map.put(details, :source_request_id, request.request_id),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp default_intervals(nil, mission_id, point_id, opts) do
    LimitReads.definition_intervals(mission_id, point_id, opts)
  end

  defp default_intervals(organization_id, mission_id, point_id, opts) do
    LimitReads.definition_intervals(organization_id, mission_id, point_id, opts)
  end

  defp default_watermark(nil, _mission_id, _point_id, _opts),
    do: {:error, :missing_tenant_context}

  defp default_watermark(organization_id, mission_id, point_id, opts) do
    LimitReads.watermark_result(organization_id, mission_id, point_id, opts)
  end

  defp compact_opts(opts), do: Enum.reject(opts, fn {_key, value} -> value in [nil, ""] end)

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    with :error <- Map.fetch(context, key),
         :error <- Map.fetch(context, Atom.to_string(key)) do
      nil
    else
      {:ok, value} -> value
    end
  end

  defp context_value(_context, _key), do: nil
  defp first_context_value(context, keys), do: Enum.find_value(keys, &context_value(context, &1))

  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> value
  end

  defp normalize_atom(value), do: value
end
