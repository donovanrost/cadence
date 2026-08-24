defmodule CadenceWeb.OpsDashboardShowLive.RuntimeCacheSummaryComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.EvidenceAttrs

  attr(:summary, :map, required: true)

  def cache_summary(%{summary: %{visible?: true} = summary} = assigns) do
    assigns = assign(assigns, :presentation, cache_summary_presentation(summary))

    ~H"""
    <.vue
      id="dashboard-cache-summary-component"
      v-component="RuntimeCacheSummary"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def cache_summary(assigns), do: ~H""

  def cache_summary_presentation(summary) do
    %{
      section: %{
        id: "dashboard-cache-summary",
        class: "border border-base-300/70 bg-base-100/40 px-3 py-2 text-sm",
        attributes:
          raw_attributes(%{
            "data-diagnostics-section" => "Cache state",
            "data-cache-classification" => summary.classification,
            "data-cache-plan" => summary.plan,
            "data-cache-source" => summary.source,
            "data-cache-frame" => summary.frame
          })
      },
      heading: %{class: "hud-label", text: "Cache state"},
      headline: %{class: "mt-1 text-base-content", text: rendered_string(summary.headline)},
      fields: %{
        class: "mt-2 grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
        rows: [
          field_dto("plan", "Plan", "Plan", summary.plan),
          field_dto("source", "Source", "Source", summary.source),
          field_dto("frame", "Frame", "Frame", summary.frame)
        ]
      },
      evidence: evidence_dto(summary)
    }
  end

  defp evidence_dto(%{drilldowns: []}), do: %{visible: false}

  defp evidence_dto(summary) do
    state_summary = summary.evidence_state_summary

    %{
      visible: true,
      section: %{
        id: "dashboard-cache-evidence",
        class: "mt-3 border-t border-base-300/70 pt-2",
        attributes:
          raw_attributes(%{
            "data-cache-evidence-count" => length(summary.drilldowns),
            "data-cache-evidence-resolved" => state_summary.resolved,
            "data-cache-evidence-context-only" => state_summary.context_only,
            "data-cache-evidence-missing" => state_summary.missing
          })
      },
      heading: %{class: "hud-label text-[0.65rem]", text: "Cache evidence"},
      states: %{
        class: "mt-2 grid grid-cols-3 gap-2 text-xs",
        rows: [
          state_field_dto("resolved", "Resolved", "Resolved", state_summary.resolved),
          state_field_dto("context-only", "Context", "Context only", state_summary.context_only),
          state_field_dto("missing", "Missing", "Missing", state_summary.missing)
        ]
      },
      list: %{
        class: "mt-2 space-y-2",
        items:
          summary.drilldowns
          |> Enum.with_index()
          |> Enum.map(fn {item, index} -> evidence_item_dto(item, index) end)
      }
    }
  end

  defp evidence_item_dto(item, index) do
    %{
      key: index,
      attributes: evidence_item_attributes(item),
      button: %{
        type: "button",
        class:
          "grid w-full grid-cols-[3.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 border border-base-300/60 bg-base-200/20 px-2 py-2 text-left text-xs hover:bg-base-200/50",
        attributes: evidence_button_attributes(item)
      },
      fields: [
        evidence_field_dto("layer", "Layer", "Layer", item.layer, true),
        evidence_field_dto("status", "Status", "Status", item.status, true),
        evidence_field_dto("request", "Request", "Request", item.request_id, true),
        evidence_field_dto(
          "placement",
          "Placement",
          "Placement",
          item.placement_id,
          item.placement_id != "-"
        ),
        evidence_field_dto("source", "Source", "Source", item.logical_source, true),
        evidence_field_dto("binding", "Binding", "Binding", item.source_binding_id, true),
        evidence_field_dto("data-source", "Data", "Data source", item.data_source_id, true),
        evidence_field_dto("reasons", "Why", "Reasons", item.reasons, true),
        evidence_field_dto(
          "incident",
          "Incident",
          "Incident",
          item.incident_status_text,
          item.incident_status_text != "-"
        ),
        evidence_field_dto(
          "action",
          "Action",
          "Action",
          item.incident_operator_action,
          item.incident_operator_action != "-"
        ),
        evidence_field_dto(
          "evidence",
          "Evidence",
          "Evidence",
          rendered_string(item.incident_evidence_kind_text) <>
            ":" <> rendered_string(item.incident_evidence_target_id),
          item.incident_evidence_target_id != "-"
        )
      ]
    }
  end

  defp evidence_item_attributes(item) do
    raw_attributes(%{
      "data-cache-evidence-id" => item.evidence_id,
      "data-cache-evidence-layer" => item.layer,
      "data-cache-evidence-status" => item.status,
      "data-cache-evidence-request-id" => item.request_id,
      "data-cache-evidence-placement-id" => item.placement_id,
      "data-cache-evidence-source" => item.logical_source,
      "data-cache-evidence-source-binding-id" => item.source_binding_id,
      "data-cache-evidence-data-source-id" => item.data_source_id,
      "data-cache-evidence-reasons" => item.reasons,
      "data-cache-evidence-state" => item.evidence_state,
      "data-cache-evidence-incident-status" => item.incident_status_text,
      "data-cache-evidence-incident-severity" => item.incident_severity,
      "data-cache-evidence-incident-action" => item.incident_operator_action,
      "data-cache-evidence-incident-runtime-action" => item.incident_runtime_action,
      "data-cache-evidence-incident-target" => item.incident_evidence_target,
      "data-cache-evidence-incident-target-id" => item.incident_evidence_target_id,
      "data-cache-evidence-incident-kind" => item.incident_evidence_kind
    })
  end

  defp evidence_button_attributes(item) do
    %{
      "phx-click" => "open_evidence",
      "data-cache-evidence-open" => item.evidence_id
    }
    |> Map.merge(EvidenceAttrs.cache(item))
    |> raw_attributes()
  end

  defp field_dto(key, label, data_label, value) do
    %{
      key: key,
      label: label,
      label_class: "text-base-content/60",
      value: rendered_string(value),
      value_class: "font-mono text-base-content break-all",
      attributes: %{"data-cache-field" => data_label}
    }
  end

  defp state_field_dto(key, label, data_label, value) do
    %{
      key: key,
      label: label,
      label_class: "text-base-content/60",
      value: rendered_string(value),
      value_class: "font-mono text-base-content",
      attributes: %{"data-cache-evidence-state-field" => data_label}
    }
  end

  defp evidence_field_dto(key, label, data_label, value, visible?) do
    %{
      key: key,
      visible: visible?,
      label: label,
      label_class: "text-base-content/60",
      value: rendered_string(value),
      value_class: "font-mono text-base-content break-all",
      attributes: %{"data-cache-evidence-field" => data_label}
    }
  end

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), rendered_string(value))
    end)
  end

  defp rendered_string(nil), do: ""
  defp rendered_string(value) when is_binary(value), do: value
  defp rendered_string(value), do: to_string(value)
end
