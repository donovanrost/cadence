defmodule CadenceWeb.OpsDashboardShowLive.RuntimeSourceExecutionDiagnostics do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticFormatter

  @spec build(map()) :: map()
  def build(source_summary) when is_map(source_summary) do
    degraded_incidents = Map.get(source_summary, :degraded_incidents, [])
    dependency_evidence = Map.get(source_summary, :source_dependencies, [])
    capability_postures = Map.get(source_summary, :capability_postures, [])
    capability_statuses = capability_status_counts(capability_postures)

    %{
      runtime_actions: Map.get(source_summary, :runtime_actions, %{}),
      runtime_actions_text:
        RuntimeDiagnosticFormatter.value(
          RuntimeDiagnosticFormatter.count_summary(Map.get(source_summary, :runtime_actions, %{}))
        ),
      retryable_count: Map.get(source_summary, :retryable_count, 0),
      actionable_count: Map.get(source_summary, :actionable_count, 0),
      degraded_count: Map.get(source_summary, :degraded_count, 0),
      degraded_incidents: degraded_incidents,
      degraded_identities_text:
        RuntimeDiagnosticFormatter.value(degraded_identity_summary(degraded_incidents)),
      degraded_actions_text:
        RuntimeDiagnosticFormatter.value(degraded_action_summary(degraded_incidents)),
      degraded_summary: degraded_summary(degraded_incidents),
      degraded_drilldowns: degraded_drilldowns(degraded_incidents),
      capability_statuses: capability_statuses,
      capability_statuses_text:
        RuntimeDiagnosticFormatter.value(
          RuntimeDiagnosticFormatter.count_summary(capability_statuses)
        ),
      capability_postures: capability_postures(capability_postures),
      capability_posture_text:
        RuntimeDiagnosticFormatter.value(capability_posture_summary(capability_postures)),
      dependency_evidence: dependency_evidence(dependency_evidence),
      dependency_evidence_text:
        RuntimeDiagnosticFormatter.value(dependency_evidence_summary(dependency_evidence)),
      dependency_degraded_count: dependency_degraded_count(dependency_evidence),
      empty?: empty?(source_summary)
    }
  end

  def build(_source_summary), do: build(%{})

  @spec normalize(map()) :: map()
  def normalize(%{runtime_actions_text: _runtime_actions_text} = source_execution),
    do: source_execution

  def normalize(source_summary), do: build(source_summary)

  @spec maybe_degrade_refresh_status(map(), map()) :: map()
  def maybe_degrade_refresh_status(refresh_status, %{degraded_incidents: [_first | _rest]})
      when is_map(refresh_status) do
    %{refresh_status | status: "degraded", reason: "source_execution_degraded"}
  end

  def maybe_degrade_refresh_status(refresh_status, _source_execution), do: refresh_status

  @spec decision_audit(map()) :: map()
  def decision_audit(%{empty?: true}), do: %{}

  def decision_audit(%{} = source_execution) do
    %{
      source_execution_retryable_count: source_execution.retryable_count,
      source_execution_actionable_count: source_execution.actionable_count,
      source_execution_degraded_count: source_execution.degraded_count,
      source_execution_status_summary: Map.get(source_execution, :statuses, %{}),
      source_execution_severity_summary: Map.get(source_execution, :severities, %{}),
      source_execution_runtime_action_summary: source_execution.runtime_actions,
      source_execution_operator_action_summary: Map.get(source_execution, :operator_actions, %{}),
      source_execution_degraded_identities:
        degraded_identity_values(source_execution.degraded_incidents),
      source_execution_degraded_actions:
        degraded_action_values(source_execution.degraded_incidents),
      source_capability_posture_summary: source_execution.capability_statuses,
      source_capability_posture_evidence:
        capability_posture_values(source_execution.capability_postures),
      source_dependency_degraded_count: source_execution.dependency_degraded_count,
      source_dependency_evidence: dependency_evidence_values(source_execution.dependency_evidence)
    }
  end

  def decision_audit(_source_execution), do: %{}

  @spec decision_audit_from_summary(map()) :: map()
  def decision_audit_from_summary(source_summary) when is_map(source_summary) do
    source_summary
    |> build()
    |> Map.merge(%{
      statuses: Map.get(source_summary, :statuses, %{}),
      severities: Map.get(source_summary, :severities, %{}),
      operator_actions: Map.get(source_summary, :operator_actions, %{})
    })
    |> decision_audit()
  end

  def decision_audit_from_summary(_source_summary), do: %{}

  @spec dependency_evidence_summary([map()]) :: binary() | nil
  def dependency_evidence_summary(dependencies) when is_list(dependencies) do
    dependencies
    |> dependency_evidence_values()
    |> case do
      [] -> nil
      values -> Enum.join(values, " ")
    end
  end

  def dependency_evidence_summary(_dependencies), do: nil

  @spec degraded_identity_summary([map()]) :: binary() | nil
  def degraded_identity_summary([]), do: nil

  def degraded_identity_summary(outcomes) when is_list(outcomes) do
    outcomes
    |> Enum.map_join(" ", fn outcome ->
      [
        Map.get(outcome, :logical_source),
        Map.get(outcome, :request_id),
        Map.get(outcome, :status)
      ]
      |> Enum.map_join(":", &RuntimeDiagnosticFormatter.value/1)
    end)
  end

  def degraded_identity_summary(_outcomes), do: nil

  @spec degraded_action_summary([map()]) :: binary() | nil
  def degraded_action_summary([]), do: nil

  def degraded_action_summary(outcomes) when is_list(outcomes) do
    outcomes
    |> Enum.map_join(" ", fn outcome ->
      [
        Map.get(outcome, :logical_source),
        Map.get(outcome, :request_id),
        Map.get(outcome, :runtime_action),
        Map.get(outcome, :operator_action)
      ]
      |> Enum.map_join(":", &RuntimeDiagnosticFormatter.value/1)
    end)
  end

  def degraded_action_summary(_outcomes), do: nil

  @spec degraded_summary([map()]) :: map()
  def degraded_summary([first | _rest] = outcomes) do
    %{
      visible?: true,
      count: length(outcomes),
      headline: "Source execution degraded.",
      identity: source_execution_identity(first),
      status: drilldown_value(Map.get(first, :status)),
      runtime_action: drilldown_value(Map.get(first, :runtime_action)),
      operator_action: drilldown_value(Map.get(first, :operator_action)),
      realm: drilldown_value(Map.get(first, :realm)),
      data_source_id: drilldown_value(Map.get(first, :data_source_id)),
      source_binding_id: drilldown_value(Map.get(first, :source_binding_id)),
      request_id: drilldown_value(Map.get(first, :request_id))
    }
  end

  def degraded_summary(_outcomes), do: %{visible?: false}

  @spec degraded_drilldowns([map()]) :: [map()]
  def degraded_drilldowns(outcomes) when is_list(outcomes) do
    Enum.map(outcomes, fn outcome ->
      %{
        request_id: drilldown_value(Map.get(outcome, :request_id)),
        logical_source: drilldown_value(Map.get(outcome, :logical_source)),
        status: drilldown_value(Map.get(outcome, :status)),
        runtime_action: drilldown_value(Map.get(outcome, :runtime_action)),
        operator_action: drilldown_value(Map.get(outcome, :operator_action)),
        realm: drilldown_value(Map.get(outcome, :realm)),
        data_source_id: drilldown_value(Map.get(outcome, :data_source_id)),
        source_binding_id: drilldown_value(Map.get(outcome, :source_binding_id))
      }
    end)
  end

  def degraded_drilldowns(_outcomes), do: []

  @spec dependency_evidence([map()]) :: [map()]
  def dependency_evidence(dependencies) when is_list(dependencies) do
    dependencies
    |> Enum.map(fn dependency ->
      %{
        request_id: drilldown_value(Map.get(dependency, :request_id)),
        request_logical_source: drilldown_value(Map.get(dependency, :request_logical_source)),
        logical_source: drilldown_value(Map.get(dependency, :logical_source)),
        products: list_value(Map.get(dependency, :products, [])),
        reason: drilldown_value(Map.get(dependency, :reason)),
        upstream_request_id: drilldown_value(Map.get(dependency, :upstream_request_id)),
        upstream_status: drilldown_value(Map.get(dependency, :upstream_status)),
        upstream_runtime_action: drilldown_value(Map.get(dependency, :upstream_runtime_action)),
        upstream_operator_action: drilldown_value(Map.get(dependency, :upstream_operator_action)),
        upstream_cache_status: drilldown_value(Map.get(dependency, :upstream_cache_status)),
        upstream_cache_reasons: list_value(Map.get(dependency, :upstream_cache_reasons, [])),
        upstream_source_binding_id:
          drilldown_value(Map.get(dependency, :upstream_source_binding_id)),
        upstream_data_source_id: drilldown_value(Map.get(dependency, :upstream_data_source_id)),
        upstream_realm: drilldown_value(Map.get(dependency, :upstream_realm)),
        upstream_watermark_freshness_state:
          drilldown_value(Map.get(dependency, :upstream_watermark_freshness_state)),
        upstream_watermark_confidence:
          drilldown_value(Map.get(dependency, :upstream_watermark_confidence)),
        upstream_watermark_complete_through:
          drilldown_value(Map.get(dependency, :upstream_watermark_complete_through))
      }
    end)
  end

  def dependency_evidence(_dependencies), do: []

  @spec dependency_degraded_count([map()]) :: non_neg_integer()
  def dependency_degraded_count(dependencies) when is_list(dependencies) do
    Enum.count(dependencies, &(Map.get(&1, :upstream_degraded?) == true))
  end

  def dependency_degraded_count(_dependencies), do: 0

  defp empty?(source_summary) when is_map(source_summary) do
    Map.get(source_summary, :retryable_count, 0) == 0 and
      Map.get(source_summary, :actionable_count, 0) == 0 and
      Map.get(source_summary, :degraded_count, 0) == 0 and
      map_empty?(Map.get(source_summary, :statuses, %{})) and
      map_empty?(Map.get(source_summary, :severities, %{})) and
      map_empty?(Map.get(source_summary, :runtime_actions, %{})) and
      map_empty?(Map.get(source_summary, :operator_actions, %{})) and
      Map.get(source_summary, :capability_postures, []) == []
  end

  defp degraded_identity_values(outcomes) when is_list(outcomes) do
    outcomes
    |> Enum.map(fn outcome ->
      [
        Map.get(outcome, :logical_source),
        Map.get(outcome, :request_id),
        Map.get(outcome, :status)
      ]
      |> Enum.map_join(":", &RuntimeDiagnosticFormatter.value/1)
    end)
    |> Enum.reject(&(&1 in [nil, "", "-"]))
  end

  defp degraded_identity_values(_outcomes), do: []

  defp degraded_action_values(outcomes) when is_list(outcomes) do
    outcomes
    |> Enum.map(fn outcome ->
      [
        Map.get(outcome, :logical_source),
        Map.get(outcome, :request_id),
        Map.get(outcome, :runtime_action),
        Map.get(outcome, :operator_action)
      ]
      |> Enum.map_join(":", &RuntimeDiagnosticFormatter.value/1)
    end)
    |> Enum.reject(&(&1 in [nil, "", "-"]))
  end

  defp degraded_action_values(_outcomes), do: []

  defp capability_status_counts(postures) when is_list(postures) do
    postures
    |> Enum.map(&Map.get(&1, :status))
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp capability_status_counts(_postures), do: %{}

  defp capability_postures(postures) when is_list(postures) do
    Enum.map(postures, fn posture ->
      %{
        request_id: drilldown_value(Map.get(posture, :request_id)),
        logical_source: drilldown_value(Map.get(posture, :logical_source)),
        status: drilldown_value(Map.get(posture, :status)),
        requested_sampling: drilldown_value(Map.get(posture, :requested_sampling)),
        supported_sampling: list_value(Map.get(posture, :supported_sampling, [])),
        requested_products: list_value(Map.get(posture, :requested_products, [])),
        supported_products: list_value(Map.get(posture, :supported_products, [])),
        requested_time_axis: drilldown_value(Map.get(posture, :requested_time_axis)),
        executed_time_axis: drilldown_value(Map.get(posture, :executed_time_axis)),
        supported_time_axes: list_value(Map.get(posture, :supported_time_axes, [])),
        fallbacks: capability_details_value(Map.get(posture, :fallbacks, [])),
        unsupported: capability_details_value(Map.get(posture, :unsupported, [])),
        source_binding_id: drilldown_value(Map.get(posture, :source_binding_id)),
        data_source_id: drilldown_value(Map.get(posture, :data_source_id)),
        realm: drilldown_value(Map.get(posture, :realm))
      }
    end)
  end

  defp capability_postures(_postures), do: []

  defp capability_posture_summary(postures) when is_list(postures) do
    postures
    |> capability_posture_values()
    |> case do
      [] -> nil
      values -> Enum.join(values, " ")
    end
  end

  defp capability_posture_summary(_postures), do: nil

  defp capability_posture_values(postures) when is_list(postures) do
    postures
    |> capability_postures()
    |> Enum.map(fn posture ->
      [
        posture.logical_source,
        posture.request_id,
        posture.status,
        posture.requested_time_axis,
        "->",
        posture.executed_time_axis
      ]
      |> Enum.reject(&(&1 in [nil, "", "-"]))
      |> Enum.join(":")
      |> String.replace(":->:", "->")
    end)
    |> Enum.reject(&(&1 in [nil, "", "-"]))
  end

  defp capability_posture_values(_postures), do: []

  defp dependency_evidence_values(dependencies) when is_list(dependencies) do
    dependencies
    |> dependency_evidence()
    |> Enum.map(fn dependency ->
      [
        dependency.request_logical_source,
        dependency.request_id,
        "->",
        dependency.logical_source,
        dependency.upstream_request_id,
        dependency.upstream_status,
        dependency.upstream_runtime_action,
        dependency.upstream_watermark_freshness_state
      ]
      |> Enum.reject(&(&1 in [nil, "", "-"]))
      |> Enum.join(":")
      |> String.replace(":->:", "->")
    end)
    |> Enum.reject(&(&1 in [nil, "", "-"]))
  end

  defp dependency_evidence_values(_dependencies), do: []

  defp source_execution_identity(outcome) do
    [
      Map.get(outcome, :logical_source),
      Map.get(outcome, :request_id),
      Map.get(outcome, :status)
    ]
    |> Enum.map_join(":", &RuntimeDiagnosticFormatter.value/1)
  end

  defp drilldown_value(nil), do: nil
  defp drilldown_value(value) when is_atom(value), do: Atom.to_string(value)
  defp drilldown_value(value) when is_binary(value), do: value
  defp drilldown_value(value) when is_integer(value), do: Integer.to_string(value)
  defp drilldown_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp drilldown_value(value), do: inspect(value)

  defp list_value(values) when is_list(values) do
    values
    |> Enum.map(&drilldown_value/1)
    |> Enum.reject(&(&1 in [nil, "", "-"]))
    |> Enum.join("+")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp list_value(value), do: drilldown_value(value)

  defp capability_details_value(details) when is_list(details) do
    details
    |> Enum.map(fn
      detail when is_map(detail) ->
        [
          Map.get(detail, :capability, Map.get(detail, "capability")),
          Map.get(detail, :requested, Map.get(detail, "requested")),
          Map.get(detail, :executed, Map.get(detail, "executed")),
          Map.get(detail, :fallback, Map.get(detail, "fallback")),
          Map.get(detail, :reason, Map.get(detail, "reason"))
        ]
        |> Enum.map(&drilldown_value/1)
        |> Enum.reject(&(&1 in [nil, "", "-"]))
        |> Enum.join(":")

      detail ->
        drilldown_value(detail)
    end)
    |> Enum.reject(&(&1 in [nil, "", "-"]))
    |> Enum.join("+")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp capability_details_value(value), do: drilldown_value(value)

  defp map_empty?(map) when is_map(map), do: map_size(map) == 0
  defp map_empty?(_map), do: true
end
