defmodule Cadence.Dashboards.RuntimeInvalidation.DecisionEvent do
  @moduledoc """
  Durable audit event for a dashboard runtime invalidation decision.

  The invalidation event records that a producer/cache boundary changed. This
  event records what one dashboard runtime decided to do with that change in its
  active context.
  """

  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias Cadence.Ids

  @type t :: %__MODULE__{
          dashboard_runtime_invalidation_decision_event_id: binary(),
          invalidation_event_id: binary() | nil,
          organization_id: binary() | nil,
          mission_id: binary() | nil,
          dashboard_id: binary() | nil,
          boundary: atom() | binary() | nil,
          domain_fact: atom() | binary() | nil,
          decision_status: atom() | binary() | nil,
          matches?: boolean() | nil,
          dashboard_matches?: boolean() | nil,
          context_matches?: boolean() | nil,
          context_reason: atom() | binary() | nil,
          refresh_allowed?: boolean() | nil,
          refresh_reason: atom() | binary() | nil,
          affected_placement_count: non_neg_integer() | nil,
          affected_placement_ids: [binary()],
          affected_widget_type_ids: [binary()],
          affected_impact_reasons: [atom() | binary()],
          invalidated_artifacts: non_neg_integer(),
          invalidation_occurred_at: DateTime.t() | nil,
          decision_observed_at: DateTime.t(),
          filters: map(),
          measurements: map(),
          decision: map(),
          payload: map()
        }

  defstruct [
    :dashboard_runtime_invalidation_decision_event_id,
    :invalidation_event_id,
    :organization_id,
    :mission_id,
    :dashboard_id,
    :boundary,
    :domain_fact,
    :decision_status,
    :matches?,
    :dashboard_matches?,
    :context_matches?,
    :context_reason,
    :refresh_allowed?,
    :refresh_reason,
    :affected_placement_count,
    :invalidation_occurred_at,
    :decision_observed_at,
    affected_placement_ids: [],
    affected_widget_type_ids: [],
    affected_impact_reasons: [],
    invalidated_artifacts: 0,
    filters: %{},
    measurements: %{},
    decision: %{},
    payload: %{}
  ]

  @spec new(Event.t(), map(), keyword()) :: t()
  def new(%Event{} = event, decision, opts \\ []) when is_map(decision) and is_list(opts) do
    %__MODULE__{
      dashboard_runtime_invalidation_decision_event_id: decision_event_id(opts),
      invalidation_event_id: invalidation_event_id(event, opts),
      organization_id: organization_id(event, decision),
      mission_id: mission_id(event, decision),
      dashboard_id: decision_value(decision, :dashboard_id),
      boundary: event.boundary,
      domain_fact: event.domain_fact,
      decision_status: decision_status(decision),
      matches?: matches?(decision),
      dashboard_matches?: dashboard_matches?(decision),
      context_matches?: context_matches?(decision),
      context_reason: context_reason(decision),
      refresh_allowed?: refresh_allowed?(decision),
      refresh_reason: refresh_reason(decision),
      affected_placement_count: affected_placement_count(decision),
      affected_placement_ids: affected_placement_ids(decision),
      affected_widget_type_ids: affected_widget_type_ids(decision),
      affected_impact_reasons: affected_impact_reasons(decision),
      invalidated_artifacts: artifact_count(event.measurements),
      invalidation_occurred_at: event.occurred_at,
      decision_observed_at: decision_observed_at(opts),
      filters: event.filters || %{},
      measurements: event.measurements || %{},
      decision: decision,
      payload: Keyword.get(opts, :payload, %{})
    }
  end

  defp decision_event_id(opts) do
    Keyword.get(opts, :decision_event_id) ||
      Keyword.get(opts, :dashboard_runtime_invalidation_decision_event_id) ||
      Ids.new("dashboard_runtime_invalidation_decision_event")
  end

  defp invalidation_event_id(%Event{} = event, opts),
    do: Keyword.get(opts, :invalidation_event_id) || Event.id(event)

  defp organization_id(%Event{} = event, decision),
    do: decision_value(decision, :organization_id) || map_value(event.filters, :organization_id)

  defp mission_id(%Event{} = event, decision),
    do: decision_value(decision, :mission_id) || map_value(event.filters, :mission_id)

  defp decision_status(decision), do: decision_value(decision, :decision_status)
  defp matches?(decision), do: decision_value(decision, :matches?)
  defp dashboard_matches?(decision), do: decision_value(decision, :dashboard_matches?)
  defp context_matches?(decision), do: decision_value(decision, :context_matches?)
  defp context_reason(decision), do: decision_value(decision, :context_reason)
  defp refresh_allowed?(decision), do: decision_value(decision, :refresh_allowed?)
  defp refresh_reason(decision), do: decision_value(decision, :refresh_reason)
  defp affected_placement_count(decision), do: decision_value(decision, :affected_placement_count)

  defp affected_placement_ids(decision),
    do: list_value(decision_value(decision, :affected_placement_ids))

  defp affected_widget_type_ids(decision),
    do: list_value(decision_value(decision, :affected_widget_type_ids))

  defp affected_impact_reasons(decision),
    do: list_value(decision_value(decision, :affected_impact_reasons))

  defp decision_observed_at(opts),
    do: Keyword.get(opts, :decision_observed_at) || DateTime.utc_now()

  @spec to_decision_row(t()) :: map()
  def to_decision_row(%__MODULE__{} = event) do
    %{
      dashboard_runtime_invalidation_decision_event_id:
        event.dashboard_runtime_invalidation_decision_event_id,
      invalidation_event_id: event.invalidation_event_id,
      dashboard_id: event.dashboard_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      boundary: event.boundary,
      domain_fact: event.domain_fact,
      decision_status: event.decision_status,
      matches?: event.matches?,
      dashboard_matches?: event.dashboard_matches?,
      context_matches?: event.context_matches?,
      context_reason: event.context_reason,
      refresh_allowed?: event.refresh_allowed?,
      refresh_reason: event.refresh_reason,
      affected_placement_count: event.affected_placement_count,
      affected_placement_ids: event.affected_placement_ids,
      affected_widget_type_ids: event.affected_widget_type_ids,
      affected_impact_reasons: event.affected_impact_reasons,
      selection_state: decision_value(event.decision, :selection_state),
      selected_link_id: decision_value(event.decision, :selected_link_id),
      selected_target: decision_value(event.decision, :selected_target),
      selected_target_id: decision_value(event.decision, :selected_target_id),
      selected_placement_id: decision_value(event.decision, :selected_placement_id),
      selected_observable_id: decision_value(event.decision, :selected_observable_id),
      selected_data_view: decision_value(event.decision, :selected_data_view),
      selection_affected?: decision_value(event.decision, :selection_affected?),
      selection_impact_reason: decision_value(event.decision, :selection_impact_reason),
      source_cache_evidence_state_summary:
        decision_value(event.decision, :source_cache_evidence_state_summary),
      source_cache_evidence_target_ids:
        list_value(decision_value(event.decision, :source_cache_evidence_target_ids)),
      source_cache_evidence_request_ids:
        list_value(decision_value(event.decision, :source_cache_evidence_request_ids)),
      source_execution_retryable_count:
        decision_value(event.decision, :source_execution_retryable_count),
      source_execution_actionable_count:
        decision_value(event.decision, :source_execution_actionable_count),
      source_execution_degraded_count:
        decision_value(event.decision, :source_execution_degraded_count),
      source_execution_status_summary:
        decision_value(event.decision, :source_execution_status_summary),
      source_execution_severity_summary:
        decision_value(event.decision, :source_execution_severity_summary),
      source_execution_runtime_action_summary:
        decision_value(event.decision, :source_execution_runtime_action_summary),
      source_execution_operator_action_summary:
        decision_value(event.decision, :source_execution_operator_action_summary),
      source_execution_degraded_identities:
        list_value(decision_value(event.decision, :source_execution_degraded_identities)),
      source_execution_degraded_actions:
        list_value(decision_value(event.decision, :source_execution_degraded_actions)),
      source_dependency_degraded_count:
        decision_value(event.decision, :source_dependency_degraded_count),
      source_dependency_evidence:
        list_value(decision_value(event.decision, :source_dependency_evidence)),
      invalidated_artifacts: event.invalidated_artifacts,
      invalidation_occurred_at: event.invalidation_occurred_at,
      decision_observed_at: event.decision_observed_at,
      filters: event.filters,
      measurements: event.measurements,
      decision: event.decision,
      source_event_present?: true
    }
  end

  defp decision_value(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp map_value(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp list_value(values) when is_list(values), do: values
  defp list_value(nil), do: []
  defp list_value(value), do: [value]

  defp artifact_count(measurements) when is_map(measurements) do
    case Map.get(measurements, :total, Map.get(measurements, "total", 0)) do
      count when is_integer(count) and count >= 0 -> count
      _other -> 0
    end
  end

  defp artifact_count(_measurements), do: 0
end
