defmodule Cadence.Dashboards.Sources.Limits do
  @moduledoc """
  Dashboard limits source adapter.

  v0 resolves latest observed telemetry limit-state projections, capped observed
  limit-event history, and effective limit-definition intervals.
  """

  alias Cadence.Dashboards.{
    DataContext,
    DataLinks,
    PlannedSourceRequest,
    ResolveWarning,
    SourceCapabilities,
    SourceFacts,
    SourceResult,
    SourceWatermark
  }

  alias Cadence.Dashboards.Sources.Limits.FrameBuilder
  alias Cadence.Dashboards.Sources.Limits.FrameMetadata
  alias Cadence.Dashboards.Sources.Limits.QueryContext
  alias Cadence.Dashboards.Sources.Limits.RecomputedAnalysis
  alias Cadence.Limits.{DefinitionInterval, Event}
  alias Cadence.Reads.Limits, as: LimitReads
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Telemetry.Sample

  @supported_products [:latest_state, :event_history, :definition_intervals, :analysis_buckets]
  @default_event_limit 1_000

  @type latest_fun :: (binary() | nil, binary(), binary(), keyword() -> Event.t() | nil)
  @type history_fun :: (binary() | nil, binary(), binary(), keyword() -> [Event.t()])
  @type interval_fun :: (binary() | nil, binary(), binary(), keyword() ->
                           [
                             DefinitionInterval.t()
                           ])
  @type latest_sample_fun :: (binary() | nil, binary(), binary(), keyword() -> Sample.t() | nil)
  @type sample_history_fun :: (binary() | nil, binary(), binary(), keyword() ->
                                 [Sample.t()] | {:ok, %{samples: [Sample.t()]}} | {:error, term()})
  @type watermark_fun :: (binary() | nil, binary(), binary(), keyword() ->
                            {:ok, map()} | {:error, term()} | map())

  @spec capabilities() :: SourceCapabilities.t()
  def capabilities do
    SourceCapabilities.new(%{
      logical_source: :limits,
      supported_sampling: [
        :latest_state,
        :latest,
        :event_history,
        :definition_intervals,
        :analysis_buckets
      ],
      supported_products: @supported_products,
      supported_time_axes: [:receipt_time],
      supported_value_types: [:raw, :engineering],
      supported_shapes: [:scalar, :events, :intervals],
      supports_watermarks?: false,
      completeness: :unknown
    })
  end

  @spec facts(PlannedSourceRequest.t(), keyword()) ::
          {:ok, SourceFacts.t()} | {:error, ResolveWarning.t()}
  def facts(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    source_binding = Keyword.get(opts, :source_binding)

    with :ok <- ensure_limits_source(request),
         {:ok, _product} <- requested_product(request),
         :ok <- ensure_supported_semantics(request),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id),
         :ok <- ensure_observables(request.observables) do
      watermark =
        QueryContext.watermark_for_request(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts
        )

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
           logical_source: :limits,
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

    with :ok <- ensure_limits_source(request),
         {:ok, product} <- requested_product(request),
         :ok <- ensure_supported_semantics(request),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id),
         :ok <- ensure_observables(request.observables) do
      watermark =
        QueryContext.watermark_for_request(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts
        )

      request_warnings = watermark_warnings(request, watermark)

      {frames, frame_warnings, supported_capability} =
        resolve_frames(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts,
          request_warnings,
          product
        )

      warnings = request_warnings ++ List.flatten(frame_warnings)

      SourceResult.new(%{
        request_id: request.request_id,
        frames: frames,
        warnings: warnings,
        watermarks: [watermark],
        meta: %{
          logical_source: :limits,
          source_binding_id: source_binding_id(source_binding),
          data_source_id: data_source_id(request, source_binding),
          supported_capability: supported_capability,
          returned_frame_count: length(frames),
          degraded?: degraded?(warnings)
        }
      })
    else
      {:warning, warning} ->
        request_warnings = unknown_watermark_warnings(request)

        SourceResult.new(%{
          request_id: request.request_id,
          warnings: request_warnings ++ [warning],
          watermarks: [QueryContext.unknown_watermark(request, source_binding)],
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

  defp ensure_limits_source(%PlannedSourceRequest{logical_source: :limits}), do: :ok

  defp ensure_limits_source(%PlannedSourceRequest{} = request) do
    {:warning,
     warning(
       request,
       :unsupported_logical_source,
       :error,
       "Limits adapter cannot resolve source",
       %{
         logical_source: request.logical_source
       }
     )}
  end

  defp ensure_observables([observable | _rest]) when is_binary(observable), do: :ok

  defp ensure_observables(_observables) do
    {:warning,
     %ResolveWarning{
       code: :missing_observables,
       severity: :error,
       scope: :dashboard,
       message: "Limits source request does not include observables"
     }}
  end

  defp ensure_supported_semantics(%PlannedSourceRequest{} = request) do
    case RecomputedAnalysis.semantics_mode(request) do
      semantics_mode when semantics_mode in [:observed, :current, :recomputed, :compare] ->
        :ok

      semantics_mode ->
        {:warning,
         warning(
           request,
           :unsupported_limit_semantics_mode,
           :warning,
           "Limits source supports observed, current, recomputed, and compare limit semantics",
           unsupported_limit_semantics_details(request, semantics_mode)
         )}
    end
  end

  defp unsupported_limit_semantics_details(%PlannedSourceRequest{} = request, semantics_mode) do
    %{
      requested_semantics_mode: semantics_mode,
      requested_analysis_basis: RecomputedAnalysis.analysis_basis(semantics_mode),
      selected_limit_clock: RecomputedAnalysis.limit_clock_policy(request),
      supported_semantics_modes: [:observed, :current, :recomputed, :compare],
      supported_analysis_basis: [
        :observed_fact,
        :current_definition_analysis,
        :recomputed_analysis,
        :limit_comparison_analysis
      ],
      required_inputs: required_inputs_for_semantics(semantics_mode),
      future_capability: future_capability_for_semantics(semantics_mode)
    }
  end

  defp required_inputs_for_semantics(:current) do
    [
      :current_limit_definition_projection,
      :telemetry_sample_read_path,
      :dashboard_limit_recompute_engine
    ]
  end

  defp required_inputs_for_semantics(:recomputed) do
    [
      :historical_telemetry_sample_read_path,
      :target_limit_definition_intervals,
      :selected_limit_clock_policy,
      :dashboard_limit_recompute_engine
    ]
  end

  defp required_inputs_for_semantics(:compare) do
    [
      :observed_limit_event_read_path,
      :recomputed_limit_analysis_path,
      :comparison_frame_contract,
      :divergence_warning_policy
    ]
  end

  defp required_inputs_for_semantics(_semantics_mode), do: [:supported_limit_semantics_mode]

  defp future_capability_for_semantics(:current), do: :current_limit_analysis
  defp future_capability_for_semantics(:recomputed), do: :recomputed_limit_analysis
  defp future_capability_for_semantics(:compare), do: :limit_comparison_analysis
  defp future_capability_for_semantics(_semantics_mode), do: :limit_semantics_extension

  defp recomputed_capability(:compare), do: :limit_comparison_analysis
  defp recomputed_capability(:current), do: :current_limit_analysis
  defp recomputed_capability(:recomputed), do: :recomputed_limit_analysis
  defp recomputed_capability(_semantics_mode), do: :limit_event_history

  defp watermark_warnings(%PlannedSourceRequest{}, %SourceWatermark{confidence: confidence})
       when confidence in [:authoritative, :best_effort],
       do: []

  defp watermark_warnings(%PlannedSourceRequest{} = request, %SourceWatermark{}) do
    unknown_watermark_warnings(request)
  end

  defp unknown_watermark_warnings(%PlannedSourceRequest{} = request) do
    [
      warning(
        request,
        :watermark_unknown,
        :info,
        "Limits source watermark confidence is unknown",
        %{
          unresolved_capability: :source_watermark
        }
      )
    ]
  end

  defp missing_state_warnings(%PlannedSourceRequest{} = request, observable_id, nil) do
    [
      warning(
        request,
        :unknown_limit_definition,
        :info,
        "No latest observed limit state is available for observable",
        %{observable_id: observable_id}
      )
    ]
  end

  defp missing_state_warnings(%PlannedSourceRequest{}, _observable_id, %Event{}), do: []

  defp missing_interval_warnings(%PlannedSourceRequest{} = request, observable_id, []) do
    [
      warning(
        request,
        :unknown_limit_definition,
        :info,
        "No effective limit definition interval is available for observable",
        %{observable_id: observable_id}
      )
    ]
  end

  defp missing_interval_warnings(%PlannedSourceRequest{}, _observable_id, _intervals), do: []

  defp incomplete_interval_warnings(%PlannedSourceRequest{} = request, observable_id, intervals) do
    incomplete_intervals = Enum.reject(intervals, & &1.complete?)

    if incomplete_intervals == [] do
      []
    else
      [
        warning(
          request,
          :incomplete_limit_definition_intervals,
          :warning,
          "Some limit-definition intervals are missing hydrated definition payloads",
          %{
            observable_id: observable_id,
            missing_limit_definitions:
              Enum.map(incomplete_intervals, fn interval ->
                %{
                  limit_definition_id: interval.limit_definition_id,
                  limit_definition_version: interval.limit_definition_version,
                  limit_definition_lifecycle_event_id:
                    interval.limit_definition_lifecycle_event_id
                }
              end)
          }
        )
      ]
    end
  end

  defp resolve_frames(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings,
         :latest_state
       ) do
    case RecomputedAnalysis.semantics_mode(request) do
      :observed ->
        resolve_observed_latest_state(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts,
          request_warnings
        )

      semantics_mode ->
        resolve_recomputed_latest_state(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts,
          request_warnings,
          semantics_mode
        )
    end
  end

  defp resolve_frames(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings,
         :event_history
       ) do
    case RecomputedAnalysis.semantics_mode(request) do
      :observed ->
        resolve_observed_event_history(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts,
          request_warnings
        )

      semantics_mode ->
        resolve_recomputed_event_history(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts,
          request_warnings,
          semantics_mode
        )
    end
  end

  defp resolve_frames(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings,
         :analysis_buckets
       ) do
    case RecomputedAnalysis.semantics_mode(request) do
      :observed ->
        resolve_observed_analysis_buckets(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts,
          request_warnings
        )

      semantics_mode ->
        resolve_recomputed_analysis_buckets(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts,
          request_warnings,
          semantics_mode
        )
    end
  end

  defp resolve_frames(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings,
         :definition_intervals
       ) do
    resolve_definition_intervals(
      request,
      source_binding,
      organization_id,
      mission_id,
      opts,
      request_warnings
    )
  end

  defp resolve_observed_latest_state(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings
       ) do
    latest_opts = QueryContext.latest_opts(request, source_binding)
    time_warnings = QueryContext.latest_time_warnings(request)
    latest_fun = Keyword.get(opts, :latest_fun, &default_latest/4)

    {frames, frame_warnings} =
      request.observables
      |> Enum.map(fn observable_id ->
        event = latest_fun.(organization_id, mission_id, observable_id, latest_opts)

        intervals =
          QueryContext.selected_definition_intervals(
            request,
            source_binding,
            organization_id,
            mission_id,
            observable_id,
            event,
            opts
          )

        missing_warnings = missing_state_warnings(request, observable_id, event)
        warnings = request_warnings ++ time_warnings ++ missing_warnings

        {latest_frame(request, source_binding, observable_id, event, intervals, warnings),
         missing_warnings}
      end)
      |> Enum.unzip()

    {frames, time_warnings ++ List.flatten(frame_warnings), :latest_limit_state}
  end

  defp resolve_recomputed_latest_state(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings,
         semantics_mode
       ) do
    latest_opts = QueryContext.latest_opts(request, source_binding)
    latest_sample_opts = QueryContext.latest_sample_opts(request, source_binding, opts)
    time_warnings = QueryContext.latest_time_warnings(request)
    latest_sample_fun = Keyword.get(opts, :latest_sample_fun, &default_latest_sample/4)
    interval_fun = Keyword.get(opts, :interval_fun, &default_intervals/4)
    latest_fun = Keyword.get(opts, :latest_fun, &default_latest/4)

    {frames, frame_warnings} =
      request.observables
      |> Enum.map(fn observable_id ->
        sample =
          latest_sample_fun.(organization_id, mission_id, observable_id, latest_sample_opts)

        samples = List.wrap(sample)

        target_intervals =
          QueryContext.selected_recompute_intervals(
            request,
            source_binding,
            interval_fun,
            organization_id,
            mission_id,
            observable_id
          )

        selected_intervals =
          RecomputedAnalysis.selected_intervals_for_samples(
            semantics_mode,
            samples,
            target_intervals
          )

        observed_events =
          RecomputedAnalysis.observed_latest_for_compare(
            semantics_mode,
            latest_fun,
            organization_id,
            mission_id,
            observable_id,
            latest_opts
          )

        {events, divergence_warnings} =
          RecomputedAnalysis.recomputed_events(
            request,
            observable_id,
            samples,
            target_intervals,
            observed_events,
            semantics_mode
          )

        point_warnings =
          RecomputedAnalysis.warnings(
            request,
            observable_id,
            samples,
            selected_intervals,
            events
          ) ++
            divergence_warnings

        warnings = request_warnings ++ time_warnings ++ point_warnings

        {recomputed_latest_frame(
           request,
           source_binding,
           observable_id,
           %{
             event: List.first(events),
             samples: samples,
             selected_intervals: selected_intervals,
             observed_events: observed_events,
             warnings: warnings,
             semantics_mode: semantics_mode
           }
         ), point_warnings}
      end)
      |> Enum.unzip()

    {frames, time_warnings ++ List.flatten(frame_warnings), recomputed_capability(semantics_mode)}
  end

  defp resolve_observed_event_history(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings
       ) do
    {history_opts, time_warnings} = QueryContext.history_opts(request, source_binding)
    history_fun = Keyword.get(opts, :history_fun, &default_history/4)

    frames =
      Enum.map(request.observables, fn observable_id ->
        events = history_fun.(organization_id, mission_id, observable_id, history_opts)

        intervals =
          QueryContext.selected_definition_intervals(
            request,
            source_binding,
            organization_id,
            mission_id,
            observable_id,
            events,
            opts
          )

        event_history_frame(
          request,
          source_binding,
          observable_id,
          events,
          intervals,
          request_warnings ++ time_warnings
        )
      end)

    {frames, time_warnings, :limit_event_history}
  end

  defp resolve_recomputed_event_history(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings,
         semantics_mode
       ) do
    {history_opts, time_warnings} = QueryContext.history_opts(request, source_binding)
    sample_history_opts = QueryContext.sample_history_opts(request, source_binding, opts)
    sample_history_fun = Keyword.get(opts, :sample_history_fun, &default_sample_history/4)
    interval_fun = Keyword.get(opts, :interval_fun, &default_intervals/4)
    history_fun = Keyword.get(opts, :history_fun, &default_history/4)

    {frames, frame_warnings} =
      request.observables
      |> Enum.map(fn observable_id ->
        samples =
          organization_id
          |> then(&sample_history_fun.(&1, mission_id, observable_id, sample_history_opts))
          |> RecomputedAnalysis.normalize_sample_history_result()

        target_intervals =
          QueryContext.selected_recompute_intervals(
            request,
            source_binding,
            interval_fun,
            organization_id,
            mission_id,
            observable_id
          )

        selected_intervals =
          RecomputedAnalysis.selected_intervals_for_samples(
            semantics_mode,
            samples,
            target_intervals
          )

        observed_events =
          RecomputedAnalysis.observed_events_for_compare(
            semantics_mode,
            history_fun,
            organization_id,
            mission_id,
            observable_id,
            history_opts
          )

        {events, divergence_warnings} =
          RecomputedAnalysis.recomputed_events(
            request,
            observable_id,
            samples,
            target_intervals,
            observed_events,
            semantics_mode
          )

        point_warnings =
          RecomputedAnalysis.warnings(
            request,
            observable_id,
            samples,
            selected_intervals,
            events
          ) ++
            divergence_warnings

        warnings =
          request_warnings ++
            time_warnings ++
            point_warnings

        {recomputed_event_history_frame(
           request,
           source_binding,
           observable_id,
           %{
             events: events,
             samples: samples,
             selected_intervals: selected_intervals,
             observed_events: observed_events,
             warnings: warnings,
             semantics_mode: semantics_mode
           }
         ), point_warnings}
      end)
      |> Enum.unzip()

    {frames, time_warnings ++ List.flatten(frame_warnings), recomputed_capability(semantics_mode)}
  end

  defp resolve_observed_analysis_buckets(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings
       ) do
    {history_opts, time_warnings} = QueryContext.history_opts(request, source_binding)
    history_fun = Keyword.get(opts, :history_fun, &default_history/4)

    frames =
      Enum.map(request.observables, fn observable_id ->
        events = history_fun.(organization_id, mission_id, observable_id, history_opts)

        selected_intervals =
          QueryContext.selected_definition_intervals(
            request,
            source_binding,
            organization_id,
            mission_id,
            observable_id,
            events,
            opts
          )

        analysis = %{
          events: events,
          samples: [],
          selected_intervals: selected_intervals,
          observed_events: events,
          warnings: request_warnings ++ time_warnings,
          semantics_mode: :observed
        }

        limit_analysis_bucket_frame(request, source_binding, observable_id, analysis)
      end)

    {frames, time_warnings, :limit_analysis_buckets}
  end

  defp resolve_recomputed_analysis_buckets(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings,
         semantics_mode
       ) do
    {history_opts, time_warnings} = QueryContext.history_opts(request, source_binding)
    sample_history_opts = QueryContext.sample_history_opts(request, source_binding, opts)
    sample_history_fun = Keyword.get(opts, :sample_history_fun, &default_sample_history/4)
    interval_fun = Keyword.get(opts, :interval_fun, &default_intervals/4)
    history_fun = Keyword.get(opts, :history_fun, &default_history/4)

    {frames, frame_warnings} =
      request.observables
      |> Enum.map(fn observable_id ->
        samples =
          organization_id
          |> then(&sample_history_fun.(&1, mission_id, observable_id, sample_history_opts))
          |> RecomputedAnalysis.normalize_sample_history_result()

        target_intervals =
          QueryContext.selected_recompute_intervals(
            request,
            source_binding,
            interval_fun,
            organization_id,
            mission_id,
            observable_id
          )

        selected_intervals =
          RecomputedAnalysis.selected_intervals_for_samples(
            semantics_mode,
            samples,
            target_intervals
          )

        observed_events =
          RecomputedAnalysis.observed_events_for_compare(
            semantics_mode,
            history_fun,
            organization_id,
            mission_id,
            observable_id,
            history_opts
          )

        {events, divergence_warnings} =
          RecomputedAnalysis.recomputed_events(
            request,
            observable_id,
            samples,
            target_intervals,
            observed_events,
            semantics_mode
          )

        point_warnings =
          RecomputedAnalysis.warnings(
            request,
            observable_id,
            samples,
            selected_intervals,
            events
          ) ++
            divergence_warnings

        warnings =
          request_warnings ++
            time_warnings ++
            point_warnings

        {limit_analysis_bucket_frame(
           request,
           source_binding,
           observable_id,
           %{
             events: events,
             samples: samples,
             selected_intervals: selected_intervals,
             observed_events: observed_events,
             warnings: warnings,
             semantics_mode: semantics_mode
           }
         ), point_warnings}
      end)
      |> Enum.unzip()

    {frames, time_warnings ++ List.flatten(frame_warnings), recomputed_capability(semantics_mode)}
  end

  defp resolve_definition_intervals(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings
       ) do
    {interval_opts, time_warnings} = QueryContext.interval_opts(request, source_binding)
    interval_fun = Keyword.get(opts, :interval_fun, &default_intervals/4)

    {frames, frame_warnings} =
      request.observables
      |> Enum.map(fn observable_id ->
        intervals = interval_fun.(organization_id, mission_id, observable_id, interval_opts)

        interval_warnings =
          missing_interval_warnings(request, observable_id, intervals) ++
            incomplete_interval_warnings(request, observable_id, intervals)

        warnings = request_warnings ++ time_warnings ++ interval_warnings

        {definition_interval_frame(request, source_binding, observable_id, intervals, warnings),
         interval_warnings}
      end)
      |> Enum.unzip()

    {frames, time_warnings ++ List.flatten(frame_warnings), :limit_definition_intervals}
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
           message: "Limits source request is missing required context",
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

  defp latest_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         event,
         selected_intervals,
         warnings
       ) do
    FrameBuilder.latest(
      request,
      observable_id,
      event,
      FrameMetadata.latest(
        request,
        source_binding,
        observable_id,
        event,
        selected_intervals,
        warnings,
        frame_source_context(request, source_binding)
      )
    )
  end

  defp recomputed_latest_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         analysis
       ) do
    FrameBuilder.recomputed_latest(
      request,
      observable_id,
      analysis,
      FrameMetadata.recomputed_latest(
        request,
        source_binding,
        observable_id,
        analysis,
        frame_source_context(request, source_binding)
      )
    )
  end

  defp event_history_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         events,
         selected_intervals,
         warnings
       ) do
    FrameBuilder.event_history(
      request,
      observable_id,
      events,
      FrameMetadata.event_history(
        request,
        source_binding,
        observable_id,
        events,
        selected_intervals,
        warnings,
        frame_source_context(request, source_binding)
      )
    )
  end

  defp recomputed_event_history_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         analysis
       ) do
    FrameBuilder.recomputed_event_history(
      request,
      observable_id,
      analysis,
      FrameMetadata.recomputed_event_history(
        request,
        source_binding,
        observable_id,
        analysis,
        frame_source_context(request, source_binding)
      )
    )
  end

  defp limit_analysis_bucket_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         analysis
       ) do
    buckets = RecomputedAnalysis.buckets(request, analysis.events)

    FrameBuilder.analysis_buckets(
      request,
      observable_id,
      analysis.semantics_mode,
      buckets,
      FrameMetadata.analysis_buckets(
        request,
        source_binding,
        observable_id,
        analysis,
        buckets,
        frame_source_context(request, source_binding)
      )
    )
  end

  defp definition_interval_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         intervals,
         warnings
       ) do
    FrameBuilder.definition_intervals(
      request,
      observable_id,
      intervals,
      FrameMetadata.definition_intervals(
        request,
        source_binding,
        observable_id,
        intervals,
        warnings,
        frame_source_context(request, source_binding)
      )
    )
  end

  defp frame_source_context(%PlannedSourceRequest{} = request, source_binding) do
    %{
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request),
      event_limit: event_limit(request)
    }
  end

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

  defp default_latest(nil, mission_id, point_id, opts) do
    LimitReads.latest_state(mission_id, point_id, opts)
  end

  defp default_latest(organization_id, mission_id, point_id, opts) do
    LimitReads.latest_state(organization_id, mission_id, point_id, opts)
  end

  defp default_history(nil, mission_id, point_id, opts) do
    LimitReads.event_history(mission_id, point_id, opts)
  end

  defp default_history(organization_id, mission_id, point_id, opts) do
    LimitReads.event_history(organization_id, mission_id, point_id, opts)
  end

  defp default_intervals(nil, mission_id, point_id, opts) do
    LimitReads.definition_intervals(mission_id, point_id, opts)
  end

  defp default_intervals(organization_id, mission_id, point_id, opts) do
    LimitReads.definition_intervals(organization_id, mission_id, point_id, opts)
  end

  defp default_latest_sample(nil, mission_id, point_id, opts) do
    TelemetryReads.latest_value(mission_id, point_id, opts)
  end

  defp default_latest_sample(organization_id, mission_id, point_id, opts) do
    TelemetryReads.latest_value(organization_id, mission_id, point_id, opts)
  end

  defp default_sample_history(nil, mission_id, point_id, opts) do
    TelemetryReads.sample_history(mission_id, point_id, opts)
  end

  defp default_sample_history(organization_id, mission_id, point_id, opts) do
    TelemetryReads.sample_history(organization_id, mission_id, point_id, opts)
  end

  defp warning(%PlannedSourceRequest{} = request, code, severity, message, details) do
    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: message,
      details: Map.put(details, :source_request_id, request.request_id),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp degraded?(warnings) do
    Enum.any?(warnings, &(&1.severity != :info))
  end

  defp requested_product(%PlannedSourceRequest{} = request) do
    product =
      request
      |> sampling_products()
      |> List.first()
      |> case do
        nil -> product_for_mode(sampling_mode(request))
        value -> normalize_atom(value)
      end

    if product in @supported_products do
      {:ok, product}
    else
      {:warning,
       warning(
         request,
         :unsupported_limits_product,
         :warning,
         "Limits source supports latest state, event history, definition interval, and analysis bucket products only",
         %{requested_product: product, supported_products: @supported_products}
       )}
    end
  end

  defp sampling_products(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :products) do
      products when is_list(products) -> products
      product when not is_nil(product) -> [product]
      _other -> []
    end
  end

  defp product_for_mode(mode) when mode in [:latest_state, :latest], do: :latest_state
  defp product_for_mode(:event_history), do: :event_history
  defp product_for_mode(:analysis_buckets), do: :analysis_buckets
  defp product_for_mode(:intervals), do: :definition_intervals
  defp product_for_mode(:definition_intervals), do: :definition_intervals
  defp product_for_mode(mode), do: mode

  defp supported_capability(%PlannedSourceRequest{} = request) do
    case requested_product(request) do
      {:ok, :event_history} -> :limit_event_history
      {:ok, :analysis_buckets} -> :limit_analysis_buckets
      {:ok, :definition_intervals} -> :limit_definition_intervals
      _other -> :latest_limit_state
    end
  end

  defp sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> context_value(:mode)
    |> normalize_atom()
  end

  defp event_limit(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :limit) || context_value(sampling, :max_events) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_event_limit)
      _other -> @default_event_limit
    end
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
