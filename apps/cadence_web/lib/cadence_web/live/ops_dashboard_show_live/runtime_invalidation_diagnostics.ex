defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationDiagnostics do
  @moduledoc false

  alias Cadence.Dashboards.{Document, RuntimeInvalidationRelevance}
  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.RuntimeInvalidation.DecisionProjection
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticFormatter

  def summary(events, current_scope, mission, %Document{} = document) do
    RuntimeInvalidationRelevance.summarize_recent_events(
      events,
      current_scope,
      mission,
      document
    )
  end

  def recent_invalidations(events, current_scope, mission, document, runtime_context) do
    decisions_by_invalidation_id =
      runtime_invalidation_decisions_by_id(events, current_scope, mission, document)

    events
    |> RuntimeInvalidationRelevance.relevant_recent_events(current_scope, mission, document)
    |> Enum.map(
      &recent_runtime_invalidation_row(
        &1,
        current_scope,
        mission,
        document,
        runtime_context,
        decisions_by_invalidation_id
      )
    )
  end

  def relevance_summary(rows) when is_list(rows) do
    Enum.reduce(
      rows,
      %{context_matches: 0, context_filtered: 0, refresh_allowed: 0, refresh_suppressed: 0},
      fn row, summary ->
        summary
        |> increment_if(:context_matches, row.context_match == "true")
        |> increment_if(:context_filtered, row.context_match == "false")
        |> increment_if(:refresh_allowed, row.refresh_allowed == "true")
        |> increment_if(:refresh_suppressed, row.refresh_allowed == "false")
      end
    )
    |> put_relevance_reason_summaries(rows)
  end

  def rows(invalidation, invalidation_relevance, last_invalidation) do
    [
      diagnostic_row("Invalidation events", invalidation.event_count),
      diagnostic_row("Invalidated artifacts", invalidation.artifact_count),
      diagnostic_row("Boundaries", RuntimeInvalidationRelevance.boundary_summary(invalidation)),
      diagnostic_row("Context matches", invalidation_relevance.context_matches),
      diagnostic_row("Context filtered", invalidation_relevance.context_filtered),
      diagnostic_row("Context filter reasons", invalidation_relevance.context_reason_labels),
      diagnostic_row("Refresh allowed", invalidation_relevance.refresh_allowed),
      diagnostic_row("Refresh suppressed", invalidation_relevance.refresh_suppressed),
      diagnostic_row("Refresh suppress reasons", invalidation_relevance.refresh_reason_labels),
      diagnostic_row(
        "Last invalidation",
        RuntimeInvalidationRelevance.notice_boundary(last_invalidation)
      ),
      diagnostic_row(
        "Last refresh reason",
        RuntimeInvalidationRelevance.notice_refresh_reason(last_invalidation)
      ),
      diagnostic_row(
        "Last refresh action",
        RuntimeInvalidationRelevance.notice_refresh_action(last_invalidation)
      )
    ]
  end

  def attrs(invalidation, invalidation_relevance) do
    %{
      invalidation_event_count: invalidation.event_count,
      invalidation_artifact_count: invalidation.artifact_count,
      invalidation_boundary_summary:
        diagnostic_value(RuntimeInvalidationRelevance.boundary_summary(invalidation)),
      invalidation_context_match_count: invalidation_relevance.context_matches,
      invalidation_context_filtered_count: invalidation_relevance.context_filtered,
      invalidation_context_filter_reasons:
        diagnostic_value(invalidation_relevance.context_reasons),
      invalidation_refresh_allowed_count: invalidation_relevance.refresh_allowed,
      invalidation_refresh_suppressed_count: invalidation_relevance.refresh_suppressed,
      invalidation_refresh_suppress_reasons:
        diagnostic_value(invalidation_relevance.refresh_reasons)
    }
  end

  def no_refresh_summary(invalidation, relevance) do
    cond do
      invalidation.event_count == 0 ->
        %{visible?: false}

      relevance.refresh_allowed > 0 ->
        %{visible?: false}

      true ->
        %{
          visible?: true,
          status: no_refresh_status(relevance),
          headline: no_refresh_headline(relevance),
          context: no_refresh_context(relevance),
          refresh: no_refresh_refresh_policy(relevance)
        }
    end
  end

  def no_refresh_summary(invalidation, relevance, rows) when is_list(rows) do
    invalidation
    |> no_refresh_summary(relevance)
    |> put_no_refresh_blocker(rows)
  end

  def decision_status(%{matches?: false}, _refresh_relevance), do: :filtered

  def decision_status(%{matches?: true}, %{allowed?: true}),
    do: :refresh_allowed

  def decision_status(%{matches?: true}, %{allowed?: false}),
    do: :refresh_suppressed

  def event_id(event) do
    RuntimeInvalidation.Event.id(event)
  end

  defp recent_runtime_invalidation_row(
         event,
         current_scope,
         mission,
         document,
         runtime_context,
         decisions_by_invalidation_id
       ) do
    notice = RuntimeInvalidationRelevance.notice(event)
    event_id = event_id(event)

    context_relevance =
      RuntimeInvalidationRelevance.event_relevance(
        event,
        current_scope,
        mission,
        document,
        runtime_context
      )

    refresh_relevance = RuntimeInvalidationRelevance.refresh_relevance(event, runtime_context)
    decision = Map.get(decisions_by_invalidation_id, event_id)
    context_match = decision_value(decision, :matches?, context_relevance.matches?)
    context_reason = decision_value(decision, :context_reason, context_relevance.reason)
    refresh_allowed = decision_value(decision, :refresh_allowed?, refresh_relevance.allowed?)
    refresh_reason = decision_value(decision, :refresh_reason, refresh_relevance.reason)

    affected_placement_summary =
      event
      |> RuntimeInvalidationRelevance.affected_placements(document)
      |> RuntimeInvalidationRelevance.affected_placement_summary()

    lifecycle_correlation = lifecycle_correlation(event)

    %{
      id: event_id,
      dashboard_id: diagnostic_value(document.dashboard_id),
      mission_id: diagnostic_value(mission.mission_id),
      boundary: diagnostic_value(event.boundary),
      refresh_reason:
        diagnostic_value(RuntimeInvalidationRelevance.notice_refresh_reason(notice)),
      refresh_action:
        diagnostic_value(RuntimeInvalidationRelevance.notice_refresh_action(notice)),
      context_match: diagnostic_value(context_match),
      context_reason: diagnostic_value(context_reason),
      context_reason_label: context_reason_label(context_reason),
      refresh_allowed: diagnostic_value(refresh_allowed),
      refresh_allowed_reason: diagnostic_value(refresh_reason),
      refresh_allowed_reason_label: refresh_reason_label(refresh_reason),
      affected_placement_count:
        diagnostic_value(
          decision_value(
            decision,
            :affected_placement_count,
            affected_placement_summary.count
          )
        ),
      affected_placement_ids:
        diagnostic_list(
          decision_value(
            decision,
            :affected_placement_ids,
            affected_placement_summary.placement_ids
          )
        ),
      affected_widget_type_ids:
        diagnostic_list(
          decision_value(
            decision,
            :affected_widget_type_ids,
            affected_placement_summary.widget_type_ids
          )
        ),
      affected_impact_reasons:
        diagnostic_list(
          decision_value(
            decision,
            :affected_impact_reasons,
            affected_placement_summary.impact_reasons
          )
        ),
      selection_state: diagnostic_value(decision_value(decision, :selection_state, nil)),
      selected_link_id: diagnostic_value(decision_value(decision, :selected_link_id, nil)),
      selected_target: diagnostic_value(decision_value(decision, :selected_target, nil)),
      selected_target_id: diagnostic_value(decision_value(decision, :selected_target_id, nil)),
      selected_placement_id:
        diagnostic_value(decision_value(decision, :selected_placement_id, nil)),
      selected_observable_id:
        diagnostic_value(decision_value(decision, :selected_observable_id, nil)),
      selected_data_view: diagnostic_value(decision_value(decision, :selected_data_view, nil)),
      selection_affected: diagnostic_value(decision_value(decision, :selection_affected?, nil)),
      selection_impact_reason:
        diagnostic_value(decision_value(decision, :selection_impact_reason, nil)),
      source_cache_evidence_total:
        diagnostic_value(source_cache_evidence_count(decision, :total)),
      source_cache_evidence_resolved:
        diagnostic_value(source_cache_evidence_count(decision, :resolved)),
      source_cache_evidence_context_only:
        diagnostic_value(source_cache_evidence_count(decision, :context_only)),
      source_cache_evidence_missing:
        diagnostic_value(source_cache_evidence_count(decision, :missing)),
      source_cache_evidence_target_ids:
        diagnostic_list(decision_value(decision, :source_cache_evidence_target_ids, [])),
      source_cache_evidence_request_ids:
        diagnostic_list(decision_value(decision, :source_cache_evidence_request_ids, [])),
      source_execution_retryable_count:
        diagnostic_value(decision_value(decision, :source_execution_retryable_count, nil)),
      source_execution_actionable_count:
        diagnostic_value(decision_value(decision, :source_execution_actionable_count, nil)),
      source_execution_degraded_count:
        diagnostic_value(decision_value(decision, :source_execution_degraded_count, nil)),
      source_execution_status_summary:
        diagnostic_count_summary(decision_value(decision, :source_execution_status_summary, %{})),
      source_execution_severity_summary:
        diagnostic_count_summary(
          decision_value(decision, :source_execution_severity_summary, %{})
        ),
      source_execution_runtime_actions:
        diagnostic_count_summary(
          decision_value(decision, :source_execution_runtime_action_summary, %{})
        ),
      source_execution_operator_actions:
        diagnostic_count_summary(
          decision_value(decision, :source_execution_operator_action_summary, %{})
        ),
      source_execution_degraded_identities:
        diagnostic_list(decision_value(decision, :source_execution_degraded_identities, [])),
      source_execution_degraded_actions:
        diagnostic_list(decision_value(decision, :source_execution_degraded_actions, [])),
      source_dependency_degraded_count:
        diagnostic_value(decision_value(decision, :source_dependency_degraded_count, nil)),
      source_dependency_evidence:
        diagnostic_list(decision_value(decision, :source_dependency_evidence, [])),
      decision_status: diagnostic_value(decision_value(decision, :decision_status, nil)),
      decision_source:
        diagnostic_value(
          decision_value(
            decision,
            :decision_source,
            if(is_map(decision), do: :runtime_health, else: :computed)
          )
        ),
      decision_event_id:
        diagnostic_value(
          decision_value(decision, :dashboard_runtime_invalidation_decision_event_id, nil)
        ),
      decision_observed_at:
        diagnostic_value(
          runtime_invalidation_time(decision_value(decision, :decision_observed_at, nil))
        ),
      logical_source: diagnostic_value(Map.get(event.filters, :logical_source)),
      realm: diagnostic_value(Map.get(event.filters, :realm)),
      data_source_id: diagnostic_value(Map.get(event.filters, :data_source_id)),
      source_binding_id: diagnostic_value(Map.get(event.filters, :source_binding_id)),
      replay_run_id: diagnostic_value(Map.get(event.filters, :replay_run_id)),
      observable: diagnostic_value(Map.get(event.filters, :observable)),
      lifecycle_action: diagnostic_value(Map.get(event.filters, :lifecycle_action)),
      lifecycle_correlation_state: diagnostic_value(Map.get(lifecycle_correlation, :state)),
      lifecycle_correlation_label: diagnostic_value(Map.get(lifecycle_correlation, :label)),
      lifecycle_correlation_target_version:
        diagnostic_value(Map.get(lifecycle_correlation, :target_version)),
      lifecycle_correlation_source_version:
        diagnostic_value(Map.get(lifecycle_correlation, :source_version)),
      source_version: diagnostic_value(Map.get(event.filters, :source_version)),
      document_version: diagnostic_value(Map.get(event.filters, :document_version)),
      artifacts: diagnostic_value(Map.get(event.measurements, :total)),
      occurred_at: diagnostic_value(runtime_invalidation_time(event.occurred_at))
    }
  end

  defp runtime_invalidation_decisions_by_id(events, current_scope, mission, document)
       when is_list(events) do
    opts = [
      organization_id: current_scope.organization_id,
      mission_id: mission.mission_id,
      dashboard_id: document.dashboard_id,
      limit: length(events)
    ]

    case Cadence.durable_dashboard_runtime_invalidation_decisions(opts) do
      [] ->
        events
        |> DecisionProjection.list(opts)
        |> Enum.map(&Map.put(&1, :decision_source, :runtime_health))

      decisions ->
        Enum.map(decisions, &Map.put(&1, :decision_source, :durable_projection))
    end
    |> Enum.reduce(%{}, fn decision, decisions ->
      case Map.get(decision, :invalidation_event_id) do
        invalidation_event_id
        when is_binary(invalidation_event_id) and invalidation_event_id != "" ->
          Map.put_new(decisions, invalidation_event_id, decision)

        _other ->
          decisions
      end
    end)
  end

  defp runtime_invalidation_decisions_by_id(_events, _current_scope, _mission, _document), do: %{}

  defp decision_value(decision, key, fallback) when is_map(decision) do
    case Map.get(decision, key, Map.get(decision, Atom.to_string(key))) do
      nil -> nested_decision_value(decision, key, fallback)
      value -> value
    end
  end

  defp decision_value(_decision, _key, fallback), do: fallback

  defp nested_decision_value(decision, key, fallback) when is_map(decision) do
    case Map.get(decision, :decision, Map.get(decision, "decision")) do
      nested when is_map(nested) ->
        Map.get(nested, key, Map.get(nested, Atom.to_string(key), fallback))

      _missing ->
        fallback
    end
  end

  defp no_refresh_status(%{context_filtered: filtered, context_matches: matches})
       when filtered > 0 and matches > 0,
       do: "mixed_context_suppressed"

  defp no_refresh_status(%{context_filtered: filtered, context_matches: 0}) when filtered > 0,
    do: "context_filtered"

  defp no_refresh_status(%{refresh_suppressed: suppressed}) when suppressed > 0,
    do: "refresh_suppressed"

  defp no_refresh_status(_relevance), do: "no_refresh"

  defp no_refresh_headline(%{context_filtered: filtered, context_matches: matches})
       when filtered > 0 and matches > 0,
       do: "Some invalidations were filtered; matched invalidations were suppressed."

  defp no_refresh_headline(%{context_filtered: filtered, context_matches: 0}) when filtered > 0,
    do: "Invalidations were filtered by the current runtime context."

  defp no_refresh_headline(%{refresh_suppressed: suppressed}) when suppressed > 0,
    do: "Invalidations matched, but refresh was suppressed."

  defp no_refresh_headline(_relevance), do: "No refresh was started."

  defp no_refresh_context(%{context_filtered: filtered, context_reason_labels: reasons})
       when filtered > 0,
       do: "Context: #{diagnostic_value(reasons)}"

  defp no_refresh_context(_relevance), do: "Context: all recent invalidations matched"

  defp no_refresh_refresh_policy(%{
         refresh_suppressed: suppressed,
         refresh_reason_labels: reasons
       })
       when suppressed > 0,
       do: "Refresh: #{diagnostic_value(reasons)}"

  defp no_refresh_refresh_policy(_relevance), do: "Refresh: no suppressing policy"

  defp put_no_refresh_blocker(%{visible?: true} = summary, rows) do
    Map.put(summary, :blocker, no_refresh_blocker(rows))
  end

  defp put_no_refresh_blocker(summary, _rows), do: summary

  defp no_refresh_blocker(rows) do
    rows
    |> Enum.filter(
      &(Map.get(&1, :context_match) == "false" or Map.get(&1, :refresh_allowed) == "false")
    )
    |> Enum.sort_by(&no_refresh_blocker_sort_key/1, :desc)
    |> List.first()
    |> no_refresh_blocker_row()
  end

  defp no_refresh_blocker_sort_key(row) do
    [
      Map.get(row, :decision_observed_at),
      Map.get(row, :occurred_at),
      Map.get(row, :id)
    ]
    |> Enum.map(&diagnostic_value/1)
    |> Enum.reject(&(&1 in ["", "-"]))
    |> Enum.join("|")
  end

  defp no_refresh_blocker_row(nil), do: nil

  defp no_refresh_blocker_row(row) do
    %{
      id: Map.get(row, :id),
      dashboard_id: Map.get(row, :dashboard_id),
      mission_id: Map.get(row, :mission_id),
      boundary: Map.get(row, :boundary),
      refresh_action: Map.get(row, :refresh_action),
      logical_source: Map.get(row, :logical_source),
      realm: Map.get(row, :realm),
      data_source_id: Map.get(row, :data_source_id),
      source_binding_id: Map.get(row, :source_binding_id),
      observable: Map.get(row, :observable),
      replay_run_id: Map.get(row, :replay_run_id),
      lifecycle_action: Map.get(row, :lifecycle_action),
      decision_status: Map.get(row, :decision_status),
      decision_source: Map.get(row, :decision_source),
      decision_event_id: Map.get(row, :decision_event_id),
      decision_observed_at: Map.get(row, :decision_observed_at),
      context_reason_filter: Map.get(row, :context_reason),
      context_reason: Map.get(row, :context_reason_label),
      refresh_reason_filter: Map.get(row, :refresh_allowed_reason),
      refresh_reason: Map.get(row, :refresh_allowed_reason_label),
      affected_placement_count: Map.get(row, :affected_placement_count),
      affected_placement_ids: Map.get(row, :affected_placement_ids),
      affected_impact_reasons: Map.get(row, :affected_impact_reasons),
      source_cache_evidence_total: Map.get(row, :source_cache_evidence_total),
      source_cache_evidence_resolved: Map.get(row, :source_cache_evidence_resolved),
      source_cache_evidence_context_only: Map.get(row, :source_cache_evidence_context_only),
      source_cache_evidence_missing: Map.get(row, :source_cache_evidence_missing),
      source_cache_evidence_target_ids: Map.get(row, :source_cache_evidence_target_ids),
      source_cache_evidence_request_ids: Map.get(row, :source_cache_evidence_request_ids),
      source_execution_retryable_count: Map.get(row, :source_execution_retryable_count),
      source_execution_actionable_count: Map.get(row, :source_execution_actionable_count),
      source_execution_degraded_count: Map.get(row, :source_execution_degraded_count),
      source_execution_status_summary: Map.get(row, :source_execution_status_summary),
      source_execution_severity_summary: Map.get(row, :source_execution_severity_summary),
      source_execution_runtime_actions: Map.get(row, :source_execution_runtime_actions),
      source_execution_operator_actions: Map.get(row, :source_execution_operator_actions),
      source_execution_degraded_identities: Map.get(row, :source_execution_degraded_identities),
      source_execution_degraded_actions: Map.get(row, :source_execution_degraded_actions),
      source_dependency_degraded_count: Map.get(row, :source_dependency_degraded_count),
      source_dependency_evidence: Map.get(row, :source_dependency_evidence),
      occurred_at: Map.get(row, :occurred_at)
    }
  end

  defp source_cache_evidence_count(decision, key) do
    decision
    |> decision_value(:source_cache_evidence_state_summary, %{})
    |> map_value(key)
  end

  defp map_value(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp map_value(_attrs, _key), do: nil

  defp increment_if(summary, key, true), do: Map.update!(summary, key, &(&1 + 1))
  defp increment_if(summary, _key, false), do: summary

  defp put_relevance_reason_summaries(summary, rows) do
    summary
    |> Map.put(
      :context_reasons,
      rows
      |> Enum.filter(&(&1.context_match == "false"))
      |> count_row_reasons(:context_reason)
    )
    |> Map.put(
      :refresh_reasons,
      rows
      |> Enum.filter(&(&1.refresh_allowed == "false"))
      |> count_row_reasons(:refresh_allowed_reason)
    )
    |> Map.put(
      :context_reason_labels,
      rows
      |> Enum.filter(&(&1.context_match == "false"))
      |> count_row_reasons(:context_reason_label)
    )
    |> Map.put(
      :refresh_reason_labels,
      rows
      |> Enum.filter(&(&1.refresh_allowed == "false"))
      |> count_row_reasons(:refresh_allowed_reason_label)
    )
  end

  defp count_row_reasons(rows, key) do
    rows
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.frequencies()
    |> diagnostic_count_summary()
  end

  defp context_reason_label(:matched), do: "matched"
  defp context_reason_label(:realm_mismatch), do: "filtered by realm"
  defp context_reason_label(:replay_run_mismatch), do: "filtered by replay run"
  defp context_reason_label(:data_source_mismatch), do: "filtered by data source"
  defp context_reason_label(:source_binding_mismatch), do: "filtered by binding"
  defp context_reason_label(:scope_mismatch), do: "outside dashboard scope"
  defp context_reason_label(:document_not_relevant), do: "not used by dashboard"
  defp context_reason_label(:invalid_event), do: "invalid event"
  defp context_reason_label(reason), do: diagnostic_value(reason)

  defp refresh_reason_label(:allowed), do: "refresh allowed"
  defp refresh_reason_label(:stale_for_context), do: "stale before current context"
  defp refresh_reason_label(:edit_mode), do: "editing dashboard"
  defp refresh_reason_label(:non_live_boundary), do: "not refreshable in live mode"
  defp refresh_reason_label(:snapshot_time_mismatch), do: "outside snapshot time range"
  defp refresh_reason_label(:invalid_event), do: "invalid event"
  defp refresh_reason_label(reason), do: diagnostic_value(reason)

  defp lifecycle_correlation(%RuntimeInvalidation.Event{
         boundary: :dashboard_version_changed,
         filters: filters
       })
       when is_map(filters) do
    action = Map.get(filters, :lifecycle_action)
    document_version = Map.get(filters, :document_version)
    source_version = Map.get(filters, :source_version)

    %{
      state: lifecycle_correlation_state(action),
      label: lifecycle_correlation_label(action, document_version, source_version),
      target_version: document_version,
      source_version: source_version
    }
  end

  defp lifecycle_correlation(_event) do
    %{
      state: :not_lifecycle_change,
      label: nil,
      target_version: nil,
      source_version: nil
    }
  end

  defp lifecycle_correlation_state(:published), do: :published
  defp lifecycle_correlation_state(:reverted), do: :restored_as_draft
  defp lifecycle_correlation_state(:archived), do: :archived
  defp lifecycle_correlation_state(:restored), do: :restored
  defp lifecycle_correlation_state(:draft_saved), do: :draft_saved
  defp lifecycle_correlation_state(:created), do: :created
  defp lifecycle_correlation_state(:migrated), do: :migrated
  defp lifecycle_correlation_state(:deleted), do: :deleted
  defp lifecycle_correlation_state("published"), do: :published
  defp lifecycle_correlation_state("reverted"), do: :restored_as_draft
  defp lifecycle_correlation_state("archived"), do: :archived
  defp lifecycle_correlation_state("restored"), do: :restored
  defp lifecycle_correlation_state("draft_saved"), do: :draft_saved
  defp lifecycle_correlation_state("created"), do: :created
  defp lifecycle_correlation_state("migrated"), do: :migrated
  defp lifecycle_correlation_state("deleted"), do: :deleted

  defp lifecycle_correlation_state(_action), do: :dashboard_version_changed

  defp lifecycle_correlation_label(:published, document_version, _source_version) do
    "Published #{version_label(document_version)} invalidated dashboard plan"
  end

  defp lifecycle_correlation_label("published", document_version, source_version),
    do: lifecycle_correlation_label(:published, document_version, source_version)

  defp lifecycle_correlation_label(:reverted, document_version, source_version) do
    "Restored #{version_label(source_version)} as #{version_label(document_version)} invalidated dashboard plan"
  end

  defp lifecycle_correlation_label("reverted", document_version, source_version),
    do: lifecycle_correlation_label(:reverted, document_version, source_version)

  defp lifecycle_correlation_label(:archived, document_version, _source_version) do
    "Archived #{version_label(document_version)} invalidated dashboard plan"
  end

  defp lifecycle_correlation_label("archived", document_version, source_version),
    do: lifecycle_correlation_label(:archived, document_version, source_version)

  defp lifecycle_correlation_label(:restored, document_version, _source_version) do
    "Restored dashboard at #{version_label(document_version)} invalidated dashboard plan"
  end

  defp lifecycle_correlation_label("restored", document_version, source_version),
    do: lifecycle_correlation_label(:restored, document_version, source_version)

  defp lifecycle_correlation_label(:draft_saved, document_version, _source_version) do
    "Saved draft #{version_label(document_version)} invalidated dashboard plan"
  end

  defp lifecycle_correlation_label("draft_saved", document_version, source_version),
    do: lifecycle_correlation_label(:draft_saved, document_version, source_version)

  defp lifecycle_correlation_label(action, document_version, _source_version) do
    action_label = action |> diagnostic_value() |> String.replace("_", " ")

    "#{String.capitalize(action_label)} #{version_label(document_version)} invalidated dashboard plan"
  end

  defp version_label(version) when is_integer(version) and version > 0, do: "v#{version}"

  defp version_label(version) when is_binary(version) do
    case Integer.parse(version) do
      {parsed, ""} when parsed > 0 -> "v#{parsed}"
      _invalid -> diagnostic_value(version)
    end
  end

  defp version_label(_version), do: "dashboard"

  defp runtime_invalidation_time(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp runtime_invalidation_time(_value), do: nil

  defp diagnostic_count_summary(counts), do: RuntimeDiagnosticFormatter.count_summary(counts)

  defp diagnostic_list(values), do: RuntimeDiagnosticFormatter.list(values)

  defp diagnostic_row(label, value), do: RuntimeDiagnosticFormatter.row(label, value)

  defp diagnostic_value(value), do: RuntimeDiagnosticFormatter.value(value)
end
