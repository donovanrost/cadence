defmodule Cadence.Dashboards.Sources.Limits do
  @moduledoc """
  Dashboard limits source adapter.

  v0 resolves latest observed telemetry limit-state projections, capped observed
  limit-event history, and effective limit-definition intervals.
  """

  alias Cadence.Dashboards.{
    DataContext,
    DataLinks,
    DataSourceRegistry,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    ScopeContext,
    SourceCapabilities,
    SourceFacts,
    SourceResult,
    SourceWatermark
  }

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
        watermark_for_request(request, source_binding, organization_id, mission_id, opts)

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
        watermark_for_request(request, source_binding, organization_id, mission_id, opts)

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
    latest_opts = latest_opts(request, source_binding)
    time_warnings = latest_time_warnings(request)
    latest_fun = Keyword.get(opts, :latest_fun, &default_latest/4)

    {frames, frame_warnings} =
      request.observables
      |> Enum.map(fn observable_id ->
        event = latest_fun.(organization_id, mission_id, observable_id, latest_opts)

        intervals =
          selected_definition_intervals(
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
    latest_opts = latest_opts(request, source_binding)
    latest_sample_opts = latest_sample_opts(request, source_binding, opts)
    time_warnings = latest_time_warnings(request)
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
          selected_recompute_intervals(
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
    {history_opts, time_warnings} = history_opts(request, source_binding)
    history_fun = Keyword.get(opts, :history_fun, &default_history/4)

    frames =
      Enum.map(request.observables, fn observable_id ->
        events = history_fun.(organization_id, mission_id, observable_id, history_opts)

        intervals =
          selected_definition_intervals(
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
    {history_opts, time_warnings} = history_opts(request, source_binding)
    sample_history_opts = sample_history_opts(request, source_binding, opts)
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
          selected_recompute_intervals(
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
    {history_opts, time_warnings} = history_opts(request, source_binding)
    history_fun = Keyword.get(opts, :history_fun, &default_history/4)

    frames =
      Enum.map(request.observables, fn observable_id ->
        events = history_fun.(organization_id, mission_id, observable_id, history_opts)

        selected_intervals =
          selected_definition_intervals(
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
    {history_opts, time_warnings} = history_opts(request, source_binding)
    sample_history_opts = sample_history_opts(request, source_binding, opts)
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
          selected_recompute_intervals(
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
    {interval_opts, time_warnings} = interval_opts(request, source_binding)
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

  defp latest_opts(%PlannedSourceRequest{} = request, source_binding) do
    [
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
      data_source_id: data_source_id(request, source_binding),
      dataset: dataset(source_binding),
      semantics_mode: RecomputedAnalysis.semantics_mode(request),
      spacecraft_id: spacecraft_id(request.scope_context),
      to_receipt_time: latest_as_of_receipt_time(request)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp latest_sample_opts(%PlannedSourceRequest{} = request, source_binding, adapter_opts) do
    request
    |> latest_opts(source_binding)
    |> put_telemetry_sample_source_context(request, adapter_opts)
  end

  defp history_opts(%PlannedSourceRequest{} = request, source_binding) do
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
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

    {opts, time_warnings}
  end

  defp sample_history_opts(%PlannedSourceRequest{} = request, source_binding, adapter_opts) do
    {opts, _time_warnings} = history_opts(request, source_binding)

    put_telemetry_sample_source_context(opts, request, adapter_opts)
  end

  defp interval_opts(%PlannedSourceRequest{} = request, source_binding) do
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
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

    {opts, time_warnings}
  end

  defp selected_definition_intervals(
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
      {interval_opts, _time_warnings} = interval_opts(request, source_binding)

      interval_fun.(organization_id, mission_id, observable_id, interval_opts)
      |> Enum.filter(&interval_selected_for_times?(&1, event_times))
      |> Enum.uniq_by(& &1.definition_activation_key)
    else
      _other -> []
    end
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

  defp selected_recompute_intervals(
         %PlannedSourceRequest{} = request,
         source_binding,
         interval_fun,
         organization_id,
         mission_id,
         observable_id
       ) do
    {interval_opts, _time_warnings} = interval_opts(request, source_binding)

    interval_fun.(organization_id, mission_id, observable_id, interval_opts)
    |> Enum.filter(& &1.complete?)
    |> Enum.sort_by(&interval_sort_key/1, {:desc, DateTime})
  end

  defp interval_sort_key(%DefinitionInterval{active_from: %DateTime{} = active_from}),
    do: active_from

  defp interval_sort_key(%DefinitionInterval{}), do: DateTime.from_unix!(0)

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

  defp latest_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         event,
         selected_intervals,
         warnings
       ) do
    events = List.wrap(event)
    times = Enum.map(events, &event_time/1)
    time_axis = latest_time_axis(event)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :limits,
      shape: :scalar,
      time_axis: time_axis,
      scope: request.scope_context,
      fields: [
        %Field{name: "time", kind: :time, values: times, metadata: %{axis: time_axis}},
        %Field{
          name: "normalized_state",
          kind: :enum,
          values: Enum.map(events, & &1.normalized_state)
        },
        %Field{name: "limit_state", kind: :enum, values: Enum.map(events, & &1.limit_state)},
        %Field{name: "violation", kind: :boolean, values: Enum.map(events, & &1.violation)}
      ],
      meta:
        frame_meta(request, source_binding, observable_id, event, selected_intervals, warnings)
    }
  end

  defp recomputed_latest_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         analysis
       ) do
    event = analysis.event
    events = List.wrap(event)
    observed_events = analysis.observed_events
    semantics_mode = analysis.semantics_mode
    time_axis = latest_time_axis(event)
    times = Enum.map(events, &event_time/1)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}:latest_state:#{semantics_mode}",
      source: :limits,
      shape: :scalar,
      time_axis: time_axis,
      scope: request.scope_context,
      fields: recomputed_latest_fields(events, observed_events, semantics_mode, times, time_axis),
      meta: recomputed_latest_meta(request, source_binding, observable_id, analysis)
    }
  end

  defp recomputed_latest_fields(events, observed_events, semantics_mode, times, time_axis) do
    base_fields = [
      %Field{name: "time", kind: :time, values: times, metadata: %{axis: time_axis}},
      %Field{name: "sample_id", kind: :string, values: Enum.map(events, & &1.sample_id)},
      %Field{
        name: "limit_definition_id",
        kind: :string,
        values: Enum.map(events, & &1.limit_definition_id)
      },
      %Field{
        name: "limit_definition_version",
        kind: :number,
        values: Enum.map(events, & &1.limit_definition_version)
      },
      %Field{
        name: "normalized_state",
        kind: :enum,
        values: Enum.map(events, & &1.normalized_state)
      },
      %Field{name: "limit_state", kind: :enum, values: Enum.map(events, & &1.limit_state)},
      %Field{name: "violation", kind: :boolean, values: Enum.map(events, & &1.violation)}
    ]

    if semantics_mode == :compare do
      observed_by_sample_id = Map.new(observed_events, &{&1.sample_id, &1})

      base_fields ++
        [
          %Field{
            name: "observed_limit_event_id",
            kind: :string,
            values:
              Enum.map(
                events,
                &(observed_by_sample_id[&1.sample_id] &&
                    observed_by_sample_id[&1.sample_id].limit_event_id)
              )
          },
          %Field{
            name: "observed_normalized_state",
            kind: :enum,
            values: Enum.map(events, &Map.get(&1.provenance, "observed_normalized_state"))
          },
          %Field{
            name: "limit_state_diverged",
            kind: :boolean,
            values: Enum.map(events, &Map.get(&1.provenance, "limit_state_diverged?"))
          }
        ]
    else
      base_fields
    end
  end

  defp event_history_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         events,
         selected_intervals,
         warnings
       ) do
    times = Enum.map(events, & &1.receipt_time)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :limits,
      shape: :events,
      time_axis: :receipt_time,
      scope: request.scope_context,
      fields: [
        %Field{name: "time", kind: :time, values: times, metadata: %{axis: :receipt_time}},
        %Field{
          name: "limit_event_id",
          kind: :string,
          values: Enum.map(events, & &1.limit_event_id)
        },
        %Field{name: "sample_id", kind: :string, values: Enum.map(events, & &1.sample_id)},
        %Field{
          name: "limit_definition_id",
          kind: :string,
          values: Enum.map(events, & &1.limit_definition_id)
        },
        %Field{
          name: "limit_definition_version",
          kind: :number,
          values: Enum.map(events, & &1.limit_definition_version)
        },
        %Field{
          name: "normalized_state",
          kind: :enum,
          values: Enum.map(events, & &1.normalized_state)
        },
        %Field{name: "limit_state", kind: :enum, values: Enum.map(events, & &1.limit_state)},
        %Field{name: "violation", kind: :boolean, values: Enum.map(events, & &1.violation)}
      ],
      meta:
        event_history_meta(
          request,
          source_binding,
          observable_id,
          events,
          selected_intervals,
          warnings
        )
    }
  end

  defp recomputed_event_history_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         analysis
       ) do
    events = analysis.events
    observed_events = analysis.observed_events
    semantics_mode = analysis.semantics_mode
    times = Enum.map(events, & &1.receipt_time)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}:#{semantics_mode}",
      source: :limits,
      shape: :events,
      time_axis: :receipt_time,
      scope: request.scope_context,
      fields: recomputed_event_fields(events, observed_events, semantics_mode, times),
      meta:
        recomputed_event_history_meta(
          request,
          source_binding,
          observable_id,
          analysis
        )
    }
  end

  defp recomputed_event_fields(events, observed_events, semantics_mode, times) do
    base_fields = [
      %Field{name: "time", kind: :time, values: times, metadata: %{axis: :receipt_time}},
      %Field{name: "sample_id", kind: :string, values: Enum.map(events, & &1.sample_id)},
      %Field{
        name: "limit_definition_id",
        kind: :string,
        values: Enum.map(events, & &1.limit_definition_id)
      },
      %Field{
        name: "limit_definition_version",
        kind: :number,
        values: Enum.map(events, & &1.limit_definition_version)
      },
      %Field{
        name: "normalized_state",
        kind: :enum,
        values: Enum.map(events, & &1.normalized_state)
      },
      %Field{name: "limit_state", kind: :enum, values: Enum.map(events, & &1.limit_state)},
      %Field{name: "violation", kind: :boolean, values: Enum.map(events, & &1.violation)}
    ]

    if semantics_mode == :compare do
      observed_by_sample_id = Map.new(observed_events, &{&1.sample_id, &1})

      base_fields ++
        [
          %Field{
            name: "observed_limit_event_id",
            kind: :string,
            values:
              Enum.map(
                events,
                &(observed_by_sample_id[&1.sample_id] &&
                    observed_by_sample_id[&1.sample_id].limit_event_id)
              )
          },
          %Field{
            name: "observed_normalized_state",
            kind: :enum,
            values: Enum.map(events, &Map.get(&1.provenance, "observed_normalized_state"))
          },
          %Field{
            name: "limit_state_diverged",
            kind: :boolean,
            values: Enum.map(events, &Map.get(&1.provenance, "limit_state_diverged?"))
          }
        ]
    else
      base_fields
    end
  end

  defp limit_analysis_bucket_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         analysis
       ) do
    buckets = RecomputedAnalysis.buckets(request, analysis.events)
    semantics_mode = analysis.semantics_mode

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}:analysis_buckets:#{semantics_mode}",
      source: :limits,
      shape: :events,
      time_axis: :receipt_time,
      scope: request.scope_context,
      fields: limit_analysis_bucket_fields(buckets),
      meta:
        limit_analysis_bucket_meta(
          request,
          source_binding,
          observable_id,
          analysis,
          buckets
        )
    }
  end

  defp limit_analysis_bucket_fields(buckets) do
    [
      %Field{
        name: "time",
        kind: :time,
        values: Enum.map(buckets, & &1.bucket_start),
        metadata: %{axis: :receipt_time}
      },
      %Field{
        name: "bucket_start",
        kind: :time,
        values: Enum.map(buckets, & &1.bucket_start),
        metadata: %{axis: :receipt_time}
      },
      %Field{
        name: "bucket_end",
        kind: :time,
        values: Enum.map(buckets, & &1.bucket_end),
        metadata: %{axis: :receipt_time}
      },
      %Field{name: "event_count", kind: :number, values: Enum.map(buckets, & &1.event_count)},
      %Field{
        name: "limit_event_id",
        kind: :string,
        values: Enum.map(buckets, & &1.limit_event_id)
      },
      %Field{name: "sample_id", kind: :string, values: Enum.map(buckets, & &1.sample_id)},
      %Field{
        name: "limit_event_ids",
        kind: :string,
        values: Enum.map(buckets, & &1.limit_event_ids)
      },
      %Field{name: "sample_ids", kind: :string, values: Enum.map(buckets, & &1.sample_ids)},
      %Field{
        name: "limit_definition_id",
        kind: :string,
        values: Enum.map(buckets, & &1.limit_definition_id)
      },
      %Field{
        name: "limit_definition_version",
        kind: :number,
        values: Enum.map(buckets, & &1.limit_definition_version)
      },
      %Field{
        name: "limit_set_name",
        kind: :string,
        values: Enum.map(buckets, & &1.limit_set_name)
      },
      %Field{
        name: "normalized_state",
        kind: :enum,
        values: Enum.map(buckets, & &1.normalized_state)
      },
      %Field{name: "limit_state", kind: :enum, values: Enum.map(buckets, & &1.limit_state)},
      %Field{name: "violation", kind: :boolean, values: Enum.map(buckets, & &1.violation)},
      %Field{
        name: "observed_normalized_state",
        kind: :enum,
        values: Enum.map(buckets, & &1.observed_normalized_state)
      },
      %Field{
        name: "limit_state_diverged",
        kind: :boolean,
        values: Enum.map(buckets, & &1.limit_state_diverged)
      },
      %Field{
        name: "limit_divergence_count",
        kind: :number,
        values: Enum.map(buckets, & &1.limit_divergence_count)
      }
    ]
  end

  defp definition_interval_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         intervals,
         warnings
       ) do
    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :limits,
      shape: :intervals,
      time_axis: :receipt_time,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "active_from",
          kind: :time,
          values: Enum.map(intervals, & &1.active_from),
          metadata: %{axis: :receipt_time}
        },
        %Field{
          name: "active_to",
          kind: :time,
          values: Enum.map(intervals, & &1.active_to),
          metadata: %{axis: :receipt_time, open_ended?: true}
        },
        %Field{
          name: "limit_definition_id",
          kind: :string,
          values: Enum.map(intervals, & &1.limit_definition_id)
        },
        %Field{
          name: "limit_definition_version",
          kind: :number,
          values: Enum.map(intervals, & &1.limit_definition_version)
        },
        %Field{
          name: "limit_set_name",
          kind: :string,
          values: Enum.map(intervals, & &1.limit_set_name)
        },
        %Field{name: "red_low", kind: :number, values: threshold_values(intervals, "red_low")},
        %Field{
          name: "yellow_low",
          kind: :number,
          values: threshold_values(intervals, "yellow_low")
        },
        %Field{
          name: "yellow_high",
          kind: :number,
          values: threshold_values(intervals, "yellow_high")
        },
        %Field{name: "red_high", kind: :number, values: threshold_values(intervals, "red_high")}
      ],
      meta: definition_interval_meta(request, source_binding, observable_id, intervals, warnings)
    }
  end

  defp frame_meta(request, source_binding, observable_id, event, selected_intervals, warnings) do
    %{
      source_request_id: request.request_id,
      observable_id: observable_id,
      point_id: observable_id,
      logical_source: :limits,
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      sampling: :latest_state,
      semantics_mode: :observed,
      analysis_basis: :observed_fact,
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request),
      returned_points: event_count(event),
      evidence:
        DataLinks.limit_event_evidence_refs(List.wrap(event)) ++
          DataLinks.limit_definition_interval_evidence_refs(selected_intervals),
      links:
        DataLinks.limit_links(request, observable_id, List.wrap(event),
          source: :frame,
          source_binding: source_binding
        ),
      warning_codes: Enum.map(warnings, & &1.code)
    }
    |> maybe_put_selected_limit_definition_intervals(selected_intervals)
    |> maybe_put_event_meta(event)
  end

  defp recomputed_latest_meta(request, source_binding, observable_id, analysis) do
    event = analysis.event
    events = List.wrap(event)
    samples = analysis.samples
    selected_intervals = analysis.selected_intervals
    observed_events = analysis.observed_events
    warnings = analysis.warnings
    semantics_mode = analysis.semantics_mode

    %{
      source_request_id: request.request_id,
      observable_id: observable_id,
      point_id: observable_id,
      logical_source: :limits,
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      sampling: :latest_state,
      semantics_mode: semantics_mode,
      analysis_basis: RecomputedAnalysis.analysis_basis(semantics_mode),
      synthetic_limit_analysis?: true,
      selected_limit_clock: RecomputedAnalysis.limit_clock_policy(request),
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request),
      returned_points: event_count(event),
      source_sample_count: length(samples),
      observed_event_count: length(observed_events),
      divergence_count: RecomputedAnalysis.divergence_count(events),
      evidence:
        DataLinks.telemetry_sample_evidence_refs(samples) ++
          DataLinks.limit_definition_interval_evidence_refs(selected_intervals) ++
          DataLinks.limit_event_evidence_refs(observed_events),
      links:
        DataLinks.limit_links(request, observable_id, observed_events,
          source: :frame,
          source_binding: source_binding
        ) ++
          DataLinks.telemetry_links(request, observable_id, samples,
            source: :frame,
            source_binding: source_binding
          ),
      warning_codes: Enum.map(warnings, & &1.code)
    }
    |> maybe_put_selected_limit_definition_intervals(selected_intervals)
    |> maybe_put_event_meta(event)
  end

  defp maybe_put_event_meta(meta, nil), do: meta

  defp maybe_put_event_meta(meta, %Event{} = event) do
    meta
    |> Map.merge(%{
      sample_id: event.sample_id,
      limit_event_id: event.limit_event_id,
      limit_definition_id: event.limit_definition_id,
      limit_definition_version: event.limit_definition_version,
      limit_set_name: event.limit_set_name,
      source_sample_type: event.source_sample_type
    })
    |> maybe_put_limit_activation_meta(event.provenance)
  end

  defp maybe_put_limit_activation_meta(meta, provenance) when is_map(provenance) do
    meta
    |> maybe_put_provenance_value(provenance, :definition_activation_key)
    |> maybe_put_provenance_value(provenance, :limit_definition_lifecycle_event_id)
    |> maybe_put_provenance_value(provenance, :limit_activation_event_id)
    |> maybe_put_provenance_value(provenance, :limit_activation_event_type)
    |> maybe_put_provenance_value(provenance, :active_from)
  end

  defp maybe_put_limit_activation_meta(meta, _provenance), do: meta

  defp maybe_put_provenance_value(meta, provenance, key) do
    case Map.get(provenance, Atom.to_string(key)) do
      nil -> meta
      value -> Map.put(meta, key, value)
    end
  end

  defp event_history_meta(
         request,
         source_binding,
         observable_id,
         events,
         selected_intervals,
         warnings
       ) do
    %{
      source_request_id: request.request_id,
      observable_id: observable_id,
      point_id: observable_id,
      logical_source: :limits,
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      sampling: :event_history,
      semantics_mode: :observed,
      analysis_basis: :observed_fact,
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request),
      returned_events: length(events),
      truncated?: length(events) >= event_limit(request),
      evidence:
        DataLinks.limit_event_evidence_refs(events) ++
          DataLinks.limit_definition_interval_evidence_refs(selected_intervals),
      links:
        DataLinks.limit_links(request, observable_id, events,
          source: :frame,
          source_binding: source_binding
        ),
      warning_codes: Enum.map(warnings, & &1.code)
    }
    |> maybe_put_selected_limit_definition_intervals(selected_intervals)
  end

  defp recomputed_event_history_meta(
         request,
         source_binding,
         observable_id,
         analysis
       ) do
    events = analysis.events
    samples = analysis.samples
    selected_intervals = analysis.selected_intervals
    observed_events = analysis.observed_events
    warnings = analysis.warnings
    semantics_mode = analysis.semantics_mode

    %{
      source_request_id: request.request_id,
      observable_id: observable_id,
      point_id: observable_id,
      logical_source: :limits,
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      sampling: :event_history,
      semantics_mode: semantics_mode,
      analysis_basis: RecomputedAnalysis.analysis_basis(semantics_mode),
      synthetic_limit_analysis?: true,
      selected_limit_clock: RecomputedAnalysis.limit_clock_policy(request),
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request),
      returned_events: length(events),
      source_sample_count: length(samples),
      observed_event_count: length(observed_events),
      divergence_count: RecomputedAnalysis.divergence_count(events),
      truncated?: length(events) >= event_limit(request),
      evidence:
        DataLinks.telemetry_sample_evidence_refs(samples) ++
          DataLinks.limit_definition_interval_evidence_refs(selected_intervals) ++
          DataLinks.limit_event_evidence_refs(observed_events),
      links:
        DataLinks.limit_links(request, observable_id, observed_events,
          source: :frame,
          source_binding: source_binding
        ) ++
          DataLinks.telemetry_links(request, observable_id, samples,
            source: :frame,
            source_binding: source_binding
          ),
      warning_codes: Enum.map(warnings, & &1.code)
    }
    |> maybe_put_selected_limit_definition_intervals(selected_intervals)
  end

  defp limit_analysis_bucket_meta(
         request,
         source_binding,
         observable_id,
         analysis,
         buckets
       ) do
    events = analysis.events
    samples = analysis.samples
    selected_intervals = analysis.selected_intervals
    observed_events = analysis.observed_events
    warnings = analysis.warnings
    semantics_mode = analysis.semantics_mode

    %{
      source_request_id: request.request_id,
      observable_id: observable_id,
      point_id: observable_id,
      logical_source: :limits,
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      sampling: :analysis_buckets,
      semantics_mode: semantics_mode,
      analysis_basis: RecomputedAnalysis.analysis_basis(semantics_mode),
      selected_limit_clock: RecomputedAnalysis.limit_clock_policy(request),
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request),
      bucket_width_ms: RecomputedAnalysis.bucket_width_ms(request),
      returned_buckets: length(buckets),
      returned_events: length(events),
      source_sample_count: length(samples),
      observed_event_count: length(observed_events),
      divergence_count: RecomputedAnalysis.divergence_count(events),
      truncated?: length(events) >= event_limit(request),
      evidence:
        DataLinks.telemetry_sample_evidence_refs(samples) ++
          DataLinks.limit_definition_interval_evidence_refs(selected_intervals) ++
          DataLinks.limit_event_evidence_refs(observed_events),
      links:
        DataLinks.limit_links(request, observable_id, observed_events,
          source: :frame,
          source_binding: source_binding
        ) ++
          DataLinks.telemetry_links(request, observable_id, samples,
            source: :frame,
            source_binding: source_binding
          ),
      warning_codes: Enum.map(warnings, & &1.code)
    }
    |> maybe_put_synthetic_limit_analysis(semantics_mode)
    |> maybe_put_selected_limit_definition_intervals(selected_intervals)
  end

  defp maybe_put_synthetic_limit_analysis(meta, :observed), do: meta

  defp maybe_put_synthetic_limit_analysis(meta, _semantics_mode) do
    Map.put(meta, :synthetic_limit_analysis?, true)
  end

  defp definition_interval_meta(request, source_binding, observable_id, intervals, warnings) do
    %{
      source_request_id: request.request_id,
      observable_id: observable_id,
      point_id: observable_id,
      logical_source: :limits,
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      sampling: :definition_intervals,
      semantics_mode: :observed,
      analysis_basis: :observed_fact,
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request),
      returned_intervals: length(intervals),
      incomplete_intervals?: Enum.any?(intervals, &(not &1.complete?)),
      evidence: DataLinks.limit_definition_interval_evidence_refs(intervals),
      links:
        DataLinks.limit_links(request, observable_id, intervals,
          source: :frame,
          source_binding: source_binding
        ),
      activation_evidence: Enum.map(intervals, &activation_evidence/1),
      warning_codes: Enum.map(warnings, & &1.code)
    }
  end

  defp threshold_values(intervals, threshold_name) do
    Enum.map(intervals, fn %DefinitionInterval{} = interval ->
      Map.get(interval.thresholds || %{}, threshold_name)
    end)
  end

  defp activation_evidence(%DefinitionInterval{} = interval) do
    %{
      definition_activation_key: interval.definition_activation_key,
      limit_definition_lifecycle_event_id: interval.limit_definition_lifecycle_event_id,
      limit_definition_id: interval.limit_definition_id,
      limit_definition_version: interval.limit_definition_version,
      limit_set_name: interval.limit_set_name,
      point_id: interval.point_id,
      scope_type: interval.scope_type,
      scope_ref: interval.scope_ref,
      realm: interval.realm,
      event_type: interval.event_type,
      active_from: interval.active_from,
      active_to: interval.active_to,
      observed_at: interval.observed_at,
      complete?: interval.complete?
    }
  end

  defp maybe_put_selected_limit_definition_intervals(meta, []), do: meta

  defp maybe_put_selected_limit_definition_intervals(meta, intervals) do
    Map.put(
      meta,
      :selected_limit_definition_intervals,
      Enum.map(intervals, &activation_evidence/1)
    )
  end

  defp latest_time_axis(%Event{generation_time: %DateTime{}}), do: :generation_time
  defp latest_time_axis(_event), do: :receipt_time

  defp event_time(%Event{generation_time: %DateTime{} = generation_time}), do: generation_time
  defp event_time(%Event{receipt_time: receipt_time}), do: receipt_time

  defp event_count(%Event{}), do: 1
  defp event_count(nil), do: 0

  defp watermark_for_request(
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

  defp watermark(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if watermarks_supported?(source_binding) do
      watermark_fun = Keyword.get(opts, :watermark_fun, &default_watermark/4)
      watermark_opts = watermark_opts(request, source_binding)

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

    point_watermarks =
      Map.new(normalized_results, fn {observable_id, result} ->
        {observable_id, result}
      end)

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

  defp watermark_opts(%PlannedSourceRequest{} = request, source_binding) do
    [
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
      data_source_id: data_source_id(request, source_binding),
      dataset: dataset(source_binding),
      semantics_mode: RecomputedAnalysis.semantics_mode(request),
      spacecraft_id: spacecraft_id(request.scope_context)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp watermarks_supported?(%{data_source: %{capabilities: capabilities}})
       when is_map(capabilities) do
    Map.get(capabilities, :watermarks?, Map.get(capabilities, "watermarks?")) == true
  end

  defp watermarks_supported?(_source_binding), do: false

  defp source_binding_id(%{binding: %{binding_id: binding_id}}), do: binding_id
  defp source_binding_id(_source_binding), do: nil

  defp put_telemetry_sample_source_context(
         opts,
         %PlannedSourceRequest{} = request,
         adapter_opts
       ) do
    if explicit_logical_source_context?(request, :telemetry) do
      put_logical_source_context(opts, request, :telemetry)
    else
      put_resolved_telemetry_source_context(opts, request, adapter_opts)
    end
  end

  defp put_logical_source_context(opts, %PlannedSourceRequest{} = request, logical_source) do
    [:realm, :data_source_id, :source_binding_id, :dataset, :replay_run_id]
    |> Enum.reduce(opts, fn key, opts ->
      case DataContext.source_value(request.data_context, logical_source, key) do
        nil -> opts
        "" -> opts
        value -> Keyword.put(opts, key, value)
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
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp put_opts(source_opts, opts) do
    Enum.reduce(source_opts, opts, fn {key, value}, opts -> Keyword.put(opts, key, value) end)
  end

  defp registry_opts(adapter_opts) do
    adapter_opts
    |> Keyword.take([
      :data_sources,
      :data_bindings,
      :source_health_statuses,
      :persisted?,
      :source_binding_at,
      :source_binding_range
    ])
  end

  defp explicit_logical_source_context?(%PlannedSourceRequest{} = request, logical_source) do
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

  defp present_context_value?(nil), do: false
  defp present_context_value?(""), do: false
  defp present_context_value?(_value), do: true

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

  defp default_watermark(nil, _mission_id, _point_id, _opts) do
    {:error, :missing_tenant_context}
  end

  defp default_watermark(organization_id, mission_id, point_id, opts) do
    LimitReads.watermark_result(organization_id, mission_id, point_id, opts)
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

  defp time_axis(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> context_value(:axis)
    |> normalize_atom()
  end

  defp time_range_requested?(time_context) do
    mode = time_context |> context_value(:mode) |> normalize_atom()

    mode in [:archive, :range] or
      not is_nil(first_context_value(time_context, [:from, :start, :start_time])) or
      not is_nil(first_context_value(time_context, [:to, :end, :end_time]))
  end

  defp event_limit(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :limit) || context_value(sampling, :max_events) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_event_limit)
      _other -> @default_event_limit
    end
  end

  defp spacecraft_id(scope_context) do
    ScopeContext.scope_id(scope_context, :spacecraft)
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

  defp first_context_value(context, keys) do
    keys
    |> Enum.find_value(&context_value(context, &1))
  end

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
