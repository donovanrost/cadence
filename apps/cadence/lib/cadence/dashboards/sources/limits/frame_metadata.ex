defmodule Cadence.Dashboards.Sources.Limits.FrameMetadata do
  @moduledoc """
  Builds evidence and provenance metadata for resolved limit frames.

  Source identity is supplied by the adapter so provider selection remains
  centralized. This module owns only consumer-facing evidence, links, counts,
  selected-definition details, and limit-analysis annotations.
  """

  alias Cadence.Dashboards.{DataLinks, PlannedSourceRequest}
  alias Cadence.Dashboards.Sources.Limits.RecomputedAnalysis
  alias Cadence.Limits.{DefinitionInterval, Event}

  @spec latest(
          PlannedSourceRequest.t(),
          term(),
          binary(),
          Event.t() | nil,
          [DefinitionInterval.t()],
          [struct()],
          map()
        ) :: map()
  def latest(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        event,
        selected_intervals,
        warnings,
        source_context
      ) do
    %{
      source_request_id: request.request_id,
      observable_id: observable_id,
      point_id: observable_id,
      logical_source: :limits,
      source_binding_id: source_context.source_binding_id,
      dataset: source_context.dataset,
      sampling: :latest_state,
      semantics_mode: :observed,
      analysis_basis: :observed_fact,
      realm: source_context.realm,
      data_source_id: source_context.data_source_id,
      replay_run_id: source_context.replay_run_id,
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

  @spec recomputed_latest(
          PlannedSourceRequest.t(),
          term(),
          binary(),
          map(),
          map()
        ) :: map()
  def recomputed_latest(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        analysis,
        source_context
      ) do
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
      source_binding_id: source_context.source_binding_id,
      dataset: source_context.dataset,
      sampling: :latest_state,
      semantics_mode: semantics_mode,
      analysis_basis: RecomputedAnalysis.analysis_basis(semantics_mode),
      synthetic_limit_analysis?: true,
      selected_limit_clock: RecomputedAnalysis.limit_clock_policy(request),
      realm: source_context.realm,
      data_source_id: source_context.data_source_id,
      replay_run_id: source_context.replay_run_id,
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

  @spec event_history(
          PlannedSourceRequest.t(),
          term(),
          binary(),
          [Event.t()],
          [DefinitionInterval.t()],
          [struct()],
          map()
        ) :: map()
  def event_history(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        events,
        selected_intervals,
        warnings,
        source_context
      ) do
    %{
      source_request_id: request.request_id,
      observable_id: observable_id,
      point_id: observable_id,
      logical_source: :limits,
      source_binding_id: source_context.source_binding_id,
      dataset: source_context.dataset,
      sampling: :event_history,
      semantics_mode: :observed,
      analysis_basis: :observed_fact,
      realm: source_context.realm,
      data_source_id: source_context.data_source_id,
      replay_run_id: source_context.replay_run_id,
      returned_events: length(events),
      truncated?: length(events) >= source_context.event_limit,
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

  @spec recomputed_event_history(
          PlannedSourceRequest.t(),
          term(),
          binary(),
          map(),
          map()
        ) :: map()
  def recomputed_event_history(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        analysis,
        source_context
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
      source_binding_id: source_context.source_binding_id,
      dataset: source_context.dataset,
      sampling: :event_history,
      semantics_mode: semantics_mode,
      analysis_basis: RecomputedAnalysis.analysis_basis(semantics_mode),
      synthetic_limit_analysis?: true,
      selected_limit_clock: RecomputedAnalysis.limit_clock_policy(request),
      realm: source_context.realm,
      data_source_id: source_context.data_source_id,
      replay_run_id: source_context.replay_run_id,
      returned_events: length(events),
      source_sample_count: length(samples),
      observed_event_count: length(observed_events),
      divergence_count: RecomputedAnalysis.divergence_count(events),
      truncated?: length(events) >= source_context.event_limit,
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

  @spec analysis_buckets(
          PlannedSourceRequest.t(),
          term(),
          binary(),
          map(),
          [map()],
          map()
        ) :: map()
  def analysis_buckets(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        analysis,
        buckets,
        source_context
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
      source_binding_id: source_context.source_binding_id,
      dataset: source_context.dataset,
      sampling: :analysis_buckets,
      semantics_mode: semantics_mode,
      analysis_basis: RecomputedAnalysis.analysis_basis(semantics_mode),
      selected_limit_clock: RecomputedAnalysis.limit_clock_policy(request),
      realm: source_context.realm,
      data_source_id: source_context.data_source_id,
      replay_run_id: source_context.replay_run_id,
      bucket_width_ms: RecomputedAnalysis.bucket_width_ms(request),
      returned_buckets: length(buckets),
      returned_events: length(events),
      source_sample_count: length(samples),
      observed_event_count: length(observed_events),
      divergence_count: RecomputedAnalysis.divergence_count(events),
      truncated?: length(events) >= source_context.event_limit,
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

  @spec definition_intervals(
          PlannedSourceRequest.t(),
          term(),
          binary(),
          [DefinitionInterval.t()],
          [struct()],
          map()
        ) :: map()
  def definition_intervals(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        intervals,
        warnings,
        source_context
      ) do
    %{
      source_request_id: request.request_id,
      observable_id: observable_id,
      point_id: observable_id,
      logical_source: :limits,
      source_binding_id: source_context.source_binding_id,
      dataset: source_context.dataset,
      sampling: :definition_intervals,
      semantics_mode: :observed,
      analysis_basis: :observed_fact,
      realm: source_context.realm,
      data_source_id: source_context.data_source_id,
      replay_run_id: source_context.replay_run_id,
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

  defp maybe_put_synthetic_limit_analysis(meta, :observed), do: meta

  defp maybe_put_synthetic_limit_analysis(meta, _semantics_mode) do
    Map.put(meta, :synthetic_limit_analysis?, true)
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

  defp event_count(%Event{}), do: 1
  defp event_count(nil), do: 0
end
