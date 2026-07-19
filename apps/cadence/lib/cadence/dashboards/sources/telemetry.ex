defmodule Cadence.Dashboards.Sources.Telemetry do
  @moduledoc """
  Dashboard telemetry source adapter.

  This first adapter slice supports latest telemetry values and bounded raw
  telemetry history over receipt time. It intentionally does not make the
  planner execute IO; callers pass a `PlannedSourceRequest` here after planning.
  """

  alias Cadence.Dashboards.{
    DataContext,
    DataSource,
    PlannedSourceRequest,
    ResolveWarning,
    SourceCapabilities,
    SourceFacts,
    SourceProbe,
    SourceResult,
    SourceWatermark
  }

  alias Cadence.Dashboards.Sources.Telemetry.{FrameBuilder, FrameContext, QueryOptions, Warnings}
  alias Cadence.Dashboards.Sources.Telemetry.HistoricalWorkflows
  alias Cadence.Dashboards.Sources.Telemetry.QuestDBProbe
  alias Cadence.Dashboards.Sources.Telemetry.RevisionState
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Telemetry.Sample

  @history_sampling_modes [:raw_series, :bounded_history, :bounded_raw_series]
  @native_decimated_sampling_modes [:decimated_envelope]
  @supported_sampling_modes [:latest | @history_sampling_modes]
  @type decimated_history_fun :: (binary() | nil, binary(), binary(), keyword() ->
                                    [map()] | {:ok, map()} | map() | {:error, term()})
  @type history_fun :: (binary() | nil, binary(), binary(), keyword() ->
                          [Sample.t()] | {:ok, map()} | map() | {:error, term()})
  @type latest_fun :: (binary() | nil, binary(), binary(), keyword() -> Sample.t() | nil)
  @type watermark_fun :: (binary() | nil, binary(), binary(), keyword() ->
                            {:ok, map()} | {:error, term()} | map())

  @spec capabilities() :: SourceCapabilities.t()
  def capabilities do
    SourceCapabilities.new(%{
      logical_source: :telemetry,
      supported_sampling: @supported_sampling_modes,
      supported_products: [
        :latest_value,
        :bounded_receipt_time_history,
        :bounded_generation_time_history
      ],
      supported_time_axes: [:generation_time, :receipt_time],
      supported_value_types: [:raw, :engineering],
      supported_shapes: [:scalar, :wide],
      supports_watermarks?: false,
      completeness: :unknown
    })
  end

  @spec probe(DataSource.t(), keyword()) :: SourceProbe.t()
  def probe(%DataSource{} = data_source, opts \\ []) when is_list(opts) do
    case metadata_value(data_source.metadata, :storage) do
      storage when storage in [:questdb, "questdb"] ->
        QuestDBProbe.probe(data_source, opts)

      storage ->
        SourceProbe.unsupported(%{
          adapter: "telemetry",
          storage: storage || "unknown",
          reason: "telemetry adapter only has a live probe for QuestDB-backed sources"
        })
    end
  end

  @spec facts(PlannedSourceRequest.t(), keyword()) ::
          {:ok, SourceFacts.t()} | {:error, ResolveWarning.t()}
  def facts(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    source_binding = Keyword.get(opts, :source_binding)

    with :ok <- ensure_telemetry_source(request),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id),
         :ok <- ensure_observables(request.observables) do
      watermark = watermark(request, source_binding, organization_id, mission_id, opts)

      {:ok,
       SourceFacts.new(%{
         source_binding: source_binding && source_binding.binding,
         data_source: source_binding && source_binding.data_source,
         watermark: watermark,
         data_revision: Keyword.get(opts, :data_revision),
         correction_cursor: Keyword.get(opts, :correction_cursor),
         backfill_cursor: Keyword.get(opts, :backfill_cursor),
         source_health: Keyword.get(opts, :source_health, :healthy),
         meta: %{
           logical_source: :telemetry,
           source_binding_id: source_binding_id(source_binding),
           data_source_id: data_source_id(request, source_binding)
         }
       })}
    else
      {:warning, warning} -> {:error, warning}
    end
  end

  @spec resolve(PlannedSourceRequest.t(), keyword()) :: SourceResult.t()
  def resolve(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    source_binding = Keyword.get(opts, :source_binding)
    overlay_warnings = Warnings.overlay(request)

    with :ok <- ensure_telemetry_source(request),
         :ok <- ensure_supported_sampling(request, source_binding),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id),
         :ok <- ensure_observables(request.observables) do
      watermark = watermark(request, source_binding, organization_id, mission_id, opts)

      request_warnings =
        overlay_warnings ++ Warnings.watermark(request, source_binding, watermark)

      {frames, mode_warnings, supported_capability} =
        resolve_frames(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts,
          request_warnings
        )

      warnings = request_warnings ++ mode_warnings

      SourceResult.new(%{
        request_id: request.request_id,
        frames: frames,
        warnings: warnings,
        watermarks: [watermark],
        meta: %{
          logical_source: :telemetry,
          source_binding_id: source_binding_id(source_binding),
          data_source_id: data_source_id(request, source_binding),
          supported_capability: supported_capability,
          returned_frame_count: length(frames),
          telemetry_revision_dependency: RevisionState.dependency(frames),
          degraded?: Warnings.degraded?(warnings)
        }
      })
    else
      {:warning, warning} ->
        request_warnings = overlay_warnings ++ Warnings.unknown_watermark(request)

        SourceResult.new(%{
          request_id: request.request_id,
          warnings: request_warnings ++ [warning],
          watermarks: [unknown_watermark(request, source_binding)],
          meta: %{
            logical_source: request.logical_source,
            source_binding_id: source_binding_id(source_binding),
            data_source_id: data_source_id(request, source_binding),
            supported_capability: supported_capability(request),
            returned_frame_count: 0,
            degraded?: true
          }
        })
    end
  end

  defp ensure_telemetry_source(%PlannedSourceRequest{logical_source: :telemetry}), do: :ok

  defp ensure_telemetry_source(%PlannedSourceRequest{} = request) do
    {:warning,
     Warnings.warning(
       request,
       :unsupported_logical_source,
       :error,
       "Telemetry adapter cannot resolve source",
       %{
         logical_source: request.logical_source
       }
     )}
  end

  defp ensure_supported_sampling(%PlannedSourceRequest{} = request, source_binding) do
    mode = sampling_mode(request)

    if mode in supported_sampling_modes(source_binding) do
      :ok
    else
      {:warning,
       Warnings.warning(
         request,
         :unsupported_sampling,
         :warning,
         "Telemetry source cannot resolve requested sampling mode",
         %{
           requested_mode: mode,
           supported_modes: supported_sampling_modes(source_binding)
         }
       )}
    end
  end

  defp supported_sampling_modes(source_binding) do
    if native_decimation?(source_binding) do
      @supported_sampling_modes ++ @native_decimated_sampling_modes
    else
      @supported_sampling_modes
    end
  end

  defp ensure_observables([observable | _rest]) when is_binary(observable), do: :ok

  defp ensure_observables(_observables) do
    {:warning,
     %ResolveWarning{
       code: :missing_observables,
       severity: :error,
       scope: :dashboard,
       message: "Telemetry source request does not include observables"
     }}
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp resolve_frames(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings
       ) do
    data_view_warnings = Warnings.data_view(request)
    request_warnings = request_warnings ++ data_view_warnings

    case sampling_mode(request) do
      :latest ->
        latest_opts = QueryOptions.latest(request, source_binding, opts)
        time_warnings = QueryOptions.latest_warnings(request)
        latest_fun = Keyword.get(opts, :latest_fun, &default_latest/4)

        {frames, revision_warnings} =
          Enum.map(request.observables, fn observable_id ->
            sample = latest_fun.(organization_id, mission_id, observable_id, latest_opts)

            {
              FrameBuilder.latest(
                request,
                source_binding,
                observable_id,
                sample,
                request_warnings ++ time_warnings,
                FrameContext.source_filter_context(latest_opts)
              ),
              List.wrap(sample)
            }
          end)
          |> resolve_revision_state(request, source_binding, organization_id, mission_id, opts)

        frames =
          annotate_active_historical_workflows(
            frames,
            request,
            source_binding,
            organization_id,
            mission_id,
            opts
          )

        partial_warnings =
          Warnings.partial_coverage(request, source_binding, frames)

        frames =
          Warnings.annotate_frames(frames, partial_warnings)

        {frames, data_view_warnings ++ time_warnings ++ revision_warnings ++ partial_warnings,
         :latest_value}

      mode when mode in @history_sampling_modes ->
        {history_opts, time_warnings} = QueryOptions.history(request, source_binding, opts)
        history_fun = Keyword.get(opts, :history_fun, &default_history/4)

        case resolve_history_entries(
               request,
               source_binding,
               organization_id,
               mission_id,
               history_opts,
               history_fun,
               request_warnings ++ time_warnings
             ) do
          {:ok, entries} ->
            bounded_history_success_result(
              entries,
              request,
              source_binding,
              organization_id,
              mission_id,
              opts,
              data_view_warnings,
              time_warnings
            )

          {:error, observable_id, reason} ->
            bounded_history_error_result(
              request,
              source_binding,
              observable_id,
              reason,
              data_view_warnings,
              request_warnings,
              time_warnings
            )
        end

      :decimated_envelope ->
        {decimated_opts, time_warnings} = QueryOptions.decimated(request, source_binding, opts)
        aggregate_warnings = Warnings.native_aggregate_semantics(request)

        decimated_history_fun =
          Keyword.get(opts, :decimated_history_fun, &default_decimated_history/4)

        case resolve_decimated_frames(
               request,
               source_binding,
               organization_id,
               mission_id,
               decimated_opts,
               decimated_history_fun,
               request_warnings ++ time_warnings ++ aggregate_warnings
             ) do
          {:ok, frames} ->
            partial_warnings =
              Warnings.partial_coverage(request, source_binding, frames)

            frames =
              annotate_active_historical_workflows(
                frames,
                request,
                source_binding,
                organization_id,
                mission_id,
                opts
              )

            {frames,
             data_view_warnings ++ time_warnings ++ aggregate_warnings ++ partial_warnings,
             :native_decimated_envelope}

          {:error, reason} ->
            source_warning =
              Warnings.source_query_failure(
                request,
                source_binding,
                nil,
                :native_decimated_history,
                :native_decimation,
                reason
              )

            {[],
             data_view_warnings ++
               request_warnings ++
               time_warnings ++
               aggregate_warnings ++
               [source_warning], :native_decimated_envelope}
        end
    end
  end

  defp bounded_history_success_result(
         entries,
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         data_view_warnings,
         time_warnings
       ) do
    {frames, revision_warnings} =
      entries
      |> Enum.map(fn {frame, samples, _history_warnings} -> {frame, samples} end)
      |> resolve_revision_state(request, source_binding, organization_id, mission_id, opts)

    frames =
      annotate_active_historical_workflows(
        frames,
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )

    history_warnings =
      entries
      |> Enum.flat_map(fn {_frame, _samples, history_warnings} -> history_warnings end)
      |> Enum.uniq_by(&Warnings.key/1)

    partial_warnings =
      Warnings.partial_coverage(request, source_binding, frames)

    {frames,
     data_view_warnings ++
       time_warnings ++
       history_warnings ++
       revision_warnings ++
       partial_warnings, bounded_history_capability(request)}
  end

  defp bounded_history_error_result(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         reason,
         data_view_warnings,
         request_warnings,
         time_warnings
       ) do
    source_warning =
      Warnings.source_query_failure(
        request,
        source_binding,
        observable_id,
        :bounded_history,
        bounded_history_capability(request),
        reason
      )

    {[], data_view_warnings ++ request_warnings ++ time_warnings ++ [source_warning],
     bounded_history_capability(request)}
  end

  defp resolve_history_entries(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         history_opts,
         history_fun,
         warnings
       ) do
    request.observables
    |> Enum.reduce_while({:ok, []}, fn observable_id, {:ok, entries} ->
      history_result =
        history_fun.(organization_id, mission_id, observable_id, history_opts)

      case normalize_history_result(history_result) do
        {:ok, samples, diagnostics} ->
          history_warnings = Warnings.history_diagnostics(request, observable_id, diagnostics)

          entry =
            {
              FrameBuilder.history(
                request,
                source_binding,
                observable_id,
                samples,
                warnings ++ history_warnings,
                diagnostics,
                FrameContext.source_filter_context(history_opts)
              ),
              samples,
              history_warnings
            }

          {:cont, {:ok, [entry | entries]}}

        {:error, reason} ->
          {:halt, {:error, observable_id, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, observable_id, reason} -> {:error, observable_id, reason}
    end
  end

  defp resolve_decimated_frames(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         decimated_history_fun,
         warnings
       ) do
    request.observables
    |> Enum.reduce_while({:ok, []}, fn observable_id, {:ok, frames} ->
      case resolve_decimated_frame(
             request,
             source_binding,
             organization_id,
             mission_id,
             observable_id,
             opts,
             decimated_history_fun,
             warnings
           ) do
        {:ok, frame} -> {:cont, {:ok, [frame | frames]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, frames} -> {:ok, Enum.reverse(frames)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_decimated_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         observable_id,
         opts,
         decimated_history_fun,
         warnings
       ) do
    decimated_history_fun.(organization_id, mission_id, observable_id, opts)
    |> normalize_decimated_history_result()
    |> decimated_frame_result(request, source_binding, observable_id, warnings, opts)
  end

  defp decimated_frame_result(
         {:ok, buckets, diagnostics},
         request,
         source_binding,
         observable_id,
         warnings,
         opts
       ) do
    frame =
      FrameBuilder.decimated(
        request,
        source_binding,
        observable_id,
        buckets,
        warnings,
        diagnostics,
        FrameContext.source_filter_context(opts)
      )

    {:ok, frame}
  end

  defp decimated_frame_result(
         {:error, reason},
         _request,
         _source_binding,
         _observable_id,
         _warnings,
         _opts
       ) do
    {:error, reason}
  end

  defp normalize_history_result({:ok, %{samples: samples, diagnostics: diagnostics}})
       when is_list(samples) and is_map(diagnostics) do
    {:ok, samples, diagnostics}
  end

  defp normalize_history_result(%{samples: samples, diagnostics: diagnostics})
       when is_list(samples) and is_map(diagnostics) do
    {:ok, samples, diagnostics}
  end

  defp normalize_history_result({:error, reason}), do: {:error, reason}
  defp normalize_history_result({:ok, samples}) when is_list(samples), do: {:ok, samples, %{}}
  defp normalize_history_result(samples) when is_list(samples), do: {:ok, samples, %{}}
  defp normalize_history_result(other), do: {:error, {:invalid_history_result, other}}

  defp normalize_decimated_history_result({:ok, %{buckets: buckets, diagnostics: diagnostics}})
       when is_list(buckets) and is_map(diagnostics) do
    {:ok, buckets, diagnostics}
  end

  defp normalize_decimated_history_result(%{buckets: buckets, diagnostics: diagnostics})
       when is_list(buckets) and is_map(diagnostics) do
    {:ok, buckets, diagnostics}
  end

  defp normalize_decimated_history_result({:error, reason}), do: {:error, reason}

  defp normalize_decimated_history_result({:ok, buckets}) when is_list(buckets),
    do: {:ok, buckets, %{}}

  defp normalize_decimated_history_result(buckets) when is_list(buckets), do: {:ok, buckets, %{}}

  defp normalize_decimated_history_result(other),
    do: {:error, {:invalid_decimated_history_result, other}}

  defp required_request_context(%PlannedSourceRequest{} = request, key) do
    case request_context_value(request, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _other ->
        {:warning,
         %ResolveWarning{
           code: missing_context_code(key),
           severity: :error,
           scope: :dashboard,
           message: "Telemetry source request is missing required context",
           details: %{required_context: key}
         }}
    end
  end

  defp missing_context_code(:organization_id), do: :missing_tenant_context
  defp missing_context_code(:mission_id), do: :missing_mission_context

  defp request_context_value(%PlannedSourceRequest{organization_id: value}, :organization_id)
       when is_binary(value) and value != "",
       do: value

  defp request_context_value(%PlannedSourceRequest{mission_id: value}, :mission_id)
       when is_binary(value) and value != "",
       do: value

  defp request_context_value(%PlannedSourceRequest{} = request, key) do
    context_value(request.scope_context, key)
  end

  defp resolve_revision_state(
         frames_with_samples,
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    RevisionState.resolve(
      frames_with_samples,
      request,
      identity_state_opts(request, source_binding, organization_id, mission_id),
      opts
    )
  end

  defp annotate_active_historical_workflows(
         frames,
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts
       )
       when is_list(frames) do
    {source_from, source_to, _warnings} = QueryOptions.receipt_time_bounds(request)

    query_opts =
      [
        organization_id: organization_id,
        realm: realm(request, source_binding),
        replay_run_id: replay_run_id(request),
        data_source_id: data_source_id(request, source_binding),
        binding_id: source_binding_id(source_binding),
        source_from: source_from,
        source_to: source_to,
        limit: 1_000
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

    HistoricalWorkflows.annotate(frames, mission_id, query_opts, opts)
  end

  defp identity_state_opts(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id
       ) do
    [
      organization_id: organization_id,
      mission_id: mission_id,
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
      data_source_id: data_source_id(request, source_binding),
      binding_id: source_binding_id(source_binding)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp watermark(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if watermarks_supported?(source_binding) do
      watermark_fun = Keyword.get(opts, :watermark_fun, &default_watermark/4)
      watermark_opts = QueryOptions.watermark(request, source_binding, opts)

      request.observables
      |> Enum.map(fn observable_id ->
        {observable_id,
         watermark_fun.(organization_id, mission_id, observable_id, watermark_opts)}
      end)
      |> request_watermark(request, source_binding)
    else
      unknown_watermark(request, source_binding)
    end
  end

  defp unknown_watermark(%PlannedSourceRequest{} = request, source_binding) do
    %SourceWatermark{
      logical_source: :telemetry,
      request_id: request.request_id,
      source_binding_id: source_binding_id(source_binding),
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
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

    point_watermarks =
      Map.new(normalized_results, fn {observable_id, result} ->
        {observable_id, result}
      end)

    if Enum.all?(normalized_results, fn {_observable_id, result} ->
         Map.get(result, :confidence) in [:authoritative, :best_effort]
       end) do
      %SourceWatermark{
        logical_source: :telemetry,
        request_id: request.request_id,
        source_binding_id: source_binding_id(source_binding),
        realm: realm(request, source_binding),
        replay_run_id: replay_run_id(request),
        data_source_id: data_source_id(request, source_binding),
        dataset: dataset(source_binding),
        scope: request.scope_context,
        complete_through: minimum_datetime(normalized_results, :complete_through),
        latest_receipt_time: maximum_datetime(normalized_results, :latest_receipt_time),
        retention_starts_at: minimum_datetime(normalized_results, :retention_starts_at),
        confidence: :best_effort,
        meta:
          source_watermark_meta(%{
            point_watermarks: point_watermarks,
            canonical_mode: :physical,
            aggregate_semantics: :physical_as_recorded
          })
      }
    else
      %SourceWatermark{
        unknown_watermark(request, source_binding)
        | meta:
            source_watermark_meta(%{
              point_watermarks: point_watermarks,
              canonical_mode: :physical,
              aggregate_semantics: :physical_as_recorded
            })
      }
    end
  end

  defp source_watermark_meta(meta), do: meta

  defp normalize_watermark_result({:ok, result}) when is_map(result), do: result

  defp normalize_watermark_result({:error, reason}) do
    %{confidence: :unknown, error: inspect(reason)}
  end

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

  defp watermarks_supported?(%{data_source: %{capabilities: capabilities}})
       when is_map(capabilities) do
    Map.get(capabilities, :watermarks?, Map.get(capabilities, "watermarks?")) == true
  end

  defp watermarks_supported?(_source_binding), do: false

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

  defp default_decimated_history(nil, _mission_id, _point_id, _opts) do
    {:error, :missing_tenant_context}
  end

  defp default_decimated_history(organization_id, mission_id, point_id, opts) do
    case TelemetryReads.decimated_sample_history_result(
           organization_id,
           mission_id,
           point_id,
           opts
         ) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_history(nil, mission_id, point_id, opts) do
    TelemetryReads.sample_history_result(mission_id, point_id, opts)
  end

  defp default_history(organization_id, mission_id, point_id, opts) do
    TelemetryReads.sample_history_result(organization_id, mission_id, point_id, opts)
  end

  defp default_watermark(nil, _mission_id, _point_id, _opts) do
    {:error, :missing_tenant_context}
  end

  defp default_watermark(organization_id, mission_id, point_id, opts) do
    TelemetryReads.sample_watermark(organization_id, mission_id, point_id, opts)
  end

  defp default_latest(nil, mission_id, point_id, opts) do
    TelemetryReads.latest_value(mission_id, point_id, opts)
  end

  defp default_latest(organization_id, mission_id, point_id, opts) do
    TelemetryReads.latest_value(organization_id, mission_id, point_id, opts)
  end

  defp supported_capability(%PlannedSourceRequest{} = request) do
    case sampling_mode(request) do
      :latest -> :latest_value
      :decimated_envelope -> :native_decimated_envelope
      _other -> bounded_history_capability(request)
    end
  end

  defp bounded_history_capability(%PlannedSourceRequest{} = request) do
    case time_axis(request) do
      :generation_time -> :bounded_generation_time_history
      _axis -> :bounded_receipt_time_history
    end
  end

  defp sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> context_value(:mode)
    |> normalize_atom()
  end

  defp time_axis(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> context_value(:axis)
    |> normalize_atom()
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    with :error <- Map.fetch(context, key),
         :error <- Map.fetch(context, Atom.to_string(key)) do
      nil
    else
      {:ok, value} -> value
    end
  end

  defp context_value(_context, _key), do: nil

  defp native_decimation?(%{data_source: %{capabilities: capabilities}}) do
    capability_value(capabilities, :native_decimation?) == true
  end

  defp native_decimation?(_source_binding), do: false

  defp capability_value(capabilities, key) when is_map(capabilities) and is_atom(key) do
    Map.get(capabilities, key, Map.get(capabilities, Atom.to_string(key)))
  end

  defp capability_value(_capabilities, _key), do: nil

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
