defmodule CadenceWeb.OpsDashboardShowLive.RuntimeNoRefreshSummaryComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.RuntimeAdminDecisionLink

  attr(:summary, :map, required: true)

  def no_refresh_summary(%{summary: %{visible?: true}} = assigns) do
    assigns =
      assign(assigns, :no_refresh_summary, no_refresh_summary_presentation(assigns.summary))

    ~H"""
    <.vue
      id="dashboard-no-refresh-summary-component"
      v-component="RuntimeNoRefreshSummary"
      summary={@no_refresh_summary}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def no_refresh_summary(assigns), do: ~H""

  def no_refresh_summary_presentation(summary) do
    admin_decision_href = admin_decision_link(summary)

    %{
      section: %{
        id: "dashboard-no-refresh-summary",
        class: "border border-warning/30 bg-warning/10 px-3 py-2 text-sm",
        attributes: section_attributes(summary, admin_decision_href)
      },
      heading: %{class: "hud-label", text: "Why no refresh?"},
      headline: %{class: "mt-1 text-base-content", text: rendered_string(summary.headline)},
      fields: %{
        class: "mt-2 grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
        rows: [
          field_dto(
            "context",
            "Context",
            "data-no-refresh-field",
            rendered_string(summary.context)
          ),
          field_dto(
            "refresh",
            "Refresh",
            "data-no-refresh-field",
            rendered_string(summary.refresh)
          )
        ]
      },
      blocker: blocker_dto(summary),
      admin_action: admin_action_dto(admin_decision_href)
    }
  end

  defp section_attributes(summary, admin_decision_href) do
    %{
      "data-diagnostics-section" => "No refresh summary",
      "data-no-refresh-status" => rendered_string(summary.status),
      "data-no-refresh-context" => rendered_string(summary.context),
      "data-no-refresh-refresh" => rendered_string(summary.refresh),
      "data-no-refresh-blocking-boundary" => no_refresh_blocker_value(summary, :boundary),
      "data-no-refresh-blocking-refresh-action" =>
        no_refresh_blocker_value(summary, :refresh_action),
      "data-no-refresh-blocking-logical-source" =>
        no_refresh_blocker_value(summary, :logical_source),
      "data-no-refresh-blocking-realm" => no_refresh_blocker_value(summary, :realm),
      "data-no-refresh-blocking-data-source" =>
        no_refresh_blocker_value(summary, :data_source_id),
      "data-no-refresh-blocking-source-binding" =>
        no_refresh_blocker_value(summary, :source_binding_id),
      "data-no-refresh-blocking-source" => no_refresh_blocker_value(summary, :decision_source),
      "data-no-refresh-blocking-decision-id" =>
        no_refresh_blocker_value(summary, :decision_event_id),
      "data-no-refresh-blocking-observable" => no_refresh_blocker_value(summary, :observable),
      "data-no-refresh-blocking-lifecycle-action" =>
        no_refresh_blocker_value(summary, :lifecycle_action),
      "data-no-refresh-blocking-context" => no_refresh_blocker_value(summary, :context_reason),
      "data-no-refresh-blocking-refresh" => no_refresh_blocker_value(summary, :refresh_reason),
      "data-no-refresh-blocking-placements" =>
        no_refresh_blocker_value(summary, :affected_placement_ids),
      "data-no-refresh-blocking-impact" =>
        no_refresh_blocker_value(summary, :affected_impact_reasons),
      "data-no-refresh-blocking-source-cache-evidence-total" =>
        no_refresh_blocker_value(summary, :source_cache_evidence_total),
      "data-no-refresh-blocking-source-cache-evidence-resolved" =>
        no_refresh_blocker_value(summary, :source_cache_evidence_resolved),
      "data-no-refresh-blocking-source-cache-evidence-context-only" =>
        no_refresh_blocker_value(summary, :source_cache_evidence_context_only),
      "data-no-refresh-blocking-source-cache-evidence-missing" =>
        no_refresh_blocker_value(summary, :source_cache_evidence_missing),
      "data-no-refresh-blocking-source-cache-evidence-targets" =>
        no_refresh_blocker_value(summary, :source_cache_evidence_target_ids),
      "data-no-refresh-blocking-source-cache-evidence-requests" =>
        no_refresh_blocker_value(summary, :source_cache_evidence_request_ids),
      "data-no-refresh-blocking-source-execution-retryable" =>
        no_refresh_blocker_value(summary, :source_execution_retryable_count),
      "data-no-refresh-blocking-source-execution-actionable" =>
        no_refresh_blocker_value(summary, :source_execution_actionable_count),
      "data-no-refresh-blocking-source-execution-degraded" =>
        no_refresh_blocker_value(summary, :source_execution_degraded_count),
      "data-no-refresh-blocking-source-execution-statuses" =>
        no_refresh_blocker_value(summary, :source_execution_status_summary),
      "data-no-refresh-blocking-source-execution-actions" =>
        no_refresh_blocker_value(summary, :source_execution_runtime_actions),
      "data-no-refresh-blocking-source-execution-degraded-identities" =>
        no_refresh_blocker_value(summary, :source_execution_degraded_identities),
      "data-no-refresh-blocking-source-execution-degraded-actions" =>
        no_refresh_blocker_value(summary, :source_execution_degraded_actions),
      "data-no-refresh-blocking-source-dependency-degraded" =>
        no_refresh_blocker_value(summary, :source_dependency_degraded_count),
      "data-no-refresh-blocking-source-dependency-evidence" =>
        no_refresh_blocker_value(summary, :source_dependency_evidence)
    }
    |> maybe_put_admin_decision_link(admin_decision_href)
  end

  defp maybe_put_admin_decision_link(attributes, nil), do: attributes

  defp maybe_put_admin_decision_link(attributes, href) do
    Map.put(attributes, "data-no-refresh-blocking-admin-decision-link", href)
  end

  defp blocker_dto(summary) do
    if is_map(Map.get(summary, :blocker)) do
      %{
        id: "dashboard-no-refresh-blocker",
        class:
          "mt-3 grid grid-cols-[5.75rem_minmax(0,1fr)] gap-x-2 gap-y-1 border-t border-warning/30 pt-2 text-xs",
        rows: blocker_rows(summary)
      }
    end
  end

  defp blocker_rows(summary) do
    [
      blocker_field_dto(
        "boundary",
        "Boundary",
        "Boundary",
        no_refresh_blocker_value(summary, :boundary)
      ),
      blocker_field_dto(
        "observable",
        "Observable",
        "Observable",
        no_refresh_blocker_value(summary, :observable)
      ),
      blocker_field_dto(
        "action",
        "Action",
        "Action",
        no_refresh_blocker_value(summary, :refresh_action)
      ),
      blocker_field_dto("identity", "Identity", "Identity", no_refresh_blocker_identity(summary)),
      blocker_field_dto(
        "lifecycle",
        "Lifecycle",
        "Lifecycle",
        no_refresh_blocker_value(summary, :lifecycle_action)
      ),
      blocker_field_dto(
        "decision-source",
        "Source",
        "Decision source",
        no_refresh_blocker_value(summary, :decision_source)
      ),
      blocker_field_dto(
        "decision-id",
        "Decision ID",
        "Decision ID",
        no_refresh_blocker_value(summary, :decision_event_id)
      ),
      blocker_field_dto(
        "context",
        "Context",
        "Context",
        no_refresh_blocker_value(summary, :context_reason)
      ),
      blocker_field_dto(
        "refresh",
        "Refresh",
        "Refresh",
        no_refresh_blocker_value(summary, :refresh_reason)
      ),
      blocker_field_dto(
        "placements",
        "Placements",
        "Placements",
        no_refresh_blocker_value(summary, :affected_placement_ids)
      ),
      blocker_field_dto(
        "impact",
        "Impact",
        "Impact",
        no_refresh_blocker_value(summary, :affected_impact_reasons)
      ),
      blocker_field_dto(
        "source-cache-evidence",
        "Evidence",
        "Source cache evidence",
        source_cache_evidence_summary(summary)
      ),
      blocker_field_dto(
        "source-cache-evidence-targets",
        "Ev targets",
        "Source cache evidence targets",
        no_refresh_blocker_value(summary, :source_cache_evidence_target_ids)
      ),
      blocker_field_dto(
        "source-cache-evidence-requests",
        "Ev requests",
        "Source cache evidence requests",
        no_refresh_blocker_value(summary, :source_cache_evidence_request_ids)
      ),
      blocker_field_dto(
        "source-execution",
        "Src exec",
        "Source execution",
        no_refresh_blocker_value(summary, :source_execution_status_summary)
      ),
      blocker_field_dto(
        "source-execution-actions",
        "Src actions",
        "Source execution actions",
        no_refresh_blocker_value(summary, :source_execution_runtime_actions)
      ),
      blocker_field_dto(
        "source-execution-degraded",
        "Src degraded",
        "Source execution degraded",
        no_refresh_blocker_value(summary, :source_execution_degraded_identities)
      ),
      blocker_field_dto(
        "source-execution-degraded-actions",
        "Src d-actions",
        "Source execution degraded actions",
        no_refresh_blocker_value(summary, :source_execution_degraded_actions)
      ),
      blocker_field_dto(
        "source-dependency-degraded",
        "Src deps",
        "Source dependency degraded",
        no_refresh_blocker_value(summary, :source_dependency_degraded_count)
      ),
      blocker_field_dto(
        "source-dependency-evidence",
        "Src dep ev",
        "Source dependency evidence",
        no_refresh_blocker_value(summary, :source_dependency_evidence)
      )
    ]
  end

  defp field_dto(key, label, attribute, value) do
    %{
      key: key,
      label: label,
      label_class: "text-base-content/60",
      value: value,
      value_class: "font-mono text-base-content break-all",
      attributes: %{attribute => label}
    }
  end

  defp blocker_field_dto(key, label, attribute_value, value) do
    field_dto(key, label, "data-no-refresh-blocker-field", value)
    |> put_in([:attributes, "data-no-refresh-blocker-field"], attribute_value)
  end

  defp admin_action_dto(nil), do: nil

  defp admin_action_dto(href) do
    %{
      href: href,
      class: "btn btn-ghost btn-xs mt-2",
      attributes: %{
        "data-no-refresh-admin-decision-link-action" => "",
        "data-phx-link" => "redirect",
        "data-phx-link-state" => "push"
      },
      icon: %{class: "hero-arrow-top-right-on-square h-3.5 w-3.5", attributes: %{}},
      label: "Runtime decision"
    }
  end

  defp no_refresh_blocker_value(summary, key) when is_map(summary) and is_atom(key) do
    summary
    |> Map.get(:blocker, %{})
    |> case do
      blocker when is_map(blocker) -> blocker |> Map.get(key, "-") |> no_refresh_blocker_display()
      _other -> "-"
    end
  end

  defp no_refresh_blocker_display(value) when value in [nil, ""], do: "-"
  defp no_refresh_blocker_display(value), do: rendered_string(value)

  defp source_cache_evidence_summary(summary) do
    [
      {"total", no_refresh_blocker_value(summary, :source_cache_evidence_total)},
      {"resolved", no_refresh_blocker_value(summary, :source_cache_evidence_resolved)},
      {"context", no_refresh_blocker_value(summary, :source_cache_evidence_context_only)},
      {"missing", no_refresh_blocker_value(summary, :source_cache_evidence_missing)}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, "", "-"] end)
    |> case do
      [] -> "-"
      parts -> Enum.map_join(parts, " ", fn {label, value} -> "#{label}:#{value}" end)
    end
  end

  defp no_refresh_blocker_identity(summary) do
    [
      no_refresh_blocker_value(summary, :logical_source),
      no_refresh_blocker_value(summary, :realm),
      no_refresh_blocker_value(summary, :data_source_id),
      no_refresh_blocker_value(summary, :source_binding_id)
    ]
    |> Enum.reject(&(&1 == "-"))
    |> case do
      [] -> "-"
      parts -> Enum.join(parts, ":")
    end
  end

  defp admin_decision_link(summary) do
    RuntimeAdminDecisionLink.from_no_refresh_summary(summary)
  end

  defp rendered_string(nil), do: ""
  defp rendered_string(value) when is_binary(value), do: value
  defp rendered_string(value), do: to_string(value)
end
