defmodule Cadence.Dashboards.SourceIncident do
  @moduledoc """
  Core source-incident semantics for dashboard runtime evidence.

  The web layer formats incidents into rows and labels, but the dashboard core
  owns the diagnostic details and route-free actions operators can take from a
  source incident.
  """

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    DataContext,
    EvidenceRef,
    PlannedSourceRequest,
    ResolveWarning,
    SourceActions,
    SourceExecutionSemantics
  }

  @source_warning_codes [:source_degraded, :source_unavailable]

  @spec summaries(term()) :: [map()]
  def summaries(nil), do: []

  def summaries(%{watermarks: watermarks, planned_source_requests: requests} = result)
      when is_list(watermarks) and is_list(requests) do
    source_cache_by_request_id = source_cache_by_request_id(result)
    frame_cache_by_request_id = frame_cache_by_request_id(result)
    source_warnings_by_request_id = source_warnings_by_request_id(result)
    source_execution_outcomes_by_request_id = source_execution_outcomes_by_request_id(result)

    watermarked_request_ids = MapSet.new(Enum.map(watermarks, &Map.get(&1, :request_id)))

    synthesized =
      requests
      |> Enum.reject(&MapSet.member?(watermarked_request_ids, &1.request_id))
      |> Enum.map(&unknown_request_watermark/1)

    health_incidents =
      (watermarks ++ synthesized)
      |> Enum.map(
        &summary(
          &1,
          source_cache_by_request_id,
          frame_cache_by_request_id,
          source_warnings_by_request_id,
          source_execution_outcomes_by_request_id
        )
      )

    incident_request_ids = MapSet.new(Enum.map(health_incidents, & &1.request_id))

    execution_incidents =
      source_execution_outcomes_by_request_id
      |> Map.values()
      |> Enum.reject(&MapSet.member?(incident_request_ids, &1.request_id))
      |> Enum.map(
        &execution_summary(
          &1,
          source_cache_by_request_id,
          frame_cache_by_request_id,
          source_warnings_by_request_id
        )
      )

    dedupe_and_sort(health_incidents ++ execution_incidents)
  end

  def summaries(%DashboardResolveResult{} = result) do
    source_cache_by_request_id = source_cache_by_request_id(result)
    frame_cache_by_request_id = frame_cache_by_request_id(result)
    source_warnings_by_request_id = source_warnings_by_request_id(result)

    result
    |> source_execution_outcomes_by_request_id()
    |> Map.values()
    |> Enum.map(
      &execution_summary(
        &1,
        source_cache_by_request_id,
        frame_cache_by_request_id,
        source_warnings_by_request_id
      )
    )
    |> dedupe_and_sort()
  end

  def summaries(_result), do: []

  @spec source_execution_warnings(term()) :: [ResolveWarning.t() | map()]
  def source_execution_warnings(%{dashboard_warnings: warnings} = result)
      when is_list(warnings) do
    outcomes_by_request_id = source_execution_outcomes_by_request_id(result)

    enriched_warnings =
      Enum.map(warnings, &enrich_source_execution_warning(&1, outcomes_by_request_id))

    enriched_warnings ++ synthetic_source_execution_warnings(result, enriched_warnings)
  end

  def source_execution_warnings(%DashboardResolveResult{} = result),
    do: synthetic_source_execution_warnings(result, [])

  def source_execution_warnings(_result), do: []

  @spec execution_details(map()) :: map()
  def execution_details(outcome) when is_map(outcome) do
    outcome
    |> metadata()
    |> Map.take([:source_binding_id, :data_source_id, :realm, :dataset])
    |> Map.merge(%{
      source_request_id: Map.get(outcome, :request_id),
      logical_source: Map.get(outcome, :logical_source),
      source_execution_status: Map.get(outcome, :status),
      source_execution_severity: Map.get(outcome, :severity),
      source_execution_action: Map.get(outcome, :operator_action),
      source_execution_runtime_action: Map.get(outcome, :runtime_action),
      source_execution_actionable?: Map.get(outcome, :actionable?),
      source_execution_retryable?: Map.get(outcome, :retryable?),
      source_execution_dashboard_degraded?: Map.get(outcome, :dashboard_degraded?)
    })
    |> maybe_put(:source_execution_cache_status, Map.get(outcome, :cache_status))
    |> maybe_put(:source_execution_warning_codes, Map.get(outcome, :warning_codes, []))
  end

  def execution_details(_outcome), do: %{}

  @spec put_execution_source_actions(map(), map()) :: map()
  def put_execution_source_actions(details, outcome) when is_map(details) and is_map(outcome) do
    details
    |> Map.merge(execution_details(outcome))
    |> SourceActions.put_source_warning_actions()
  end

  def put_execution_source_actions(details, _outcome) when is_map(details), do: details

  @spec actions(map(), map(), map(), keyword()) :: [Cadence.Dashboards.DashboardAction.t()]
  def actions(watermark, source_warning, execution_outcome, opts \\ []) do
    source_warning_details = source_warning |> Map.get(:details, %{}) |> ensure_map()
    execution_metadata = execution_outcome |> metadata()

    watermark
    |> action_context()
    |> Map.merge(
      Map.take(execution_metadata, [:source_binding_id, :data_source_id, :realm, :dataset])
    )
    |> Map.merge(source_warning_details)
    |> SourceActions.source_warning_actions(
      source: Keyword.get(opts, :source, :source_health),
      health_action_id: Keyword.get(opts, :health_action_id, "dashboard-evidence-source-health"),
      inventory_action_id:
        Keyword.get(opts, :inventory_action_id, "dashboard-evidence-source-inventory")
    )
  end

  defp enrich_source_execution_warning(warning, outcomes_by_request_id) do
    request_id = warning |> Map.get(:details, %{}) |> detail_value(:source_request_id)

    case Map.get(outcomes_by_request_id, request_id) do
      nil ->
        warning

      outcome ->
        Map.update(
          warning,
          :details,
          outcome |> execution_details() |> SourceActions.put_source_warning_actions(),
          fn details ->
            put_execution_source_actions(details || %{}, outcome)
          end
        )
    end
  end

  defp synthetic_source_execution_warnings(result, warnings) do
    warned_request_ids =
      warnings
      |> Enum.map(&(Map.get(&1, :details, %{}) |> detail_value(:source_request_id)))
      |> MapSet.new()

    result
    |> source_execution_outcomes_by_request_id()
    |> Map.values()
    |> Enum.reject(&MapSet.member?(warned_request_ids, &1.request_id))
    |> Enum.filter(&(&1.actionable? or &1.dashboard_degraded?))
    |> Enum.map(&source_execution_warning/1)
  end

  defp source_execution_warning(outcome) do
    details =
      outcome
      |> execution_details()
      |> SourceActions.put_source_warning_actions()

    %ResolveWarning{
      code: source_execution_warning_code(outcome.status),
      severity: outcome.severity,
      message: source_execution_warning_message(outcome),
      details: details,
      evidence: [
        %EvidenceRef{
          kind: :source_request,
          id: outcome.request_id,
          source: outcome.logical_source,
          confidence: :direct
        }
      ]
    }
  end

  defp source_execution_warning_code(:facts_error), do: :source_execution_facts_error
  defp source_execution_warning_code(:source_execution_failed), do: :source_execution_failed
  defp source_execution_warning_code(:source_unavailable), do: :source_unavailable
  defp source_execution_warning_code(:source_degraded), do: :source_degraded
  defp source_execution_warning_code(:unsupported_capability), do: :unsupported_source_capability
  defp source_execution_warning_code(status), do: status

  defp source_execution_warning_message(outcome) do
    "#{source_text(outcome.logical_source)} source execution #{status_text(outcome.status)}; action #{status_text(outcome.operator_action)}."
  end

  defp execution_summary(
         outcome,
         source_cache_by_request_id,
         frame_cache_by_request_id,
         source_warnings_by_request_id
       ) do
    metadata = Map.get(outcome, :metadata, %{})

    watermark = %{
      logical_source: Map.get(outcome, :logical_source),
      request_id: Map.get(outcome, :request_id),
      realm: Map.get(metadata, :realm),
      data_source_id: Map.get(metadata, :data_source_id),
      source_binding_id: Map.get(metadata, :source_binding_id),
      dataset: Map.get(metadata, :dataset),
      confidence: :derived
    }

    summary(
      watermark,
      source_cache_by_request_id,
      frame_cache_by_request_id,
      source_warnings_by_request_id,
      %{Map.get(outcome, :request_id) => outcome}
    )
  end

  defp summary(
         watermark,
         source_cache_by_request_id,
         frame_cache_by_request_id,
         source_warnings_by_request_id,
         source_execution_outcomes_by_request_id
       ) do
    state = source_health_state(watermark)
    request_id = Map.get(watermark, :request_id)
    source_cache = Map.get(source_cache_by_request_id, request_id, %{})
    frame_cache = Map.get(frame_cache_by_request_id, request_id, %{})
    source_warning = Map.get(source_warnings_by_request_id, request_id, %{})
    execution_outcome = Map.get(source_execution_outcomes_by_request_id, request_id, %{})
    circuit_state = source_warning |> Map.get(:details, %{}) |> detail_value(:circuit_state)
    incident_status = incident_status(state, execution_outcome)

    %{
      incident_kind: incident_kind(execution_outcome),
      incident_status: incident_status,
      logical_source: Map.get(watermark, :logical_source),
      realm: Map.get(watermark, :realm),
      state: state,
      request_id: request_id,
      source_binding_id: Map.get(watermark, :source_binding_id),
      data_source_id: Map.get(watermark, :data_source_id),
      dataset: Map.get(watermark, :dataset),
      source_health_event_id: watermark_meta_value(watermark, :source_health_event_id),
      source_health_reason: watermark_meta_value(watermark, :source_health_reason),
      source_health_probe_kind: watermark_meta_value(watermark, :source_health_probe_kind),
      source_health_probe_message: watermark_meta_value(watermark, :source_health_probe_message),
      source_health_probe_metadata:
        watermark_meta_value(watermark, :source_health_probe_metadata),
      confidence: Map.get(watermark, :confidence, :unknown),
      source_cache_status: Map.get(source_cache, :status),
      source_cache: source_cache,
      frame_cache_status: Map.get(frame_cache, :status),
      frame_cache: frame_cache,
      circuit_state: circuit_state,
      execution_status: Map.get(execution_outcome, :status),
      execution_severity: Map.get(execution_outcome, :severity),
      execution_operator_action: Map.get(execution_outcome, :operator_action),
      execution_runtime_action: Map.get(execution_outcome, :runtime_action),
      execution_degraded?: Map.get(execution_outcome, :degraded?, false),
      execution_actionable?: Map.get(execution_outcome, :actionable?, false),
      execution_retryable?: Map.get(execution_outcome, :retryable?, false),
      execution_dashboard_degraded?: Map.get(execution_outcome, :dashboard_degraded?, false),
      execution_warning_codes: Map.get(execution_outcome, :warning_codes, []),
      source_warning_code: Map.get(source_warning, :code),
      source_warning: source_warning,
      evidence_refs: evidence_refs(watermark),
      actions: actions(watermark, source_warning, execution_outcome)
    }
  end

  defp dedupe_and_sort(incidents) do
    incidents
    |> Enum.uniq_by(
      &{&1.logical_source, &1.realm, &1.source_binding_id, &1.data_source_id, &1.state,
       &1.source_cache_status, &1.frame_cache_status, &1.circuit_state, &1.execution_status}
    )
    |> Enum.sort_by(
      &{text_key(&1.logical_source), text_key(&1.realm), text_key(&1.state),
       text_key(&1.source_cache_status)}
    )
  end

  defp incident_kind(%{status: status}) when not is_nil(status), do: :source_execution
  defp incident_kind(_execution_outcome), do: :source_health

  defp incident_status(_state, %{status: status}) when not is_nil(status), do: status
  defp incident_status(state, _execution_outcome), do: state

  defp watermark_meta_value(%{meta: meta}, key) when is_map(meta) and is_atom(key) do
    Map.get(meta, key, Map.get(meta, Atom.to_string(key)))
  end

  defp watermark_meta_value(_watermark, _key), do: nil

  defp source_health_state(%{freshness_state: state}) when state in [:fresh, :stale, :unknown],
    do: state

  defp source_health_state(%{freshness_state: :retention_gap}), do: :retention_gap
  defp source_health_state(%{confidence: :unknown}), do: :unknown
  defp source_health_state(%{complete_through: %DateTime{}}), do: :fresh
  defp source_health_state(%{latest_receipt_time: %DateTime{}}), do: :fresh
  defp source_health_state(_watermark), do: :unknown

  defp evidence_refs(watermark) do
    [
      evidence_ref(:source_request, Map.get(watermark, :request_id), watermark),
      evidence_ref(:data_source, Map.get(watermark, :data_source_id), watermark),
      evidence_ref(:source_binding, Map.get(watermark, :source_binding_id), watermark)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp evidence_ref(_kind, nil, _watermark), do: nil

  defp evidence_ref(kind, id, watermark) do
    %EvidenceRef{
      kind: kind,
      id: id,
      source: Map.get(watermark, :logical_source),
      confidence: evidence_confidence(Map.get(watermark, :confidence, :unknown)),
      observed_at:
        Map.get(watermark, :complete_through) || Map.get(watermark, :latest_receipt_time)
    }
  end

  defp evidence_confidence(:authoritative), do: :direct
  defp evidence_confidence(:derived), do: :derived
  defp evidence_confidence(:best_effort), do: :best_effort
  defp evidence_confidence(_confidence), do: :best_effort

  defp unknown_request_watermark(%PlannedSourceRequest{} = request) do
    %{
      logical_source: request.logical_source,
      request_id: request.request_id,
      realm: context_value(request.data_context, :realm),
      data_source_id:
        DataContext.source_value(request.data_context, request.logical_source, :data_source_id),
      source_binding_id:
        DataContext.source_value(request.data_context, request.logical_source, :source_binding_id),
      dataset: DataContext.source_value(request.data_context, request.logical_source, :dataset),
      confidence: :unknown
    }
  end

  defp source_cache_by_request_id(%{plan_metadata: %{cache: cache}}) when is_map(cache) do
    cache
    |> Map.get(:source_result_cache_by_request_id, %{})
    |> ensure_map()
  end

  defp source_cache_by_request_id(_result), do: %{}

  defp frame_cache_by_request_id(%{plan_metadata: %{cache: cache}}) when is_map(cache) do
    cache
    |> Map.get(:frame_cache_by_placement, %{})
    |> ensure_map()
    |> Enum.reduce(%{}, fn {_placement_id, entries_by_request_id}, acc ->
      entries_by_request_id
      |> ensure_map()
      |> Enum.reduce(acc, fn {request_id, entry}, acc ->
        Map.update(acc, request_id, cache_summary(entry), &merge_cache_summaries(&1, entry))
      end)
    end)
  end

  defp frame_cache_by_request_id(_result), do: %{}

  defp source_warnings_by_request_id(%{dashboard_warnings: warnings}) when is_list(warnings) do
    warnings
    |> Enum.filter(&(Map.get(&1, :code) in @source_warning_codes))
    |> Map.new(fn warning ->
      details = Map.get(warning, :details, %{})
      {detail_value(details, :source_request_id), warning}
    end)
    |> Map.delete(nil)
  end

  defp source_warnings_by_request_id(_result), do: %{}

  defp source_execution_outcomes_by_request_id(%DashboardResolveResult{} = result) do
    result
    |> SourceExecutionSemantics.summarize()
    |> Map.fetch!(:outcomes)
    |> Map.new(&{&1.request_id, &1})
  end

  defp source_execution_outcomes_by_request_id(_result), do: %{}

  defp merge_cache_summaries(summary, entry) do
    entry_summary = cache_summary(entry)

    %{
      status: merge_cache_statuses(Map.get(summary, :status), Map.get(entry_summary, :status)),
      statuses:
        (List.wrap(Map.get(summary, :statuses)) ++ List.wrap(Map.get(entry_summary, :statuses)))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      reasons:
        (List.wrap(Map.get(summary, :reasons)) ++ List.wrap(Map.get(entry_summary, :reasons)))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  defp cache_summary(entry) when is_map(entry) do
    status = Map.get(entry, :status)

    %{
      status: status,
      statuses: List.wrap(status) |> Enum.reject(&is_nil/1),
      reasons: entry |> Map.get(:reasons, []) |> List.wrap() |> Enum.reject(&is_nil/1)
    }
  end

  defp cache_summary(_entry), do: %{}

  defp merge_cache_statuses(nil, status), do: status
  defp merge_cache_statuses(status, nil), do: status
  defp merge_cache_statuses(status, status), do: status
  defp merge_cache_statuses(:stale, _status), do: :stale
  defp merge_cache_statuses(_status, :stale), do: :stale
  defp merge_cache_statuses(:refresh, _status), do: :refresh
  defp merge_cache_statuses(_status, :refresh), do: :refresh
  defp merge_cache_statuses(:miss, _status), do: :miss
  defp merge_cache_statuses(_status, :miss), do: :miss
  defp merge_cache_statuses(status, _other), do: status

  defp action_context(watermark) when is_map(watermark) do
    watermark
    |> Map.take([
      :logical_source,
      :request_id,
      :source_binding_id,
      :data_source_id,
      :realm,
      :dataset
    ])
    |> Enum.map(fn
      {:request_id, value} -> {:source_request_id, value}
      entry -> entry
    end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp action_context(_watermark), do: %{}

  defp metadata(%{metadata: metadata}) when is_map(metadata), do: metadata
  defp metadata(_outcome), do: %{}

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp detail_value(details, key) when is_map(details) and is_atom(key) do
    Map.get(details, key, Map.get(details, Atom.to_string(key)))
  end

  defp text_key(nil), do: ""
  defp text_key(value) when is_atom(value), do: Atom.to_string(value)
  defp text_key(value) when is_binary(value), do: value
  defp text_key(value), do: inspect(value)

  defp source_text(nil), do: "Source"

  defp source_text(logical_source) when is_atom(logical_source) do
    logical_source
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp source_text(logical_source) when is_binary(logical_source) do
    logical_source
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp source_text(_logical_source), do: "Source"

  defp status_text(nil), do: "unknown"
  defp status_text(status) when is_atom(status), do: Atom.to_string(status)
  defp status_text(status) when is_binary(status), do: status
  defp status_text(status), do: inspect(status)
end
