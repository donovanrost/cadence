defmodule Cadence.Dashboards.RuntimeCache do
  @moduledoc """
  ETS-backed runtime cache for dashboard engine runtime artifacts.

  v0 stores resolved plan results, source-result entries, and materialized
  frames. Invalidation metadata indexes both single-binding and segmented
  source identities so domain writes can evict affected runtime artifacts.
  """

  use GenServer

  require Logger

  alias Cadence.Dashboards.{DashboardResolveResult, Frame, RuntimeCacheKey, SourceResult}

  @default_call_timeout_ms 1_000

  @enforce_keys [:server, :call_timeout_ms]
  defstruct [:server, :call_timeout_ms]

  @source_result_live_lineage_fields [
    :cache_policy,
    :organization_id,
    :mission_id,
    :request_id,
    :logical_source,
    :observables,
    :time_context,
    :replay_run_id,
    :source_binding_ids,
    :data_source_ids,
    :realms,
    :datasets
  ]

  @frame_live_lineage_fields @source_result_live_lineage_fields ++
                               [
                                 :placement_id,
                                 :placement_size,
                                 :display,
                                 :frame_shape,
                                 :limit_context,
                                 :catalog_revision
                               ]

  @type server :: GenServer.server()
  @type t :: %__MODULE__{server: server(), call_timeout_ms: pos_integer()}
  @type client :: t() | server()
  @type invalidation_filters :: keyword() | map()

  @doc """
  Builds an immutable cache client from an explicit server and timeout policy.

  Callers that own a runtime composition should retain this value and pass it
  through every cache operation. `configured_client/1` is the narrow
  compatibility constructor for application boundaries that still own config.
  """
  @spec client(server(), keyword()) :: t()
  def client(server, opts \\ []) when is_list(opts) do
    %__MODULE__{
      server: server,
      call_timeout_ms:
        opts
        |> Keyword.get(:call_timeout_ms, @default_call_timeout_ms)
        |> normalize_call_timeout()
    }
  end

  @spec configured_client(server()) :: t()
  def configured_client(server \\ __MODULE__) do
    config = Application.get_env(:cadence, :dashboard_runtime_cache, [])
    client(server, config)
  end

  @spec server(t()) :: server()
  def server(%__MODULE__{server: server}), do: server

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, opts)
    else
      GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec get_plan(RuntimeCacheKey.t()) :: {:ok, DashboardResolveResult.t()} | :miss
  def get_plan(%RuntimeCacheKey{} = key), do: get_plan(key, configured_client())

  @spec get_plan(RuntimeCacheKey.t(), client()) :: {:ok, DashboardResolveResult.t()} | :miss
  def get_plan(%RuntimeCacheKey{layer: :plan} = key, cache) do
    cache_call(cache, {:get, :plan, key.fingerprint}, :miss)
  end

  @spec put_plan(RuntimeCacheKey.t(), DashboardResolveResult.t()) :: :ok
  def put_plan(%RuntimeCacheKey{} = key, %DashboardResolveResult{} = result) do
    put_plan(key, result, configured_client())
  end

  @spec put_plan(RuntimeCacheKey.t(), DashboardResolveResult.t(), client()) :: :ok
  def put_plan(
        %RuntimeCacheKey{layer: :plan} = key,
        %DashboardResolveResult{} = result,
        cache
      ) do
    cache_call(cache, {:put, :plan, key, result}, :ok)
  end

  @spec get_source_result(RuntimeCacheKey.t()) :: {:ok, SourceResult.t()} | :miss
  def get_source_result(%RuntimeCacheKey{} = key),
    do: get_source_result(key, configured_client())

  @spec get_source_result(RuntimeCacheKey.t(), client()) :: {:ok, SourceResult.t()} | :miss
  def get_source_result(%RuntimeCacheKey{layer: :source_result} = key, cache) do
    cache_call(cache, {:get, :source_result, key.fingerprint}, :miss)
  end

  @spec put_source_result(RuntimeCacheKey.t(), SourceResult.t()) :: :ok
  def put_source_result(%RuntimeCacheKey{} = key, %SourceResult{} = result) do
    put_source_result(key, result, configured_client())
  end

  @spec put_source_result(RuntimeCacheKey.t(), SourceResult.t(), client()) :: :ok
  def put_source_result(
        %RuntimeCacheKey{layer: :source_result} = key,
        %SourceResult{} = result,
        cache
      ) do
    cache_call(cache, {:put, :source_result, key, result}, :ok)
  end

  @spec get_frame(RuntimeCacheKey.t()) :: {:ok, [Frame.t()]} | :miss
  def get_frame(%RuntimeCacheKey{} = key), do: get_frame(key, configured_client())

  @spec get_frame(RuntimeCacheKey.t(), client()) :: {:ok, [Frame.t()]} | :miss
  def get_frame(%RuntimeCacheKey{layer: :frame} = key, cache) do
    cache_call(cache, {:get, :frame, key.fingerprint}, :miss)
  end

  @spec put_frame(RuntimeCacheKey.t(), [Frame.t()]) :: :ok
  def put_frame(%RuntimeCacheKey{} = key, frames) when is_list(frames) do
    put_frame(key, frames, configured_client())
  end

  @spec put_frame(RuntimeCacheKey.t(), [Frame.t()], client()) :: :ok
  def put_frame(%RuntimeCacheKey{layer: :frame} = key, frames, cache)
      when is_list(frames) do
    cache_call(cache, {:put, :frame, key, frames}, :ok)
  end

  @spec invalidate_plans(invalidation_filters()) :: {:ok, non_neg_integer()}
  def invalidate_plans(filters) when is_list(filters) or is_map(filters) do
    invalidate_plans(configured_client(), filters)
  end

  @spec invalidate_plans(client(), invalidation_filters()) :: {:ok, non_neg_integer()}
  def invalidate_plans(cache, filters) when is_list(filters) or is_map(filters) do
    cache_call(cache, {:invalidate, :plan, normalize_filters(filters)}, {:ok, 0})
  end

  @spec invalidate_source_results(invalidation_filters()) :: {:ok, non_neg_integer()}
  def invalidate_source_results(filters) when is_list(filters) or is_map(filters) do
    invalidate_source_results(configured_client(), filters)
  end

  @spec invalidate_source_results(client(), invalidation_filters()) :: {:ok, non_neg_integer()}
  def invalidate_source_results(cache, filters) when is_list(filters) or is_map(filters) do
    cache_call(cache, {:invalidate, :source_result, normalize_filters(filters)}, {:ok, 0})
  end

  @spec invalidate_frames(invalidation_filters()) :: {:ok, non_neg_integer()}
  def invalidate_frames(filters) when is_list(filters) or is_map(filters) do
    invalidate_frames(configured_client(), filters)
  end

  @spec invalidate_frames(client(), invalidation_filters()) :: {:ok, non_neg_integer()}
  def invalidate_frames(cache, filters) when is_list(filters) or is_map(filters) do
    cache_call(cache, {:invalidate, :frame, normalize_filters(filters)}, {:ok, 0})
  end

  @spec reset() :: :ok
  def reset, do: reset(configured_client())

  @spec reset(client()) :: :ok
  def reset(cache), do: cache_call(cache, :reset, :ok)

  @impl true
  def init(_opts) do
    table =
      :ets.new(__MODULE__, [
        :set,
        :protected,
        read_concurrency: true,
        write_concurrency: true
      ])

    live_index =
      :ets.new(__MODULE__, [
        :set,
        :private
      ])

    {:ok, %{live_index: live_index, table: table}}
  end

  @impl true
  def handle_call({:get, layer, fingerprint}, _from, %{table: table} = state) do
    case :ets.lookup(table, {layer, fingerprint}) do
      [{{^layer, ^fingerprint}, %{value: value}}] -> {:reply, {:ok, value}, state}
      [] -> {:reply, :miss, state}
    end
  end

  def handle_call(
        {:put, layer, %RuntimeCacheKey{} = key, value},
        _from,
        %{live_index: live_index, table: table} = state
      ) do
    metadata = cache_metadata(layer, key, value)
    prune_superseded_live_entry(table, live_index, layer, key.fingerprint, metadata)

    entry = %{value: value, metadata: metadata}
    true = :ets.insert(table, {{layer, key.fingerprint}, entry})
    index_live_entry(live_index, layer, key.fingerprint, metadata)
    {:reply, :ok, state}
  end

  def handle_call(
        {:invalidate, layer, filters},
        _from,
        %{live_index: live_index, table: table} = state
      ) do
    deleted =
      table
      |> entries_for_layer(layer)
      |> Enum.filter(fn {_fingerprint, metadata} -> metadata_matches?(metadata, filters) end)
      |> Enum.reduce(0, fn {fingerprint, metadata}, count ->
        delete_entry(table, live_index, layer, fingerprint, metadata)
        count + 1
      end)

    {:reply, {:ok, deleted}, state}
  end

  def handle_call(:reset, _from, %{live_index: live_index, table: table} = state) do
    true = :ets.delete_all_objects(table)
    true = :ets.delete_all_objects(live_index)
    {:reply, :ok, state}
  end

  defp cache_call(cache, request, fallback) do
    client = normalize_client(cache)

    case server_pid(client.server) do
      nil ->
        fallback

      _pid ->
        try do
          GenServer.call(client.server, request, client.call_timeout_ms)
        catch
          :exit, reason ->
            Logger.warning(
              "Dashboard runtime cache #{cache_operation(request)} failed open: " <>
                inspect(reason, limit: 10)
            )

            fallback
        end
    end
  end

  defp normalize_client(%__MODULE__{} = client), do: client
  defp normalize_client(server), do: client(server)

  defp normalize_call_timeout(value) when is_integer(value) and value > 0, do: value
  defp normalize_call_timeout(_value), do: @default_call_timeout_ms

  defp cache_operation({operation, _layer, _value}), do: operation
  defp cache_operation({operation, _layer, _key, _value}), do: operation
  defp cache_operation(operation), do: operation

  defp server_pid(server) do
    cond do
      is_pid(server) and Process.alive?(server) ->
        server

      is_pid(server) ->
        nil

      true ->
        case GenServer.whereis(server) do
          pid when is_pid(pid) -> pid
          nil -> nil
        end
    end
  end

  defp entries_for_layer(table, layer) do
    :ets.select(table, [
      {{{layer, :"$1"}, %{metadata: :"$2"}}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  defp prune_superseded_live_entry(table, live_index, layer, fingerprint, metadata) do
    case live_lineage(layer, metadata) do
      nil ->
        :ok

      lineage ->
        case :ets.lookup(live_index, lineage) do
          [{^lineage, {previous_layer, previous_fingerprint}}]
          when previous_layer != layer or previous_fingerprint != fingerprint ->
            true = :ets.delete(table, {previous_layer, previous_fingerprint})
            true = :ets.delete(live_index, lineage)

          _other ->
            :ok
        end
    end
  end

  defp index_live_entry(live_index, layer, fingerprint, metadata) do
    case live_lineage(layer, metadata) do
      nil -> :ok
      lineage -> true = :ets.insert(live_index, {lineage, {layer, fingerprint}})
    end
  end

  defp delete_entry(table, live_index, layer, fingerprint, metadata) do
    key = {layer, fingerprint}
    true = :ets.delete(table, key)

    case live_lineage(layer, metadata) do
      nil ->
        :ok

      lineage ->
        case :ets.lookup(live_index, lineage) do
          [{^lineage, ^key}] -> true = :ets.delete(live_index, lineage)
          _other -> :ok
        end
    end
  end

  defp live_lineage(:source_result, %{cache_policy: :live} = metadata) do
    {:source_result, Map.take(metadata, @source_result_live_lineage_fields)}
  end

  defp live_lineage(:frame, %{cache_policy: :live} = metadata) do
    {:frame, Map.take(metadata, @frame_live_lineage_fields)}
  end

  defp live_lineage(_layer, _metadata), do: nil

  defp cache_metadata(:plan, _key, %DashboardResolveResult{} = result) do
    plan_key = get_in(result.plan_metadata, [:cache, :plan_key])

    %{
      dashboard_id: result.dashboard_id,
      organization_id: get_in(plan_key_parts(plan_key), [:organization_id]),
      mission_id: get_in(plan_key_parts(plan_key), [:mission_id]),
      document_version: get_in(plan_key_parts(plan_key), [:document, :document_version]),
      document_schema_version: get_in(plan_key_parts(plan_key), [:document, :schema_version]),
      widget_registry_version: get_in(plan_key_parts(plan_key), [:widget_registry_version]),
      source_capability_version: get_in(plan_key_parts(plan_key), [:source_capability_version]),
      logical_sources:
        result.planned_source_requests
        |> Enum.map(& &1.logical_source)
        |> Enum.uniq()
        |> Enum.sort(),
      observables:
        result.planned_source_requests
        |> Enum.flat_map(& &1.observables)
        |> Enum.uniq()
        |> Enum.sort()
    }
  end

  defp cache_metadata(:source_result, %RuntimeCacheKey{parts: parts}, %SourceResult{} = result) do
    request = Map.get(parts, :request, %{})
    source_binding = parts |> Map.get(:source_binding) |> ensure_map()
    source_binding_segments = parts |> Map.get(:source_binding_segments, []) |> segment_maps()
    data_source = parts |> Map.get(:data_source) |> ensure_map()
    watermark_cursor = Map.get(parts, :watermark_cursor)

    source_binding_ids =
      source_binding_ids(source_binding, source_binding_segments, watermark_cursor)

    data_source_ids =
      data_source_ids(data_source, source_binding, source_binding_segments, watermark_cursor)

    realms =
      identity_values([
        Map.get(source_binding, :realm),
        segment_attrs(source_binding_segments, :realm),
        watermark_attr(watermark_cursor, :realm)
      ])

    datasets =
      identity_values([
        Map.get(source_binding, :dataset),
        segment_attrs(source_binding_segments, :dataset),
        watermark_attr(watermark_cursor, :dataset)
      ])

    data_binding_event_ids =
      identity_values([
        Map.get(source_binding, :current_event_id),
        segment_attrs(source_binding_segments, :data_binding_event_id)
      ])

    %{
      request_id: Map.get(request, :request_id) || result.request_id,
      cache_policy: Map.get(parts, :cache_policy, :live),
      organization_id: Map.get(request, :organization_id),
      mission_id: Map.get(request, :mission_id),
      logical_source: Map.get(request, :logical_source),
      logical_sources: [Map.get(request, :logical_source)] |> Enum.reject(&is_nil/1),
      observables: Map.get(request, :observables, []) |> Enum.sort(),
      time_context: Map.get(request, :time_context),
      requested_time_range: requested_time_range(Map.get(request, :time_context)),
      replay_run_id: replay_run_id(request),
      source_binding_id: single_identity(source_binding_ids),
      source_binding_ids: source_binding_ids,
      data_binding_event_ids: data_binding_event_ids,
      data_source_id: single_identity(data_source_ids),
      data_source_ids: data_source_ids,
      realm: single_identity(realms),
      realms: realms,
      dataset: single_identity(datasets),
      datasets: datasets,
      source_binding_segments: source_binding_segments,
      watermark_cursor: watermark_cursor,
      telemetry_revision_dependency: source_result_telemetry_revision_dependency(result),
      observation_identity_ids:
        observation_identity_ids(source_result_telemetry_revision_dependency(result)),
      watermark_confidence:
        watermark_attr(watermark_cursor, :confidence) || first_watermark_attr(result, :confidence),
      watermark_freshness_state:
        watermark_attr(watermark_cursor, :freshness_state) ||
          first_watermark_attr(result, :freshness_state)
    }
  end

  defp cache_metadata(:frame, %RuntimeCacheKey{parts: parts}, frames) when is_list(frames) do
    request = Map.get(parts, :source_result_request, %{})
    binding = parts |> Map.get(:source_result_binding) |> ensure_map()
    binding_segments = parts |> Map.get(:source_result_binding_segments, []) |> segment_maps()
    data_source = parts |> Map.get(:source_result_data_source) |> ensure_map()
    logical_source = Map.get(request, :logical_source) || first_frame_attr(frames, :source)
    source_binding_ids = source_binding_ids(binding, binding_segments, nil)
    data_source_ids = data_source_ids(data_source, binding, binding_segments, nil)
    realms = identity_values([Map.get(binding, :realm), segment_attrs(binding_segments, :realm)])

    datasets =
      identity_values([Map.get(binding, :dataset), segment_attrs(binding_segments, :dataset)])

    data_binding_event_ids =
      identity_values([
        Map.get(binding, :current_event_id),
        segment_attrs(binding_segments, :data_binding_event_id)
      ])

    %{
      cache_policy: Map.get(parts, :cache_policy, :live),
      source_result_fingerprint: Map.get(parts, :source_result_fingerprint),
      placement_id: Map.get(parts, :placement_id),
      placement_size: Map.get(parts, :placement_size, %{}),
      display: Map.get(parts, :display, %{}),
      frame_shape: Map.get(parts, :frame_shape) || first_frame_attr(frames, :shape),
      limit_context: Map.get(parts, :limit_context),
      catalog_revision: Map.get(parts, :catalog_revision),
      telemetry_revision_dependency: Map.get(parts, :telemetry_revision_dependency),
      observation_identity_ids:
        observation_identity_ids(Map.get(parts, :telemetry_revision_dependency)),
      request_id: Map.get(request, :request_id),
      organization_id: Map.get(request, :organization_id) || Map.get(binding, :organization_id),
      mission_id: Map.get(request, :mission_id) || Map.get(binding, :mission_id),
      logical_source: logical_source,
      logical_sources: [logical_source] |> Enum.reject(&is_nil/1),
      observables: Map.get(request, :observables, []) |> Enum.sort(),
      time_context: Map.get(request, :time_context),
      requested_time_range: requested_time_range(Map.get(request, :time_context)),
      replay_run_id: replay_run_id(request),
      source_binding_id: single_identity(source_binding_ids),
      source_binding_ids: source_binding_ids,
      data_binding_event_ids: data_binding_event_ids,
      data_source_id: single_identity(data_source_ids),
      data_source_ids: data_source_ids,
      realm: single_identity(realms),
      realms: realms,
      dataset: single_identity(datasets),
      datasets: datasets,
      source_binding_segments: binding_segments
    }
  end

  defp cache_metadata(_layer, _key, _value), do: %{}

  defp plan_key_parts(%RuntimeCacheKey{parts: parts}), do: parts
  defp plan_key_parts(_key), do: %{}

  defp normalize_filters(filters) when is_list(filters), do: Map.new(filters)
  defp normalize_filters(filters) when is_map(filters), do: filters

  defp metadata_matches?(_metadata, filters) when map_size(filters) == 0 do
    true
  end

  defp metadata_matches?(metadata, filters) do
    Enum.all?(filters, fn
      {:logical_source, logical_source} ->
        logical_source in Map.get(metadata, :logical_sources, [])

      {"logical_source", logical_source} ->
        logical_source in Map.get(metadata, :logical_sources, [])

      {:observable, observable} ->
        observable in Map.get(metadata, :observables, [])

      {"observable", observable} ->
        observable in Map.get(metadata, :observables, [])

      {:observation_identity_id, observation_identity_id} ->
        observation_identity_id in Map.get(metadata, :observation_identity_ids, [])

      {"observation_identity_id", observation_identity_id} ->
        observation_identity_id in Map.get(metadata, :observation_identity_ids, [])

      {:time_range, time_range} ->
        time_ranges_overlap?(Map.get(metadata, :requested_time_range), time_range)

      {"time_range", time_range} ->
        time_ranges_overlap?(Map.get(metadata, :requested_time_range), time_range)

      {:requested_time_range, time_range} ->
        time_ranges_overlap?(Map.get(metadata, :requested_time_range), time_range)

      {"requested_time_range", time_range} ->
        time_ranges_overlap?(Map.get(metadata, :requested_time_range), time_range)

      {:source_binding_id, source_binding_id} ->
        identity_matches?(metadata, :source_binding_id, :source_binding_ids, source_binding_id)

      {"source_binding_id", source_binding_id} ->
        identity_matches?(metadata, :source_binding_id, :source_binding_ids, source_binding_id)

      {:binding_id, source_binding_id} ->
        identity_matches?(metadata, :source_binding_id, :source_binding_ids, source_binding_id)

      {"binding_id", source_binding_id} ->
        identity_matches?(metadata, :source_binding_id, :source_binding_ids, source_binding_id)

      {:data_source_id, data_source_id} ->
        identity_matches?(metadata, :data_source_id, :data_source_ids, data_source_id)

      {"data_source_id", data_source_id} ->
        identity_matches?(metadata, :data_source_id, :data_source_ids, data_source_id)

      {:source_id, data_source_id} ->
        identity_matches?(metadata, :data_source_id, :data_source_ids, data_source_id)

      {"source_id", data_source_id} ->
        identity_matches?(metadata, :data_source_id, :data_source_ids, data_source_id)

      {:data_binding_event_id, event_id} ->
        identity_matches?(metadata, nil, :data_binding_event_ids, event_id)

      {"data_binding_event_id", event_id} ->
        identity_matches?(metadata, nil, :data_binding_event_ids, event_id)

      {:realm, realm} ->
        identity_matches?(metadata, :realm, :realms, realm)

      {"realm", realm} ->
        identity_matches?(metadata, :realm, :realms, realm)

      {:dataset, dataset} ->
        identity_matches?(metadata, :dataset, :datasets, dataset)

      {"dataset", dataset} ->
        identity_matches?(metadata, :dataset, :datasets, dataset)

      {key, value} ->
        Map.get(metadata, normalize_key(key)) == value
    end)
  end

  defp normalize_key("dashboard_id"), do: :dashboard_id
  defp normalize_key("organization_id"), do: :organization_id
  defp normalize_key("mission_id"), do: :mission_id
  defp normalize_key("document_version"), do: :document_version
  defp normalize_key("document_schema_version"), do: :document_schema_version
  defp normalize_key("widget_registry_version"), do: :widget_registry_version
  defp normalize_key("source_capability_version"), do: :source_capability_version
  defp normalize_key("request_id"), do: :request_id
  defp normalize_key("cache_policy"), do: :cache_policy
  defp normalize_key("source_id"), do: :data_source_id
  defp normalize_key("binding_id"), do: :source_binding_id
  defp normalize_key("source_binding_id"), do: :source_binding_id
  defp normalize_key("data_source_id"), do: :data_source_id
  defp normalize_key("realm"), do: :realm
  defp normalize_key("dataset"), do: :dataset
  defp normalize_key("time_context"), do: :time_context
  defp normalize_key("time_range"), do: :time_range
  defp normalize_key("requested_time_range"), do: :requested_time_range
  defp normalize_key("replay_run_id"), do: :replay_run_id
  defp normalize_key("watermark_cursor"), do: :watermark_cursor
  defp normalize_key("watermark_confidence"), do: :watermark_confidence
  defp normalize_key("watermark_freshness_state"), do: :watermark_freshness_state
  defp normalize_key("source_result_fingerprint"), do: :source_result_fingerprint
  defp normalize_key("placement_id"), do: :placement_id
  defp normalize_key("placement_size"), do: :placement_size
  defp normalize_key("display"), do: :display
  defp normalize_key("frame_shape"), do: :frame_shape
  defp normalize_key("limit_context"), do: :limit_context
  defp normalize_key("catalog_revision"), do: :catalog_revision
  defp normalize_key("telemetry_revision_dependency"), do: :telemetry_revision_dependency
  defp normalize_key("observation_identity_id"), do: :observation_identity_id
  defp normalize_key(key), do: key

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp segment_maps(segments) when is_list(segments) do
    Enum.filter(segments, &is_map/1)
  end

  defp segment_maps(_segments), do: []

  defp source_binding_ids(source_binding, segments, watermark_cursor) do
    identity_values([
      Map.get(source_binding, :binding_id),
      segment_attrs(segments, :binding_id),
      watermark_attr(watermark_cursor, :source_binding_id)
    ])
  end

  defp data_source_ids(data_source, source_binding, segments, watermark_cursor) do
    identity_values([
      Map.get(data_source, :data_source_id),
      Map.get(source_binding, :data_source_id),
      segment_attrs(segments, :data_source_id),
      watermark_attr(watermark_cursor, :data_source_id)
    ])
  end

  defp segment_attrs(segments, key) do
    Enum.map(segments, &segment_attr(&1, key))
  end

  defp segment_attr(segment, key) when is_map(segment) and is_atom(key) do
    Map.get(segment, key) || Map.get(segment, Atom.to_string(key))
  end

  defp identity_values(values) do
    values
    |> List.wrap()
    |> Enum.flat_map(fn
      values when is_list(values) -> values
      value -> [value]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort_by(&inspect/1)
  end

  defp single_identity([value]), do: value
  defp single_identity(_values), do: nil

  defp identity_matches?(metadata, scalar_key, set_key, value) do
    requested_values = identity_values(value)

    metadata_values =
      []
      |> maybe_add_identity(Map.get(metadata, scalar_key))
      |> Kernel.++(Map.get(metadata, set_key, []))
      |> identity_values()

    requested_values != [] and Enum.any?(requested_values, &(&1 in metadata_values))
  end

  defp maybe_add_identity(values, nil), do: values
  defp maybe_add_identity(values, value), do: [value | values]

  defp watermark_attr(nil, _key), do: nil
  defp watermark_attr(watermark, key) when is_map(watermark), do: Map.get(watermark, key)

  defp first_watermark_attr(%SourceResult{watermarks: [watermark | _rest]}, key) do
    Map.get(watermark, key)
  end

  defp first_watermark_attr(%SourceResult{}, _key), do: nil

  defp first_frame_attr([%Frame{} = frame | _rest], key), do: Map.get(frame, key)
  defp first_frame_attr(_frames, _key), do: nil

  defp source_result_telemetry_revision_dependency(%SourceResult{meta: meta}) when is_map(meta) do
    Map.get(meta, :telemetry_revision_dependency)
  end

  defp source_result_telemetry_revision_dependency(%SourceResult{}), do: nil

  defp observation_identity_ids(%{observation_identity_ids: ids}) when is_list(ids) do
    ids
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp observation_identity_ids(%{"observation_identity_ids" => ids}) when is_list(ids) do
    observation_identity_ids(%{observation_identity_ids: ids})
  end

  defp observation_identity_ids(%{dependencies: dependencies}) when is_list(dependencies) do
    dependencies
    |> Enum.flat_map(&observation_identity_ids/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp observation_identity_ids(%{"dependencies" => dependencies}) when is_list(dependencies) do
    observation_identity_ids(%{dependencies: dependencies})
  end

  defp observation_identity_ids(_dependency), do: []

  defp requested_time_range(nil), do: nil

  defp requested_time_range(time_context) do
    from = first_context_value(time_context, [:from, :start, :start_time])
    to = first_context_value(time_context, [:to, :end, :end_time])

    if is_nil(from) and is_nil(to) do
      nil
    else
      %{
        axis: normalize_time_axis(context_value(time_context, :axis)),
        mode: normalize_time_mode(context_value(time_context, :mode)),
        from: from,
        to: to
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end
  end

  defp first_context_value(time_context, keys) do
    Enum.find_value(keys, &context_value(time_context, &1))
  end

  defp context_value(nil, _key), do: nil

  defp context_value(time_context, key) when is_map(time_context) do
    Map.get(time_context, key, Map.get(time_context, to_string(key)))
  end

  defp replay_run_id(request) when is_map(request) do
    context_value(Map.get(request, :data_context), :replay_run_id) ||
      context_value(Map.get(request, :time_context), :replay_run_id)
  end

  defp time_ranges_overlap?(requested_range, changed_range) do
    with {:ok, requested} <- normalize_time_range(requested_range),
         {:ok, changed} <- normalize_time_range(changed_range),
         true <- time_axes_compatible?(requested.axis, changed.axis),
         true <- valid_interval?(requested),
         true <- valid_interval?(changed) do
      intervals_overlap?(requested, changed)
    else
      _other -> false
    end
  end

  defp normalize_time_range(nil), do: :error

  defp normalize_time_range(range) when is_list(range) do
    if Keyword.keyword?(range), do: normalize_time_range(Map.new(range)), else: :error
  end

  defp normalize_time_range(range) when is_map(range) do
    from = range_attr(range, :from) || range_attr(range, :start) || range_attr(range, :start_time)
    to = range_attr(range, :to) || range_attr(range, :end) || range_attr(range, :end_time)
    axis = range_attr(range, :axis) |> normalize_time_axis()

    with true <- not (is_nil(from) and is_nil(to)),
         {:ok, from} <- normalize_time_bound(from),
         {:ok, to} <- normalize_time_bound(to) do
      {:ok, %{axis: axis, from: from, to: to}}
    else
      _other -> :error
    end
  end

  defp normalize_time_range(_range), do: :error

  defp range_attr(range, key) when is_map(range) do
    Map.get(range, key, Map.get(range, to_string(key)))
  end

  defp normalize_time_bound(nil), do: {:ok, nil}
  defp normalize_time_bound(%DateTime{} = value), do: {:ok, value}

  defp normalize_time_bound(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> :error
    end
  end

  defp normalize_time_bound(_value), do: :error

  defp time_axes_compatible?(nil, _changed_axis), do: true
  defp time_axes_compatible?(_requested_axis, nil), do: true
  defp time_axes_compatible?(axis, axis), do: true
  defp time_axes_compatible?(_requested_axis, _changed_axis), do: false

  defp valid_interval?(%{from: %DateTime{} = from, to: %DateTime{} = to}) do
    DateTime.compare(from, to) != :gt
  end

  defp valid_interval?(_range), do: true

  defp intervals_overlap?(left, right) do
    starts_before_or_at_end?(left.from, right.to) and
      starts_before_or_at_end?(right.from, left.to)
  end

  defp starts_before_or_at_end?(nil, _right_to), do: true
  defp starts_before_or_at_end?(_left_from, nil), do: true

  defp starts_before_or_at_end?(%DateTime{} = left_from, %DateTime{} = right_to) do
    DateTime.compare(left_from, right_to) != :gt
  end

  defp normalize_time_axis(value) when value in [:generation_time, "generation_time"],
    do: :generation_time

  defp normalize_time_axis(value) when value in [:receipt_time, "receipt_time"], do: :receipt_time
  defp normalize_time_axis(value) when value in [:occurred_at, "occurred_at"], do: :occurred_at
  defp normalize_time_axis(value), do: value

  defp normalize_time_mode(value) when value in [:live, "live"], do: :live
  defp normalize_time_mode(value) when value in [:archive, "archive"], do: :archive
  defp normalize_time_mode(value) when value in [:range, "range"], do: :range
  defp normalize_time_mode(value) when value in [:replay_run, "replay_run"], do: :replay_run
  defp normalize_time_mode(value), do: value
end
