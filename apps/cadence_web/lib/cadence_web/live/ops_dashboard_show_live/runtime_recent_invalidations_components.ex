defmodule CadenceWeb.OpsDashboardShowLive.RuntimeRecentInvalidationsComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Dashboards.LifecycleEvent
  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.LifecycleRuntimeCorrelation
  alias CadenceWeb.OpsDashboardShowLive.RuntimeAdminDecisionLink

  attr :invalidations, :list, required: true
  attr :dashboard_lifecycle_events, :list, default: []
  attr :dashboard_current_path, :string, default: nil

  def recent_invalidations(assigns) do
    presentation =
      recent_invalidations_dto(
        assigns.invalidations,
        Map.get(assigns, :dashboard_lifecycle_events, []),
        Map.get(assigns, :dashboard_current_path)
      )

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id="dashboard-recent-invalidations-component"
      v-component="RuntimeRecentInvalidations"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp recent_invalidations_dto(invalidations, lifecycle_events, current_path) do
    %{
      section: %{
        class: "space-y-2",
        data_attrs: string_data_attrs(%{"data-diagnostics-section" => "Recent invalidations"})
      },
      header: %{
        class: "flex items-center justify-between",
        heading: %{class: "hud-label", text: "Recent invalidations"},
        count: %{
          class: "font-mono text-xs text-base-content/50",
          value: length(invalidations)
        }
      },
      list: %{id: "dashboard-recent-invalidations", class: "space-y-2"},
      events: Enum.map(invalidations, &event_dto(&1, lifecycle_events, current_path)),
      empty: %{
        visible: invalidations == [],
        class: "text-sm text-base-content/60",
        text: "No runtime invalidations."
      }
    }
  end

  defp event_dto(event, lifecycle_events, current_path) do
    activity_link = activity_event_link(event, lifecycle_events, current_path)
    decision_link = admin_decision_link(event)

    %{
      id: "dashboard-runtime-invalidation-#{event.id}",
      class: "border border-base-300/70 bg-base-100/40 px-2 py-2",
      data_attrs: event_data_attrs(event, lifecycle_events, activity_link, decision_link),
      badges_class: "flex flex-wrap items-center gap-1.5",
      badges: [
        %{class: "badge badge-xs badge-outline", text: event.boundary},
        %{class: "badge badge-xs", text: event.logical_source},
        %{class: "font-mono text-xs text-base-content/60", text: event.artifacts}
      ],
      actions:
        [
          action_dto(
            activity_link,
            "Open activity",
            "data-runtime-invalidation-activity-link-action"
          ),
          action_dto(
            decision_link,
            "Runtime decision",
            "data-runtime-invalidation-admin-decision-link-action"
          )
        ]
        |> Enum.reject(&is_nil/1),
      fields_class: "mt-2 grid grid-cols-[5.75rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
      fields: event_fields(event)
    }
  end

  defp event_data_attrs(event, lifecycle_events, activity_link, decision_link) do
    %{
      "data-runtime-invalidation-dashboard" => invalidation_field(event, :dashboard_id),
      "data-runtime-invalidation-mission" => invalidation_field(event, :mission_id),
      "data-runtime-invalidation-boundary" => event.boundary,
      "data-runtime-invalidation-source" => event.logical_source,
      "data-runtime-invalidation-realm" => event.realm,
      "data-runtime-invalidation-data-source" => event.data_source_id,
      "data-runtime-invalidation-binding" => event.source_binding_id,
      "data-runtime-invalidation-replay-run-id" => event.replay_run_id,
      "data-runtime-invalidation-observable" => event.observable,
      "data-runtime-invalidation-lifecycle-action" => event.lifecycle_action,
      "data-runtime-invalidation-lifecycle-correlation-state" =>
        invalidation_field(event, :lifecycle_correlation_state),
      "data-runtime-invalidation-lifecycle-correlation-label" =>
        invalidation_field(event, :lifecycle_correlation_label),
      "data-runtime-invalidation-lifecycle-target-version" =>
        invalidation_field(event, :lifecycle_correlation_target_version),
      "data-runtime-invalidation-lifecycle-source-version" =>
        invalidation_field(event, :lifecycle_correlation_source_version),
      "data-runtime-invalidation-activity-event-id" => activity_event_id(event, lifecycle_events),
      "data-runtime-invalidation-activity-link" => activity_link,
      "data-runtime-invalidation-admin-decision-link" => decision_link,
      "data-runtime-invalidation-source-version" => event.source_version,
      "data-runtime-invalidation-document-version" => event.document_version,
      "data-runtime-invalidation-context-match" => event.context_match,
      "data-runtime-invalidation-context-reason" => event.context_reason,
      "data-runtime-invalidation-refresh-allowed" => event.refresh_allowed,
      "data-runtime-invalidation-refresh-allowed-reason" => event.refresh_allowed_reason,
      "data-runtime-invalidation-refresh-reason" => event.refresh_reason,
      "data-runtime-invalidation-refresh-action" => event.refresh_action,
      "data-runtime-invalidation-decision-status" => event.decision_status,
      "data-runtime-invalidation-decision-source" => event.decision_source,
      "data-runtime-invalidation-decision-event-id" => event.decision_event_id,
      "data-runtime-invalidation-decision-observed-at" => event.decision_observed_at,
      "data-runtime-invalidation-affected-placement-count" => event.affected_placement_count,
      "data-runtime-invalidation-affected-placement-ids" => event.affected_placement_ids,
      "data-runtime-invalidation-affected-widget-types" => event.affected_widget_type_ids,
      "data-runtime-invalidation-affected-impact-reasons" => event.affected_impact_reasons,
      "data-runtime-invalidation-selection-state" => invalidation_field(event, :selection_state),
      "data-runtime-invalidation-selected-link" => invalidation_field(event, :selected_link_id),
      "data-runtime-invalidation-selected-target" => invalidation_field(event, :selected_target),
      "data-runtime-invalidation-selected-target-id" =>
        invalidation_field(event, :selected_target_id),
      "data-runtime-invalidation-selected-placement-id" =>
        invalidation_field(event, :selected_placement_id),
      "data-runtime-invalidation-selected-observable" =>
        invalidation_field(event, :selected_observable_id),
      "data-runtime-invalidation-selected-data-view" =>
        invalidation_field(event, :selected_data_view),
      "data-runtime-invalidation-selection-affected" =>
        invalidation_field(event, :selection_affected),
      "data-runtime-invalidation-selection-impact-reason" =>
        invalidation_field(event, :selection_impact_reason),
      "data-runtime-invalidation-source-cache-evidence-total" =>
        invalidation_field(event, :source_cache_evidence_total),
      "data-runtime-invalidation-source-cache-evidence-resolved" =>
        invalidation_field(event, :source_cache_evidence_resolved),
      "data-runtime-invalidation-source-cache-evidence-context-only" =>
        invalidation_field(event, :source_cache_evidence_context_only),
      "data-runtime-invalidation-source-cache-evidence-missing" =>
        invalidation_field(event, :source_cache_evidence_missing),
      "data-runtime-invalidation-source-cache-evidence-targets" =>
        invalidation_field(event, :source_cache_evidence_target_ids),
      "data-runtime-invalidation-source-cache-evidence-requests" =>
        invalidation_field(event, :source_cache_evidence_request_ids),
      "data-runtime-invalidation-source-execution-retryable" =>
        invalidation_field(event, :source_execution_retryable_count),
      "data-runtime-invalidation-source-execution-actionable" =>
        invalidation_field(event, :source_execution_actionable_count),
      "data-runtime-invalidation-source-execution-degraded" =>
        invalidation_field(event, :source_execution_degraded_count),
      "data-runtime-invalidation-source-execution-statuses" =>
        invalidation_field(event, :source_execution_status_summary),
      "data-runtime-invalidation-source-execution-actions" =>
        invalidation_field(event, :source_execution_runtime_actions),
      "data-runtime-invalidation-source-execution-degraded-identities" =>
        invalidation_field(event, :source_execution_degraded_identities),
      "data-runtime-invalidation-source-execution-degraded-actions" =>
        invalidation_field(event, :source_execution_degraded_actions),
      "data-runtime-invalidation-source-dependency-degraded" =>
        invalidation_field(event, :source_dependency_degraded_count),
      "data-runtime-invalidation-source-dependency-evidence" =>
        invalidation_field(event, :source_dependency_evidence),
      "data-runtime-invalidation-artifacts" => event.artifacts,
      "data-runtime-invalidation-occurred-at" => event.occurred_at
    }
    |> string_data_attrs()
  end

  defp action_dto(nil, _text, _data_attr), do: nil

  defp action_dto(href, text, data_attr) do
    %{
      href: href,
      class: "btn btn-ghost btn-xs mt-2",
      text: text,
      data_attrs:
        string_data_attrs(%{
          data_attr => "",
          "data-phx-link" => "redirect",
          "data-phx-link-state" => "push"
        }),
      icon: %{name: "hero-arrow-top-right-on-square", class: "h-3.5 w-3.5"}
    }
  end

  defp event_fields(event) do
    [
      field_dto("Observable", "Observable", event.observable),
      field_dto("Realm", "Realm", event.realm),
      field_dto("Source", "Source", event.data_source_id),
      field_dto("Binding", "Binding", event.source_binding_id),
      field_dto("Replay", "Replay", event.replay_run_id),
      field_dto("Context", "Context", event.context_match),
      field_dto("Ctx reason", "Context reason", event.context_reason_label),
      field_dto("Allowed", "Allowed", event.refresh_allowed),
      field_dto("Allow reason", "Allowed reason", event.refresh_allowed_reason_label),
      field_dto("Decision", "Decision", event.decision_status),
      field_dto("Source", "Decision source", event.decision_source),
      field_dto("Decision ID", "Decision ID", event.decision_event_id),
      field_dto("Decision at", "Decision observed", event.decision_observed_at),
      field_dto("Impacted", "Impacted", event.affected_placement_count),
      field_dto("Placements", "Placements", event.affected_placement_ids),
      field_dto("Widgets", "Widgets", event.affected_widget_type_ids),
      field_dto("Impact", "Impact", event.affected_impact_reasons),
      field_dto("Selection", "Selection", invalidation_field(event, :selection_affected)),
      field_dto(
        "Sel reason",
        "Selection reason",
        invalidation_field(event, :selection_impact_reason)
      ),
      field_dto(
        "Sel target",
        "Selection target",
        invalidation_field(event, :selected_target)
      ),
      field_dto("Sel ID", "Selection ID", invalidation_field(event, :selected_target_id)),
      field_dto("Evidence", "Source cache evidence", source_cache_evidence_summary(event)),
      field_dto(
        "Ev targets",
        "Source cache evidence targets",
        invalidation_field(event, :source_cache_evidence_target_ids)
      ),
      field_dto(
        "Ev requests",
        "Source cache evidence requests",
        invalidation_field(event, :source_cache_evidence_request_ids)
      ),
      field_dto(
        "Src exec",
        "Source execution",
        invalidation_field(event, :source_execution_status_summary)
      ),
      field_dto(
        "Src actions",
        "Source execution actions",
        invalidation_field(event, :source_execution_runtime_actions)
      ),
      field_dto(
        "Src degraded",
        "Source execution degraded",
        invalidation_field(event, :source_execution_degraded_identities)
      ),
      field_dto(
        "Src d-actions",
        "Source execution degraded actions",
        invalidation_field(event, :source_execution_degraded_actions)
      ),
      field_dto(
        "Src deps",
        "Source dependency degraded",
        invalidation_field(event, :source_dependency_degraded_count)
      ),
      field_dto(
        "Src dep ev",
        "Source dependency evidence",
        invalidation_field(event, :source_dependency_evidence)
      ),
      field_dto("Action", "Action", event.lifecycle_action),
      field_dto(
        "Lifecycle",
        "Lifecycle",
        invalidation_field(event, :lifecycle_correlation_label)
      ),
      field_dto("Version", "Version", event.document_version),
      field_dto("Reason", "Reason", event.refresh_reason),
      field_dto("Refresh", "Refresh", event.refresh_action),
      field_dto("Time", "Time", event.occurred_at)
    ]
  end

  defp field_dto(label, data_label, value) do
    %{
      key: data_label,
      label: label,
      value: value,
      label_class: "text-base-content/60",
      value_class: "font-mono text-base-content break-all",
      data_attrs: string_data_attrs(%{"data-invalidation-field" => data_label})
    }
  end

  defp string_data_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_key, nil}, data_attrs ->
        data_attrs

      {key, value}, data_attrs ->
        Map.put(data_attrs, to_string(key), data_attr_value(value))
    end)
  end

  defp data_attr_value(value) when is_binary(value), do: value
  defp data_attr_value(value) when is_boolean(value), do: to_string(value)
  defp data_attr_value(value) when is_number(value), do: to_string(value)
  defp data_attr_value(value) when is_atom(value), do: Atom.to_string(value)
  defp data_attr_value(value), do: inspect(value)

  defp invalidation_field(event, key) when is_map(event), do: Map.get(event, key, "-")
  defp invalidation_field(_event, _key), do: "-"

  defp source_cache_evidence_summary(event) do
    [
      {"total", invalidation_field(event, :source_cache_evidence_total)},
      {"resolved", invalidation_field(event, :source_cache_evidence_resolved)},
      {"context", invalidation_field(event, :source_cache_evidence_context_only)},
      {"missing", invalidation_field(event, :source_cache_evidence_missing)}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, "", "-"] end)
    |> case do
      [] -> "-"
      parts -> Enum.map_join(parts, " ", fn {label, value} -> "#{label}:#{value}" end)
    end
  end

  defp activity_event_link(event, lifecycle_events, current_path) when is_binary(current_path) do
    case LifecycleRuntimeCorrelation.activity_event(event, lifecycle_events) do
      %LifecycleEvent{} = lifecycle_event ->
        ActivityNavigation.link(current_path, :version_changes, lifecycle_event)

      nil ->
        nil
    end
  end

  defp activity_event_link(_event, _lifecycle_events, _current_path), do: nil

  defp activity_event_id(event, lifecycle_events) do
    LifecycleRuntimeCorrelation.activity_event_id(event, lifecycle_events)
  end

  defp admin_decision_link(event) do
    RuntimeAdminDecisionLink.from_runtime_invalidation(event)
  end
end
