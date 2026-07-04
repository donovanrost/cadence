defmodule CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary do
  @moduledoc false

  alias Cadence.Dashboards.{DashboardResolveResult, SourceExecutionSemantics}
  alias CadenceWeb.OpsDashboardShowLive.SourcePresentation

  @spec build(term()) :: map()
  def build(%DashboardResolveResult{} = result) do
    source_summary = SourceExecutionSemantics.summarize(result)
    outcomes = Map.fetch!(source_summary, :outcomes)
    incidents = SourcePresentation.source_incident_summaries(result)
    degraded_incidents = Enum.filter(incidents, & &1.execution_dashboard_degraded?)

    %{
      actionable_count: Map.fetch!(source_summary, :actionable_source_request_count),
      retryable_count: Map.fetch!(source_summary, :retryable_source_request_count),
      degraded_count: length(degraded_incidents),
      source_incidents: incidents,
      degraded_incidents: degraded_source_incidents(degraded_incidents),
      degraded_outcomes: degraded_source_outcomes(outcomes),
      capability_postures: capability_posture_summaries(outcomes),
      source_selections: source_selection_summaries(result),
      source_dependencies: source_dependency_summaries(result, outcomes),
      runtime_actions: runtime_action_counts(outcomes),
      operator_actions: operator_action_counts(outcomes),
      statuses: Map.fetch!(source_summary, :status_counts),
      severities: Map.fetch!(source_summary, :severity_counts)
    }
  end

  def build(_result), do: empty_summary()

  defp empty_summary do
    %{
      actionable_count: 0,
      retryable_count: 0,
      degraded_count: 0,
      source_incidents: [],
      degraded_incidents: [],
      degraded_outcomes: [],
      capability_postures: [],
      source_selections: %{},
      source_dependencies: [],
      runtime_actions: %{},
      operator_actions: %{},
      statuses: %{},
      severities: %{}
    }
  end

  defp source_selection_summaries(%DashboardResolveResult{plan_metadata: plan_metadata})
       when is_map(plan_metadata) do
    plan_metadata
    |> Map.get(:source_selection_by_request_id, %{})
    |> case do
      selections when is_map(selections) -> selections
      _other -> %{}
    end
  end

  defp source_dependency_summaries(%DashboardResolveResult{} = result, outcomes) do
    outcomes_by_logical_source = outcomes_by_logical_source(outcomes)
    watermarks = result.watermarks || []

    outcomes
    |> Enum.flat_map(fn outcome ->
      outcome.metadata
      |> Map.get(:source_dependencies, [])
      |> case do
        dependencies when is_list(dependencies) -> dependencies
        _dependencies -> []
      end
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn dependency ->
        upstream_outcome = dependency_source_outcome(dependency, outcomes_by_logical_source)
        upstream_watermark = dependency_source_watermark(upstream_outcome, dependency, watermarks)

        source_dependency_summary(outcome, dependency, upstream_outcome, upstream_watermark)
      end)
    end)
    |> Enum.sort_by(fn summary ->
      {source_execution_sort_value(summary.request_logical_source), summary.request_id,
       source_execution_sort_value(summary.logical_source), summary.reason}
    end)
  end

  defp source_dependency_summary(outcome, dependency, upstream_outcome, upstream_watermark) do
    %{
      request_id: outcome.request_id,
      request_logical_source: outcome.logical_source,
      logical_source: dependency_value(dependency, :logical_source),
      reason: dependency_value(dependency, :reason),
      products: dependency_products(dependency_value(dependency, :products)),
      sampling: dependency_sampling(dependency_value(dependency, :sampling)),
      upstream_request_id: outcome_value(upstream_outcome, :request_id),
      upstream_status: outcome_value(upstream_outcome, :status),
      upstream_severity: outcome_value(upstream_outcome, :severity),
      upstream_runtime_action: outcome_value(upstream_outcome, :runtime_action),
      upstream_operator_action: outcome_value(upstream_outcome, :operator_action),
      upstream_cache_status: outcome_value(upstream_outcome, :cache_status),
      upstream_cache_reasons: outcome_metadata_value(upstream_outcome, :cache_reasons, []),
      upstream_source_binding_id: outcome_metadata_value(upstream_outcome, :source_binding_id),
      upstream_data_source_id: outcome_metadata_value(upstream_outcome, :data_source_id),
      upstream_realm: outcome_metadata_value(upstream_outcome, :realm),
      upstream_dataset: outcome_metadata_value(upstream_outcome, :dataset),
      upstream_degraded?: outcome_value(upstream_outcome, :dashboard_degraded?) == true,
      upstream_actionable?: outcome_value(upstream_outcome, :actionable?) == true,
      upstream_retryable?: outcome_value(upstream_outcome, :retryable?) == true,
      upstream_watermark_freshness_state: watermark_value(upstream_watermark, :freshness_state),
      upstream_watermark_confidence: watermark_value(upstream_watermark, :confidence),
      upstream_watermark_complete_through: watermark_value(upstream_watermark, :complete_through),
      upstream_watermark_latest_receipt_time:
        watermark_value(upstream_watermark, :latest_receipt_time),
      upstream_watermark_sample_count: watermark_value(upstream_watermark, :sample_count)
    }
  end

  defp outcomes_by_logical_source(outcomes) do
    outcomes
    |> Enum.group_by(& &1.logical_source)
    |> Map.new(fn {logical_source, grouped_outcomes} ->
      {logical_source,
       Enum.sort_by(grouped_outcomes, &source_execution_sort_value(&1.request_id))}
    end)
  end

  defp dependency_source_outcome(dependency, outcomes_by_logical_source) do
    dependency
    |> dependency_value(:logical_source)
    |> then(&Map.get(outcomes_by_logical_source, &1, []))
    |> Enum.find(&(&1.dashboard_degraded? == true))
    |> case do
      nil ->
        dependency
        |> dependency_value(:logical_source)
        |> then(&Map.get(outcomes_by_logical_source, &1, []))
        |> Enum.find(&(&1.status != :skipped))

      outcome ->
        outcome
    end
    |> case do
      nil ->
        dependency
        |> dependency_value(:logical_source)
        |> then(&Map.get(outcomes_by_logical_source, &1, []))
        |> List.first()

      outcome ->
        outcome
    end
  end

  defp dependency_source_watermark(nil, dependency, watermarks),
    do: dependency_source_watermark_by_logical_source(dependency, watermarks)

  defp dependency_source_watermark(upstream_outcome, dependency, watermarks) do
    request_id = outcome_value(upstream_outcome, :request_id)

    Enum.find(watermarks, &(watermark_value(&1, :request_id) == request_id)) ||
      dependency_source_watermark_by_logical_source(dependency, watermarks)
  end

  defp dependency_source_watermark_by_logical_source(dependency, watermarks) do
    logical_source = dependency_value(dependency, :logical_source)

    Enum.find(watermarks, &(watermark_value(&1, :logical_source) == logical_source))
  end

  defp runtime_action_counts(outcomes),
    do: source_execution_action_counts(outcomes, :runtime_action)

  defp operator_action_counts(outcomes),
    do: source_execution_action_counts(outcomes, :operator_action)

  defp degraded_source_outcomes(outcomes) do
    outcomes
    |> Enum.filter(& &1.dashboard_degraded?)
    |> Enum.map(fn outcome ->
      %{
        request_id: outcome.request_id,
        logical_source: outcome.logical_source,
        status: outcome.status,
        severity: outcome.severity,
        realm: Map.get(outcome.metadata, :realm),
        data_source_id: Map.get(outcome.metadata, :data_source_id),
        source_binding_id: Map.get(outcome.metadata, :source_binding_id),
        retryable?: outcome.retryable?,
        actionable?: outcome.actionable?,
        runtime_action: outcome.runtime_action,
        operator_action: outcome.operator_action
      }
    end)
    |> Enum.sort_by(fn outcome ->
      {source_execution_sort_value(outcome.logical_source), outcome.request_id}
    end)
  end

  defp degraded_source_incidents(incidents) do
    incidents
    |> Enum.map(fn incident ->
      %{
        request_id: incident.request_id,
        logical_source: incident.logical_source,
        status: incident.incident_status,
        severity: incident.execution_severity,
        realm: incident.realm,
        data_source_id: incident.data_source_id,
        source_binding_id: incident.source_binding_id,
        retryable?: incident.execution_retryable?,
        actionable?: incident.execution_actionable?,
        runtime_action: incident.execution_runtime_action,
        operator_action: incident.execution_operator_action
      }
    end)
    |> Enum.sort_by(fn incident ->
      {source_execution_sort_value(incident.logical_source), incident.request_id}
    end)
  end

  defp capability_posture_summaries(outcomes) do
    outcomes
    |> Enum.map(&capability_posture_summary/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn posture ->
      {source_execution_sort_value(Map.get(posture, :logical_source)),
       source_execution_sort_value(Map.get(posture, :request_id))}
    end)
  end

  defp capability_posture_summary(outcome) do
    case outcome_metadata_value(outcome, :capability_posture) do
      posture when is_map(posture) ->
        build_capability_posture_summary(outcome, posture)

      _posture ->
        nil
    end
  end

  defp build_capability_posture_summary(outcome, posture) do
    %{
      request_id: outcome.request_id,
      logical_source: outcome.logical_source,
      status: posture_value(posture, :status),
      requested_sampling: posture_value(posture, :requested_sampling),
      supported_sampling: posture_list_value(posture, :supported_sampling),
      requested_products: posture_list_value(posture, :requested_products),
      supported_products: posture_list_value(posture, :supported_products),
      requested_time_axis: posture_value(posture, :requested_time_axis),
      executed_time_axis: posture_value(posture, :executed_time_axis),
      supported_time_axes: posture_list_value(posture, :supported_time_axes),
      fallbacks: posture_list_value(posture, :fallbacks),
      unsupported: posture_list_value(posture, :unsupported),
      source_binding_id: outcome_metadata_value(outcome, :source_binding_id),
      data_source_id: outcome_metadata_value(outcome, :data_source_id),
      realm: outcome_metadata_value(outcome, :realm)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end

  defp source_execution_action_counts(outcomes, key) do
    outcomes
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&(&1 in [nil, :none]))
    |> Enum.frequencies()
  end

  defp source_execution_sort_value(nil), do: ""
  defp source_execution_sort_value(value) when is_atom(value), do: Atom.to_string(value)
  defp source_execution_sort_value(value) when is_binary(value), do: value
  defp source_execution_sort_value(value), do: inspect(value)

  defp dependency_value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key)))

  defp dependency_value(_map, _key), do: nil

  defp dependency_products(products) when is_list(products), do: products
  defp dependency_products(product) when not is_nil(product), do: [product]
  defp dependency_products(_products), do: []

  defp dependency_sampling(sampling) when is_map(sampling), do: sampling
  defp dependency_sampling(_sampling), do: %{}

  defp outcome_value(nil, _key), do: nil
  defp outcome_value(outcome, key) when is_map(outcome), do: Map.get(outcome, key)

  defp outcome_metadata_value(outcome, key, default \\ nil)

  defp outcome_metadata_value(nil, _key, default), do: default

  defp outcome_metadata_value(outcome, key, default) when is_map(outcome) do
    outcome
    |> Map.get(:metadata, %{})
    |> case do
      metadata when is_map(metadata) -> Map.get(metadata, key, default)
      _metadata -> default
    end
  end

  defp posture_value(posture, key) when is_map(posture),
    do: Map.get(posture, key, Map.get(posture, to_string(key)))

  defp posture_value(_posture, _key), do: nil

  defp posture_list_value(posture, key) do
    case posture_value(posture, key) do
      values when is_list(values) -> values
      nil -> []
      value -> [value]
    end
  end

  defp watermark_value(nil, _key), do: nil
  defp watermark_value(watermark, key) when is_map(watermark), do: Map.get(watermark, key)
end
