defmodule Cadence.Dashboards.Sources.Limits.RecomputedAnalysis do
  @moduledoc """
  Recomputes limit state from telemetry samples and target definitions.

  This module owns synthetic limit events, observed-versus-recomputed
  comparison, analysis buckets, and the warnings produced by incomplete or
  divergent recomputation.
  """

  alias Cadence.Dashboards.{DataLinks, PlannedSourceRequest, ResolveWarning}
  alias Cadence.Limits.{DefinitionInterval, Evaluator, Event}
  alias Cadence.Telemetry.Sample

  @spec analysis_basis(atom()) :: atom()
  def analysis_basis(:current), do: :current_definition_analysis
  def analysis_basis(:recomputed), do: :recomputed_analysis
  def analysis_basis(:compare), do: :limit_comparison_analysis
  def analysis_basis(_semantics_mode), do: :unsupported_analysis

  @spec limit_clock_policy(PlannedSourceRequest.t()) :: map()
  def limit_clock_policy(%PlannedSourceRequest{} = request) do
    %{
      observed: :limit_event_receipt_time,
      requested_time_axis: time_axis(request),
      requested_time_mode: context_value(request.time_context, :mode)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec semantics_mode(PlannedSourceRequest.t()) :: term()
  def semantics_mode(%PlannedSourceRequest{} = request) do
    mode =
      context_value(request.limit_context, :semantics_mode) ||
        context_value(request.data_context, :semantics_mode)

    normalize_semantics_mode(mode)
  end

  @spec interval_contains_time?(DefinitionInterval.t(), DateTime.t()) :: boolean()
  def interval_contains_time?(
        %DefinitionInterval{active_from: %DateTime{} = active_from, active_to: active_to},
        %DateTime{} = time
      ) do
    DateTime.compare(active_from, time) != :gt and interval_ends_after?(active_to, time)
  end

  def interval_contains_time?(%DefinitionInterval{}, %DateTime{}), do: false

  @spec selected_intervals_for_samples(atom(), [Sample.t()], [DefinitionInterval.t()]) ::
          [DefinitionInterval.t()]
  def selected_intervals_for_samples(_semantics_mode, [], _intervals), do: []

  def selected_intervals_for_samples(:current, _samples, intervals) do
    intervals
    |> List.first()
    |> List.wrap()
  end

  def selected_intervals_for_samples(_semantics_mode, samples, intervals) do
    samples
    |> Enum.map(&interval_for_sample(&1, intervals))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.definition_activation_key)
  end

  @spec observed_events_for_compare(
          atom(),
          function(),
          binary() | nil,
          binary(),
          binary(),
          keyword()
        ) :: [Event.t()]
  def observed_events_for_compare(
        :compare,
        history_fun,
        organization_id,
        mission_id,
        observable_id,
        opts
      ) do
    history_fun.(organization_id, mission_id, observable_id, opts)
  end

  def observed_events_for_compare(
        _semantics_mode,
        _history_fun,
        _organization_id,
        _mission_id,
        _observable_id,
        _opts
      ) do
    []
  end

  @spec observed_latest_for_compare(
          atom(),
          function(),
          binary() | nil,
          binary(),
          binary(),
          keyword()
        ) :: [Event.t()]
  def observed_latest_for_compare(
        :compare,
        latest_fun,
        organization_id,
        mission_id,
        observable_id,
        opts
      ) do
    opts = Keyword.put(opts, :semantics_mode, :observed)
    latest_fun.(organization_id, mission_id, observable_id, opts) |> List.wrap()
  end

  def observed_latest_for_compare(
        _semantics_mode,
        _latest_fun,
        _organization_id,
        _mission_id,
        _observable_id,
        _opts
      ) do
    []
  end

  @spec normalize_sample_history_result(term()) :: [Sample.t()]
  def normalize_sample_history_result({:ok, %{samples: samples}}) when is_list(samples),
    do: samples

  def normalize_sample_history_result(samples) when is_list(samples), do: samples
  def normalize_sample_history_result(_other), do: []

  @spec recomputed_events(
          PlannedSourceRequest.t(),
          binary(),
          [Sample.t()],
          [DefinitionInterval.t()],
          [Event.t()],
          atom()
        ) :: {[Event.t()], [ResolveWarning.t()]}
  def recomputed_events(
        %PlannedSourceRequest{} = request,
        observable_id,
        samples,
        intervals,
        observed_events,
        semantics_mode
      ) do
    observed_by_sample_id = Map.new(observed_events, &{&1.sample_id, &1})

    events =
      Enum.flat_map(samples, fn %Sample{} = sample ->
        case recompute_interval_for_sample(semantics_mode, intervals, sample) do
          %DefinitionInterval{} = interval ->
            observed_event = Map.get(observed_by_sample_id, sample.sample_id)

            [
              recomputed_limit_event(
                request,
                observable_id,
                sample,
                interval,
                observed_event,
                semantics_mode
              )
            ]

          nil ->
            []
        end
      end)

    {events, divergence_warnings(request, observable_id, events, semantics_mode)}
  end

  @spec buckets(PlannedSourceRequest.t(), [Event.t()]) :: [map()]
  def buckets(%PlannedSourceRequest{} = request, events) do
    bucket_width_ms = bucket_width_ms(request)

    events
    |> Enum.filter(&match?(%Event{receipt_time: %DateTime{}}, &1))
    |> Enum.group_by(&bucket_group_key(&1, request, bucket_width_ms))
    |> Enum.map(fn {{bucket_start, _definition_key}, bucket_events} ->
      bucket_end =
        DateTime.from_unix!(
          DateTime.to_unix(bucket_start, :millisecond) + bucket_width_ms,
          :millisecond
        )

      sorted_events =
        Enum.sort_by(bucket_events, &DateTime.to_unix(&1.receipt_time, :millisecond))

      worst_event = Enum.max_by(sorted_events, &Evaluator.severity(&1.limit_state))

      %{
        bucket_start: bucket_start,
        bucket_end: bucket_end,
        event_count: length(sorted_events),
        limit_event_id: worst_event.limit_event_id,
        sample_id: worst_event.sample_id,
        limit_event_ids: sorted_events |> Enum.map(& &1.limit_event_id) |> Enum.reject(&is_nil/1),
        sample_ids: sorted_events |> Enum.map(& &1.sample_id) |> Enum.reject(&is_nil/1),
        limit_definition_id: worst_event.limit_definition_id,
        limit_definition_version: worst_event.limit_definition_version,
        limit_set_name: worst_event.limit_set_name,
        normalized_state: worst_event.normalized_state,
        limit_state: worst_event.limit_state,
        violation: worst_event.violation,
        observed_normalized_state:
          Map.get(worst_event.provenance || %{}, "observed_normalized_state"),
        limit_state_diverged: Map.get(worst_event.provenance || %{}, "limit_state_diverged?"),
        limit_divergence_count: divergence_count(sorted_events)
      }
    end)
    |> Enum.sort_by(&bucket_sort_key/1)
  end

  @spec bucket_width_ms(PlannedSourceRequest.t()) :: pos_integer()
  def bucket_width_ms(%PlannedSourceRequest{} = request) do
    case context_value(request.sampling, :bucket_width_ms) do
      value when is_integer(value) and value > 0 ->
        value

      _other ->
        derived_bucket_width_ms(request) || 60_000
    end
  end

  @spec warnings(
          PlannedSourceRequest.t(),
          binary(),
          [Sample.t()],
          [DefinitionInterval.t()],
          [Event.t()]
        ) :: [ResolveWarning.t()]
  def warnings(request, observable_id, [], _selected_intervals, _events) do
    [
      warning(
        request,
        :missing_telemetry_samples,
        :info,
        "No telemetry samples are available for limit recomputation",
        %{observable_id: observable_id, unresolved_capability: :telemetry_sample_read_path}
      )
    ]
  end

  def warnings(request, observable_id, _samples, [], _events) do
    [
      warning(
        request,
        :unknown_limit_definition,
        :warning,
        "No complete target limit definition is available for recomputation",
        %{
          observable_id: observable_id,
          requested_semantics_mode: semantics_mode(request),
          unresolved_capability: :target_limit_definition_intervals
        }
      )
    ]
  end

  def warnings(request, observable_id, samples, _selected_intervals, events) do
    missing_samples = missing_recomputed_sample_ids(samples, events)

    if missing_samples == [] do
      []
    else
      [
        warning(
          request,
          :incomplete_limit_evaluation,
          :warning,
          "Some telemetry samples have no active complete limit definition for recomputation",
          %{
            observable_id: observable_id,
            requested_semantics_mode: semantics_mode(request),
            selected_limit_clock: limit_clock_policy(request),
            missing_sample_ids: missing_samples,
            unresolved_capability: :target_limit_definition_intervals
          }
        )
      ]
    end
  end

  @spec divergence_count([Event.t()]) :: non_neg_integer()
  def divergence_count(events) do
    Enum.count(events, fn %Event{provenance: provenance} ->
      Map.get(provenance, "limit_state_diverged?") == true
    end)
  end

  defp interval_for_sample(%Sample{} = sample, intervals) do
    Enum.find(intervals, &interval_selected_for_sample(&1, sample))
  end

  defp interval_selected_for_sample(%DefinitionInterval{} = interval, %Sample{
         receipt_time: %DateTime{} = receipt_time
       }) do
    interval_contains_time?(interval, receipt_time)
  end

  defp interval_selected_for_sample(%DefinitionInterval{}, %Sample{}), do: false

  defp recompute_interval_for_sample(:current, intervals, %Sample{}), do: List.first(intervals)

  defp recompute_interval_for_sample(_semantics_mode, intervals, %Sample{} = sample),
    do: interval_for_sample(sample, intervals)

  defp recomputed_limit_event(
         %PlannedSourceRequest{} = request,
         observable_id,
         %Sample{} = sample,
         %DefinitionInterval{} = interval,
         observed_event,
         semantics_mode
       ) do
    limit_state = Evaluator.evaluate(sample.engineering_value, interval.thresholds || %{})
    normalized_state = Evaluator.normalize_state(limit_state)
    observed_normalized_state = observed_event && observed_event.normalized_state

    diverged? =
      not is_nil(observed_normalized_state) and observed_normalized_state != normalized_state

    %Event{
      limit_event_id:
        synthetic_limit_event_id(
          request,
          semantics_mode,
          sample.sample_id,
          interval.definition_activation_key
        ),
      mission_id: sample.mission_id,
      spacecraft_id: sample.spacecraft_id,
      point_id: sample.point_id || observable_id,
      point_name: sample.point_name || observable_id,
      source_sample_type: :telemetry_sample,
      sample_id: sample.sample_id,
      limit_definition_id: interval.limit_definition_id,
      limit_definition_version: interval.limit_definition_version,
      limit_set_name: interval.limit_set_name,
      evaluated_value: sample.engineering_value,
      limit_state: limit_state,
      normalized_state: normalized_state,
      violation: Evaluator.violation?(limit_state),
      generation_time: sample.generation_time,
      receipt_time: sample.receipt_time,
      provenance:
        recomputed_event_provenance(
          semantics_mode,
          interval,
          sample,
          observed_event,
          diverged?
        )
    }
  end

  defp synthetic_limit_event_id(request, semantics_mode, sample_id, activation_key) do
    [
      "synthetic_limit_analysis",
      request.request_id,
      semantics_mode,
      sample_id,
      activation_key
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp recomputed_event_provenance(semantics_mode, interval, sample, observed_event, diverged?) do
    %{
      "synthetic?" => true,
      "semantics_mode" => semantics_mode,
      "analysis_basis" => analysis_basis(semantics_mode),
      "telemetry_sample_id" => sample.sample_id,
      "definition_activation_key" => interval.definition_activation_key,
      "limit_definition_lifecycle_event_id" => interval.limit_definition_lifecycle_event_id,
      "active_from" => interval.active_from,
      "active_to" => interval.active_to,
      "observed_limit_event_id" => observed_event && observed_event.limit_event_id,
      "observed_normalized_state" => observed_event && observed_event.normalized_state,
      "observed_limit_state" => observed_event && observed_event.limit_state,
      "limit_state_diverged?" => diverged?
    }
  end

  defp bucket_sort_key(bucket) do
    {
      DateTime.to_unix(bucket.bucket_start, :millisecond),
      bucket.limit_definition_id || "",
      bucket.limit_definition_version || 0,
      bucket.limit_set_name || ""
    }
  end

  defp bucket_group_key(%Event{} = event, %PlannedSourceRequest{} = request, bucket_width_ms) do
    {
      bucket_start(event.receipt_time, request, bucket_width_ms),
      limit_definition_key(event)
    }
  end

  defp limit_definition_key(%Event{} = event) do
    {
      event.limit_definition_id,
      event.limit_definition_version,
      event.limit_set_name,
      Map.get(event.provenance || %{}, "definition_activation_key")
    }
  end

  defp bucket_start(%DateTime{} = time, %PlannedSourceRequest{} = request, bucket_width_ms) do
    origin_ms =
      case first_context_value(request.time_context, [:from, :start, :start_time]) do
        %DateTime{} = from_time -> DateTime.to_unix(from_time, :millisecond)
        _other -> 0
      end

    time_ms = DateTime.to_unix(time, :millisecond)
    bucket_ms = origin_ms + div(time_ms - origin_ms, bucket_width_ms) * bucket_width_ms
    DateTime.from_unix!(bucket_ms, :millisecond)
  end

  defp derived_bucket_width_ms(%PlannedSourceRequest{} = request) do
    with %DateTime{} = from_time <-
           first_context_value(request.time_context, [:from, :start, :start_time]),
         %DateTime{} = to_time <-
           first_context_value(request.time_context, [:to, :end, :end_time]),
         target_points when is_integer(target_points) and target_points > 0 <-
           context_value(request.sampling, :target_points) do
      diff_ms = max(DateTime.diff(to_time, from_time, :millisecond), 1)
      max(div(diff_ms + target_points - 1, target_points), 1)
    else
      _other -> nil
    end
  end

  defp missing_recomputed_sample_ids(samples, events) do
    event_sample_ids =
      events
      |> Enum.map(& &1.sample_id)
      |> MapSet.new()

    samples
    |> Enum.map(& &1.sample_id)
    |> Enum.reject(&MapSet.member?(event_sample_ids, &1))
  end

  defp divergence_warnings(request, observable_id, events, :compare) do
    divergent_events =
      Enum.filter(events, fn %Event{provenance: provenance} ->
        Map.get(provenance, "limit_state_diverged?") == true
      end)

    if divergent_events == [] do
      []
    else
      [
        warning(
          request,
          :limit_analysis_diverged,
          :warning,
          "Recomputed limit analysis differs from observed limit events",
          %{
            observable_id: observable_id,
            divergent_sample_ids: Enum.map(divergent_events, & &1.sample_id),
            divergent_count: length(divergent_events),
            requested_semantics_mode: :compare
          }
        )
      ]
    end
  end

  defp divergence_warnings(_request, _observable_id, _events, _semantics_mode), do: []

  defp interval_ends_after?(nil, %DateTime{}), do: true

  defp interval_ends_after?(%DateTime{} = active_to, %DateTime{} = time) do
    DateTime.compare(active_to, time) == :gt
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

  defp normalize_semantics_mode(nil), do: :observed
  defp normalize_semantics_mode("observed"), do: :observed
  defp normalize_semantics_mode("current"), do: :current
  defp normalize_semantics_mode("recomputed"), do: :recomputed
  defp normalize_semantics_mode("compare"), do: :compare
  defp normalize_semantics_mode(mode) when is_atom(mode), do: mode
  defp normalize_semantics_mode(mode), do: mode

  defp time_axis(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> context_value(:axis)
    |> normalize_atom()
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
    Enum.find_value(keys, &context_value(context, &1))
  end
end
