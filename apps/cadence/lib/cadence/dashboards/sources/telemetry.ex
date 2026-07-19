defmodule Cadence.Dashboards.Sources.Telemetry do
  @moduledoc """
  Dashboard telemetry source adapter.

  This first adapter slice supports latest telemetry values and bounded raw
  telemetry history over receipt time. It intentionally does not make the
  planner execute IO; callers pass a `PlannedSourceRequest` here after planning.
  """

  alias Cadence.Contacts

  alias Cadence.Dashboards.{
    DataContext,
    DataLinks,
    DataSource,
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    ScopeContext,
    SourceActions,
    SourceCapabilities,
    SourceFacts,
    SourceProbe,
    SourceResult,
    SourceWatermark,
    TelemetryActions
  }

  alias Cadence.Dashboards.Sources.Telemetry.{FrameBuilder, FrameContext}
  alias Cadence.Dashboards.Sources.Telemetry.HistoricalWorkflows
  alias Cadence.Dashboards.Sources.Telemetry.QuestDBProbe
  alias Cadence.Dashboards.Sources.Telemetry.RevisionState
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Telemetry.{Sample, SelectionPolicy}

  @history_sampling_modes [:raw_series, :bounded_history, :bounded_raw_series]
  @native_decimated_sampling_modes [:decimated_envelope]
  @supported_sampling_modes [:latest | @history_sampling_modes]
  @default_limit 10_000
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
    overlay_warnings = overlay_warnings(request)

    with :ok <- ensure_telemetry_source(request),
         :ok <- ensure_supported_sampling(request, source_binding),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id),
         :ok <- ensure_observables(request.observables) do
      watermark = watermark(request, source_binding, organization_id, mission_id, opts)

      request_warnings =
        overlay_warnings ++ watermark_warnings(request, source_binding, watermark)

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
          degraded?: degraded?(warnings)
        }
      })
    else
      {:warning, warning} ->
        request_warnings = overlay_warnings ++ unknown_watermark_warnings(request)

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
     warning(
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
       warning(
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
    data_view_warnings = data_view_warnings(request)
    request_warnings = request_warnings ++ data_view_warnings

    case sampling_mode(request) do
      :latest ->
        latest_opts = latest_opts(request, source_binding, opts)
        time_warnings = latest_time_warnings(request)
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
          partial_coverage_warnings(request, source_binding, frames)

        frames =
          annotate_frame_warning_codes(frames, partial_warnings)

        {frames, data_view_warnings ++ time_warnings ++ revision_warnings ++ partial_warnings,
         :latest_value}

      mode when mode in @history_sampling_modes ->
        {history_opts, time_warnings} = history_opts(request, source_binding, opts)
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
        {decimated_opts, time_warnings} = decimated_history_opts(request, source_binding, opts)
        aggregate_warnings = native_aggregate_semantics_warnings(request)

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
              partial_coverage_warnings(request, source_binding, frames)

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
              source_query_failure_warning(
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
      |> Enum.uniq_by(&warning_key/1)

    partial_warnings =
      partial_coverage_warnings(request, source_binding, frames)

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
      source_query_failure_warning(
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
          history_warnings = history_diagnostics_warnings(request, observable_id, diagnostics)

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

  defp history_diagnostics_warnings(
         %PlannedSourceRequest{} = request,
         observable_id,
         %{candidate_window_exhausted?: true} = diagnostics
       ) do
    [
      %ResolveWarning{
        code: :candidate_window_exhausted,
        severity: :warning,
        scope: :frame,
        frame_id: "#{request.request_id}:#{observable_id}",
        message: "Telemetry history candidate window was exhausted before selection completed",
        details:
          diagnostics
          |> Map.merge(%{
            source_request_id: request.request_id,
            observable_id: observable_id,
            point_id: observable_id
          })
          |> put_telemetry_warning_actions(request, observable_id),
        links: DataLinks.request_observable_links(request, source: :warning)
      }
    ]
  end

  defp history_diagnostics_warnings(%PlannedSourceRequest{}, _observable_id, _diagnostics),
    do: []

  defp partial_coverage_warnings(
         %PlannedSourceRequest{} = request,
         source_binding,
         frames
       )
       when is_list(frames) do
    empty_observables =
      frames
      |> Enum.filter(&empty_frame?/1)
      |> Enum.map(&frame_observable_id/1)
      |> Enum.reject(&is_nil/1)

    returned_observables =
      frames
      |> Enum.reject(&empty_frame?/1)
      |> Enum.map(&frame_observable_id/1)
      |> Enum.reject(&is_nil/1)

    if empty_observables != [] and returned_observables != [] do
      [
        warning(
          request,
          :partial_data,
          :warning,
          "Telemetry range source returned partial data",
          %{
            logical_source: :telemetry,
            requested_observables: request.observables,
            returned_observables: returned_observables,
            empty_observables: empty_observables,
            source_binding_id: source_binding_id(source_binding),
            data_source_id: data_source_id(request, source_binding),
            realm: realm(request, source_binding),
            time_mode: time_mode(request),
            time_axis: :receipt_time
          }
        )
      ]
    else
      []
    end
  end

  defp partial_coverage_warnings(%PlannedSourceRequest{}, _source_binding, _frames),
    do: []

  defp annotate_frame_warning_codes(frames, []), do: frames

  defp annotate_frame_warning_codes(frames, warnings)
       when is_list(frames) and is_list(warnings) do
    warning_codes =
      warnings
      |> Enum.map(& &1.code)
      |> Enum.reject(&is_nil/1)

    Enum.map(frames, &annotate_frame_warning_codes(&1, warning_codes))
  end

  defp annotate_frame_warning_codes(%Frame{meta: meta} = frame, warning_codes)
       when is_map(meta) do
    existing_codes =
      meta
      |> Map.get(:warning_codes, Map.get(meta, "warning_codes", []))
      |> List.wrap()

    %Frame{
      frame
      | meta: Map.put(meta, :warning_codes, Enum.uniq(existing_codes ++ warning_codes))
    }
  end

  defp annotate_frame_warning_codes(frame, _warning_codes), do: frame

  defp empty_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :returned_points, Map.get(meta, "returned_points", 0)) == 0
  end

  defp empty_frame?(%Frame{}), do: true

  defp frame_observable_id(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :observable_id, Map.get(meta, "observable_id"))
  end

  defp frame_observable_id(%Frame{}), do: nil

  defp overlay_warnings(%PlannedSourceRequest{overlays: []}), do: []
  defp overlay_warnings(%PlannedSourceRequest{overlays: nil}), do: []

  defp overlay_warnings(%PlannedSourceRequest{} = request) do
    [
      warning(
        request,
        :capability_fallback,
        :info,
        "Telemetry source does not resolve overlays yet",
        %{
          requested_overlays: request.overlays,
          unresolved_capability: :overlays
        }
      )
    ]
  end

  defp watermark_warnings(
         %PlannedSourceRequest{},
         _source_binding,
         %SourceWatermark{confidence: confidence}
       )
       when confidence in [:authoritative, :best_effort],
       do: []

  defp watermark_warnings(
         %PlannedSourceRequest{} = request,
         source_binding,
         %SourceWatermark{} = watermark
       ) do
    unknown_watermark_warnings(request, source_binding, watermark)
  end

  defp unknown_watermark_warnings(%PlannedSourceRequest{} = request) do
    unknown_watermark_warnings(request, nil, nil)
  end

  defp unknown_watermark_warnings(
         %PlannedSourceRequest{} = request,
         source_binding,
         %SourceWatermark{} = watermark
       ) do
    details =
      case watermark_errors(watermark) do
        [{observable_id, reason} | _rest] ->
          source_query_failure_details(
            request,
            source_binding,
            observable_id,
            :watermark,
            :source_watermark,
            reason
          )

        [] ->
          %{unresolved_capability: :source_watermark}
      end

    [
      warning(
        request,
        :watermark_unknown,
        :info,
        "Telemetry source watermark confidence is unknown",
        details
      )
    ]
  end

  defp unknown_watermark_warnings(%PlannedSourceRequest{} = request, _source_binding, _watermark) do
    [
      warning(
        request,
        :watermark_unknown,
        :info,
        "Telemetry source watermark confidence is unknown",
        %{unresolved_capability: :source_watermark}
      )
    ]
  end

  defp watermark_errors(%SourceWatermark{meta: %{point_watermarks: point_watermarks}})
       when is_map(point_watermarks) do
    point_watermarks
    |> Enum.flat_map(fn {observable_id, result} ->
      case watermark_error(result) do
        nil -> []
        reason -> [{observable_id, reason}]
      end
    end)
  end

  defp watermark_errors(%SourceWatermark{}), do: []

  defp watermark_error(result) when is_map(result) do
    context_value(result, :error)
  end

  defp watermark_error(_result), do: nil

  defp native_aggregate_semantics_warnings(%PlannedSourceRequest{} = request) do
    [
      warning(
        request,
        :physical_aggregate_semantics,
        :info,
        "Native telemetry aggregates use physical storage semantics",
        %{
          canonical_mode: :physical,
          aggregate_semantics: :physical_as_recorded,
          affected_products: [:native_decimated_envelope, :source_watermark],
          future_mode: :effective_canonical
        }
      )
    ]
  end

  defp source_query_failure_warning(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         query_kind,
         unresolved_capability,
         reason
       ) do
    warning(
      request,
      :source_unavailable,
      :error,
      source_query_failure_message(query_kind),
      source_query_failure_details(
        request,
        source_binding,
        observable_id,
        query_kind,
        unresolved_capability,
        reason
      )
    )
  end

  defp source_query_failure_message(:native_decimated_history),
    do: "Telemetry data source cannot execute native decimated history"

  defp source_query_failure_message(:watermark),
    do: "Telemetry data source cannot read source watermark"

  defp source_query_failure_message(_query_kind),
    do: "Telemetry data source cannot execute bounded history"

  defp source_query_failure_details(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         query_kind,
         unresolved_capability,
         reason
       ) do
    %{
      logical_source: :telemetry,
      source_empty_reason: :source_query_failed,
      source_query_kind: query_kind,
      unresolved_capability: unresolved_capability,
      reason: format_reason(reason),
      observable_id: observable_id || List.first(List.wrap(request.observables)),
      point_id: observable_id || List.first(List.wrap(request.observables)),
      data_source_id: data_source_id(request, source_binding),
      source_binding_id: source_binding_id(source_binding),
      realm: realm(request, source_binding),
      dataset: dataset(source_binding),
      requested_sampling: sampling_mode(request)
    }
    |> SourceActions.put_source_request_context(request, :telemetry)
    |> SourceActions.put_source_warning_actions()
  end

  defp data_view_warnings(%PlannedSourceRequest{} = request) do
    case FrameContext.data_view(request) do
      :canonical ->
        []

      :as_recorded ->
        [
          warning(
            request,
            :as_recorded_view,
            :info,
            "Telemetry source is using as-recorded data view",
            data_view_warning_details(request, :as_recorded)
          )
        ]

      :all_revisions ->
        [
          warning(
            request,
            :all_revisions_view,
            :warning,
            "Telemetry source is showing all observation revisions",
            data_view_warning_details(request, :all_revisions)
          )
        ]

      :recomputed ->
        [
          warning(
            request,
            :recomputed_values,
            :warning,
            "Telemetry source is using recomputed data view semantics",
            data_view_warning_details(request, :recomputed)
          )
        ]
    end
  end

  defp data_view_warning_details(%PlannedSourceRequest{} = request, data_view) do
    %{
      data_view: data_view,
      canonical_default?: false,
      point_id: List.first(List.wrap(request.observables)),
      observable_id: List.first(List.wrap(request.observables))
    }
  end

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

  defp selection_policy_opts(%PlannedSourceRequest{} = request) do
    [
      selection_view:
        DataContext.source_value(request.data_context, request.logical_source, :view) ||
          first_context_value(request.data_context, [
            :selection_view,
            :view,
            :data_view,
            :data_management_view
          ]),
      validity_state: context_value(request.data_context, :validity_state)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> SelectionPolicy.query_opts()
  end

  defp history_opts(%PlannedSourceRequest{} = request, source_binding, source_opts) do
    {time_opts, time_warnings} = bounded_history_time_opts(request, source_opts)

    opts =
      [
        realm: realm(request, source_binding),
        replay_run_id: replay_run_id(request),
        data_source_id: data_source_id(request, source_binding),
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        spacecraft_id: spacecraft_id(request.scope_context),
        source_endpoint_ids: source_endpoint_ids(request, source_opts),
        limit: raw_point_limit(request),
        order: :asc
      ]
      |> Kernel.++(time_opts)
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

    {opts ++ selection_policy_opts(request) ++ connection_opts(source_opts), time_warnings}
  end

  defp decimated_history_opts(%PlannedSourceRequest{} = request, source_binding, source_opts) do
    {opts, time_warnings} = history_opts(request, source_binding, source_opts)

    decimation_opts =
      [
        target_points: target_points(request),
        bucket_width_ms: bucket_width_ms(request),
        decimation: :native_min_max_envelope
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    {opts ++ decimation_opts, time_warnings}
  end

  defp latest_opts(%PlannedSourceRequest{} = request, source_binding, opts) do
    [
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
      data_source_id: data_source_id(request, source_binding),
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      spacecraft_id: spacecraft_id(request.scope_context),
      source_endpoint_ids: source_endpoint_ids(request, opts),
      to_receipt_time: latest_as_of_receipt_time(request)
    ]
    |> Kernel.++(selection_policy_opts(request))
    |> Kernel.++(connection_opts(opts))
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp connection_opts(opts) when is_list(opts) do
    opts
    |> Keyword.take([
      :http_endpoint,
      :headers,
      :source_connection_profile,
      :source_connection_material
    ])
    |> Enum.reject(fn
      {_key, nil} -> true
      {_key, ""} -> true
      {_key, []} -> true
      _entry -> false
    end)
  end

  defp connection_opts(_opts), do: []

  defp receipt_time_bounds(%PlannedSourceRequest{} = request) do
    {time_bounds, warnings} = bounded_history_time_opts(request)

    {
      Keyword.get(time_bounds, :from_receipt_time),
      Keyword.get(time_bounds, :to_receipt_time),
      warnings
    }
  end

  defp bounded_history_time_opts(%PlannedSourceRequest{} = request) do
    requested_axis = time_axis(request)
    effective_axis = effective_bounded_history_time_axis(request, [])
    {from_time, to_time} = bounded_history_time_range(request, [])

    bounded_history_time_opts_for_axis(
      request,
      requested_axis,
      effective_axis,
      from_time,
      to_time,
      []
    )
  end

  defp bounded_history_time_opts(%PlannedSourceRequest{} = request, source_opts) do
    requested_axis = time_axis(request)
    effective_axis = effective_bounded_history_time_axis(request, source_opts)
    {from_time, to_time} = bounded_history_time_range(request, source_opts)

    bounded_history_time_opts_for_axis(
      request,
      requested_axis,
      effective_axis,
      from_time,
      to_time,
      source_opts
    )
  end

  defp bounded_history_time_range(%PlannedSourceRequest{} = request, source_opts) do
    from_time = first_context_value(request.time_context, [:from, :start, :start_time])
    to_time = first_context_value(request.time_context, [:to, :end, :end_time])

    case {from_time, to_time, live_time_context?(request.time_context),
          live_window_seconds(request.time_context)} do
      {nil, nil, true, window_seconds} when is_integer(window_seconds) ->
        to_time = live_window_now(source_opts)
        {DateTime.add(to_time, -window_seconds, :second), to_time}

      _explicit_or_unbounded ->
        {from_time, to_time}
    end
  end

  defp live_time_context?(time_context) do
    first_context_value(time_context, [:mode]) in [:live, "live"]
  end

  defp live_window_seconds(time_context) do
    case first_context_value(time_context, [:window_seconds]) do
      window_seconds when is_integer(window_seconds) and window_seconds > 0 -> window_seconds
      _invalid_or_missing -> nil
    end
  end

  defp live_window_now(source_opts) do
    case Keyword.get(source_opts, :now) do
      %DateTime{} = now -> DateTime.truncate(now, :microsecond)
      _missing -> DateTime.utc_now()
    end
  end

  defp effective_bounded_history_time_axis(%PlannedSourceRequest{} = request, source_opts) do
    requested_axis = time_axis(request)
    supported_axes = supported_time_axes(source_opts)

    cond do
      requested_axis in [nil, :receipt_time] ->
        :receipt_time

      requested_axis == :generation_time and supported_axes == [] ->
        :generation_time

      requested_axis == :generation_time and :generation_time in supported_axes ->
        :generation_time

      true ->
        :unsupported
    end
  end

  defp supported_time_axes(source_opts) when is_list(source_opts) do
    source_opts
    |> Keyword.get(:supported_time_axes, [])
    |> List.wrap()
    |> Enum.map(&normalize_atom/1)
    |> Enum.filter(&(&1 in [:generation_time, :receipt_time]))
    |> Enum.uniq()
  end

  defp supported_time_axes(_source_opts), do: []

  defp bounded_history_time_opts_for_axis(
         request,
         requested_axis,
         effective_axis,
         from_time,
         to_time,
         source_opts
       ) do
    case effective_axis do
      axis when axis in [nil, :receipt_time] ->
        {[
           time_axis: :receipt_time,
           from_receipt_time: from_time,
           to_receipt_time: to_time
         ], []}

      :generation_time ->
        {[
           time_axis: :generation_time,
           from_observed_at: from_time,
           to_observed_at: to_time
         ], []}

      :unsupported ->
        warning =
          warning(
            request,
            :unsupported_time_axis,
            :warning,
            "Telemetry source cannot serve the requested dashboard time axis",
            %{
              requested_axis: requested_axis,
              requested_time_axis: requested_axis,
              fallback_axis: :receipt_time,
              executed_time_axis: :receipt_time,
              supported_time_axes: supported_time_axes(source_opts),
              unsupported_capability: :time_axis
            }
          )

        {[
           time_axis: :receipt_time,
           from_receipt_time: from_time,
           to_receipt_time: to_time
         ], [warning]}
    end
  end

  defp latest_time_warnings(%PlannedSourceRequest{} = request) do
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
            "Latest telemetry archive requests require a receipt-time upper bound for as-of resolution",
            %{
              requested_time_mode: context_value(request.time_context, :mode),
              requested_axis: time_axis(request),
              fallback: :latest_projection
            }
          )
        ]
    end
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
    {source_from, source_to, _warnings} = receipt_time_bounds(request)

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

  defp warning_key(%ResolveWarning{} = warning) do
    {warning.code, warning.scope, warning.frame_id, warning.field_name}
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
      watermark_opts = watermark_opts(request, source_binding, opts)

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

  defp watermark_opts(%PlannedSourceRequest{} = request, source_binding, opts) do
    {from_receipt_time, to_receipt_time, _warnings} = receipt_time_bounds(request)

    [
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      replay_run_id: replay_run_id(request),
      spacecraft_id: spacecraft_id(request.scope_context),
      source_endpoint_ids: source_endpoint_ids(request, opts),
      from_receipt_time: from_receipt_time,
      to_receipt_time: to_receipt_time
    ]
    |> Kernel.++(selection_policy_opts(request))
    |> Kernel.++(connection_opts(opts))
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
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

  defp source_endpoint_ids(%PlannedSourceRequest{} = request, opts) do
    request.scope_context
    |> direct_source_endpoint_ids()
    |> Kernel.++(contact_source_endpoint_ids(request, opts))
    |> normalize_source_endpoint_ids()
  end

  defp direct_source_endpoint_ids(scope_context) do
    primary_ids =
      if ScopeContext.primary_kind(scope_context) in [:source_endpoint, "source_endpoint"] do
        ScopeContext.primary_ids(scope_context)
      else
        []
      end

    typed_id =
      scope_context
      |> ScopeContext.scope_id(:source_endpoint)
      |> List.wrap()

    primary_ids ++ typed_id
  end

  defp contact_source_endpoint_ids(%PlannedSourceRequest{} = request, opts) do
    request.scope_context
    |> ScopeContext.scope_ids(:contact)
    |> Enum.flat_map(fn contact_id ->
      organization_id = request.organization_id
      mission_id = request.mission_id

      fetch_contact_source_endpoint_ids(organization_id, mission_id, contact_id, opts)
    end)
  end

  defp fetch_contact_source_endpoint_ids(organization_id, mission_id, contact_id, opts) do
    case fetch_scheduled_contact(organization_id, mission_id, contact_id, opts) do
      {:ok, contact} ->
        contact_source_endpoint_refs(contact)

      {:error, :scheduled_contact_not_found} ->
        case fetch_realized_contact(organization_id, mission_id, contact_id, opts) do
          {:ok, contact} -> contact_source_endpoint_refs(contact)
          {:error, _reason} -> []
        end

      {:error, _reason} ->
        []
    end
  end

  defp fetch_scheduled_contact(organization_id, mission_id, contact_id, opts) do
    fetch_scheduled_contact =
      Keyword.get(opts, :fetch_scheduled_contact, &Contacts.fetch_scheduled_contact/3)

    fetch_scheduled_contact.(organization_id, mission_id, contact_id)
  end

  defp fetch_realized_contact(organization_id, mission_id, contact_id, opts) do
    fetch_realized_contact =
      Keyword.get(opts, :fetch_realized_contact, &Contacts.fetch_realized_contact/3)

    fetch_realized_contact.(organization_id, mission_id, contact_id)
  end

  defp contact_source_endpoint_refs(contact) when is_map(contact) do
    contact
    |> context_value(:source_endpoint_refs)
    |> normalize_source_endpoint_ids()
  end

  defp contact_source_endpoint_refs(_contact), do: []

  defp normalize_source_endpoint_ids(ids) when is_list(ids) do
    ids
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp normalize_source_endpoint_ids(id) when is_binary(id) and id != "", do: [id]
  defp normalize_source_endpoint_ids(_ids), do: []

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

  defp warning(%PlannedSourceRequest{} = request, code, severity, message, details) do
    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: message,
      details:
        details
        |> Map.put(:source_request_id, request.request_id)
        |> put_telemetry_warning_actions(request, warning_observable_id(request, details)),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp put_telemetry_warning_actions(details, %PlannedSourceRequest{} = request, observable_id) do
    actions =
      TelemetryActions.explore_actions(request, observable_id, [],
        source: :warning,
        action_id: "telemetry-warning-explore:#{request.request_id}:#{observable_id || "unknown"}"
      )

    existing_actions = List.wrap(Map.get(details, :actions))

    if existing_actions == [] and actions == [] do
      details
    else
      Map.put(details, :actions, merge_warning_actions(existing_actions, actions))
    end
  end

  defp merge_warning_actions(existing_actions, new_actions) do
    existing_actions
    |> Kernel.++(new_actions)
    |> Enum.uniq_by(fn
      %{action_id: action_id} when is_binary(action_id) -> action_id
      %{target: target, query: query} -> {target, query}
      action -> action
    end)
  end

  defp warning_observable_id(%PlannedSourceRequest{} = request, details) do
    details[:observable_id] || details["observable_id"] || details[:point_id] ||
      details["point_id"] ||
      List.first(List.wrap(request.observables))
  end

  defp degraded?(warnings) do
    Enum.any?(warnings, &(&1.severity != :info))
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

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

  defp time_mode(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> context_value(:mode)
    |> normalize_atom()
  end

  defp time_range_requested?(time_context) do
    mode = time_context |> context_value(:mode) |> normalize_atom()

    mode in [:archive, :range] or
      not is_nil(first_context_value(time_context, [:from, :start, :start_time])) or
      not is_nil(first_context_value(time_context, [:to, :end, :end_time]))
  end

  defp raw_point_limit(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :max_raw_points) || context_value(sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_limit)
      _other -> @default_limit
    end
  end

  defp target_points(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :target_points) do
      target when is_integer(target) and target > 0 -> target
      _other -> nil
    end
  end

  defp bucket_width_ms(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :bucket_width_ms) do
      width when is_integer(width) and width > 0 -> width
      _other -> nil
    end
  end

  defp spacecraft_id(scope_context) do
    ScopeContext.scope_id(scope_context, :spacecraft)
  end

  defp first_context_value(context, keys) do
    keys
    |> Enum.find_value(&context_value(context, &1))
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
