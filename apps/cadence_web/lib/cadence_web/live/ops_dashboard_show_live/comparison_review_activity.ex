defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivity do
  @moduledoc false

  use CadenceWeb, :html

  attr :row, :map, required: true

  def request_details(assigns) do
    assigns =
      assigns
      |> assign(:presentation, request_presentation(assigns.row))
      |> assign(:component_id, component_id("request", assigns.row))

    ~H"""
    <.vue
      :if={@presentation}
      id={@component_id}
      v-component="ComparisonReviewActivityDetails"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def request_presentation(%{render?: true} = row) do
    %{
      kind: "request",
      root: %{
        class: "mt-2 border-t border-base-300/60 pt-2 text-xs",
        attrs: %{
          "data-dashboard-comparison-review-request" => dom_attr_value(row.event_id),
          "data-dashboard-comparison-review-status" => dom_attr_value(row.status),
          "data-dashboard-comparison-review-resolution-event" =>
            dom_attr_value(row.resolution_event_id),
          "data-dashboard-comparison-review-result-event-id" =>
            dom_attr_value(row.result_event_id),
          "data-dashboard-comparison-review-target-event-id" =>
            dom_attr_value(row.target_event_id),
          "data-dashboard-comparison-review-schema" => dom_attr_value(row.schema),
          "data-dashboard-comparison-review-kind" => dom_attr_value(row.kind),
          "data-dashboard-comparison-review-open-count" => dom_attr_value(row.open_count_text),
          "data-dashboard-comparison-review-placements" => dom_attr_value(row.placements_attr),
          "data-dashboard-comparison-review-bulk-decision-skipped-count" =>
            dom_attr_value(row.bulk_decision_skipped_count_text),
          "data-dashboard-comparison-review-bulk-decision-skipped-placements" =>
            dom_attr_value(row.bulk_decision_skipped_placement_ids_attr),
          "data-dashboard-comparison-review-bulk-decision-skipped-reasons" =>
            dom_attr_value(row.bulk_decision_skipped_reasons_attr)
        }
      },
      details: %{
        class: "grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1",
        rows: request_detail_rows(row)
      },
      actions: request_actions_presentation(row),
      findings: findings_presentation(row.findings)
    }
    |> normalize_attribute_maps()
  end

  def request_presentation(_row), do: nil

  attr :row, :map, required: true

  def resolution_details(assigns) do
    assigns =
      assigns
      |> assign(:presentation, resolution_presentation(assigns.row))
      |> assign(:component_id, component_id("resolution", assigns.row))

    ~H"""
    <.vue
      :if={@presentation}
      id={@component_id}
      v-component="ComparisonReviewActivityDetails"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def resolution_presentation(%{render?: true} = row) do
    %{
      kind: "resolution",
      root: %{
        class: "mt-2 border-t border-base-300/60 pt-2 text-xs",
        attrs: %{
          "data-dashboard-comparison-review-resolution" => dom_attr_value(row.event_id),
          "data-dashboard-comparison-review-resolution-result-event-id" =>
            dom_attr_value(row.result_event_id),
          "data-dashboard-comparison-review-resolution-target-event-id" =>
            dom_attr_value(row.target_event_id),
          "data-dashboard-comparison-review-resolution-source" =>
            dom_attr_value(row.source_request_event_id),
          "data-dashboard-comparison-review-resolution-disposition" =>
            dom_attr_value(row.disposition),
          "data-dashboard-comparison-review-resolution-selected-placement" =>
            dom_attr_value(row.selected_placement_id),
          "data-dashboard-comparison-review-resolution-affected-placements" =>
            dom_attr_value(row.affected_placements_attr),
          "data-dashboard-comparison-review-resolution-workflow-kind" =>
            dom_attr_value(row.workflow_intent_kind),
          "data-dashboard-comparison-review-resolution-workflow-action" =>
            dom_attr_value(row.workflow_intent_action),
          "data-dashboard-comparison-review-resolution-workflow-selection-count" =>
            dom_attr_value(row.workflow_selection_count_text),
          "data-dashboard-comparison-review-resolution-source-open-count" =>
            dom_attr_value(row.source_open_count_text),
          "data-dashboard-comparison-review-resolution-source-open-placements" =>
            dom_attr_value(row.source_open_placements_attr),
          "data-dashboard-comparison-review-resolution-source-scope-kind" =>
            dom_attr_value(row.source_scope_kind),
          "data-dashboard-comparison-review-resolution-source-scope-ids" =>
            dom_attr_value(row.source_scope_ids_attr),
          "data-dashboard-comparison-review-resolution-source-contact-ids" =>
            dom_attr_value(row.source_contact_ids_attr),
          "data-dashboard-comparison-review-resolution-source-resource-ids" =>
            dom_attr_value(row.source_resource_ids_attr),
          "data-dashboard-comparison-review-resolution-source-transport-ids" =>
            dom_attr_value(row.source_transport_ids_attr),
          "data-dashboard-comparison-review-resolution-source-endpoint-ids" =>
            dom_attr_value(row.source_endpoint_ids_attr),
          "data-dashboard-comparison-review-resolution-source-ground-station-ids" =>
            dom_attr_value(row.source_ground_station_ids_attr),
          "data-dashboard-comparison-review-resolution-source-scope-link-ids" =>
            dom_attr_value(row.source_scope_link_ids_attr),
          "data-dashboard-comparison-review-resolution-source-actionable-count" =>
            dom_attr_value(row.source_bulk_decision_actionable_count_text),
          "data-dashboard-comparison-review-resolution-source-actionable-placements" =>
            dom_attr_value(row.source_bulk_decision_actionable_placements_attr),
          "data-dashboard-comparison-review-resolution-source-skipped-count" =>
            dom_attr_value(row.source_bulk_decision_skipped_count_text),
          "data-dashboard-comparison-review-resolution-source-skipped-placements" =>
            dom_attr_value(row.source_bulk_decision_skipped_placements_attr),
          "data-dashboard-comparison-review-resolution-source-skipped-reasons" =>
            dom_attr_value(row.source_bulk_decision_skipped_reasons_attr)
        }
      },
      details: %{
        class: "grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1",
        rows: resolution_detail_rows(row)
      }
    }
    |> normalize_attribute_maps()
  end

  def resolution_presentation(_row), do: nil

  defp request_detail_rows(row) do
    [
      detail_row("request", "Request", "Request", row.kind, "font-mono text-base-content/70"),
      detail_row(
        "open",
        "Open",
        "Open findings",
        row.open_count_text,
        "font-mono text-base-content/70"
      ),
      %{
        key: "placements",
        kind: "placement_links",
        label: "Placements",
        label_class: "hud-label",
        value: "",
        value_class: "break-all font-mono text-base-content/70",
        value_attrs: %{"data-activity-field" => "Open placements"},
        links_class: "flex flex-wrap gap-1",
        links: Enum.map(row.placement_links, &placement_link_presentation/1),
        empty_text: "-"
      }
    ]
  end

  defp request_actions_presentation(%{resolved?: true} = row) do
    %{
      class: "mt-2 flex items-center justify-between gap-2",
      resolved_badge: %{
        class: "badge badge-success badge-outline badge-xs",
        text: "Resolved",
        attrs: %{"data-dashboard-comparison-review-resolved" => dom_attr_value(row.event_id)}
      },
      workflow_button: nil,
      skipped_badge: nil,
      unavailable_badge: nil,
      bulk_form: nil,
      resolve_form: nil
    }
  end

  defp request_actions_presentation(row) do
    %{
      class: "mt-2 flex items-center justify-between gap-2",
      resolved_badge: nil,
      workflow_button: workflow_button_presentation(row),
      skipped_badge: skipped_badge_presentation(row),
      unavailable_badge: unavailable_badge_presentation(row),
      bulk_form: bulk_form_presentation(row),
      resolve_form: resolve_form_presentation(row)
    }
  end

  defp workflow_button_presentation(%{workflow_request_available?: false}), do: nil

  defp workflow_button_presentation(row) do
    %{
      id: "dashboard-comparison-review-workflow-request-#{row.event_id}",
      type: "button",
      class: "btn btn-ghost btn-xs gap-1",
      text: "Prepare workflow",
      icon: icon_presentation("hero-document-plus"),
      attrs: %{
        "phx-click" => "open_comparison_review_workflow_request",
        "phx-value-request-event-id" => dom_attr_value(row.event_id),
        "data-dashboard-comparison-review-workflow-request" => dom_attr_value(row.event_id),
        "data-dashboard-comparison-review-workflow-point-count" =>
          dom_attr_value(row.workflow_request_point_count_text),
        "data-dashboard-comparison-review-workflow-point-ids" =>
          dom_attr_value(row.workflow_request_point_ids_attr)
      }
    }
  end

  defp skipped_badge_presentation(%{bulk_decision_skipped_label: nil}), do: nil

  defp skipped_badge_presentation(row) do
    %{
      class: "badge badge-neutral badge-outline badge-xs gap-1",
      text: dom_text(row.bulk_decision_skipped_label),
      icon: icon_presentation("hero-information-circle"),
      attrs: %{
        "data-dashboard-comparison-review-bulk-decision-skipped" => dom_attr_value(row.event_id),
        "data-dashboard-comparison-review-bulk-decision-skipped-count" =>
          dom_attr_value(row.bulk_decision_skipped_count_text),
        "data-dashboard-comparison-review-bulk-decision-skipped-placements" =>
          dom_attr_value(row.bulk_decision_skipped_placement_ids_attr),
        "data-dashboard-comparison-review-bulk-decision-skipped-reasons" =>
          dom_attr_value(row.bulk_decision_skipped_reasons_attr)
      }
    }
  end

  defp unavailable_badge_presentation(%{bulk_decision_unavailable?: false}), do: nil

  defp unavailable_badge_presentation(row) do
    %{
      class: "badge badge-warning badge-outline badge-xs gap-1",
      text: dom_text(row.bulk_decision_unavailable_label),
      icon: icon_presentation("hero-exclamation-triangle"),
      attrs: %{
        "data-dashboard-comparison-review-bulk-decision-unavailable" =>
          dom_attr_value(row.event_id),
        "data-dashboard-comparison-review-bulk-decision-unavailable-reason" =>
          dom_attr_value(row.bulk_decision_unavailable_reason),
        "data-dashboard-comparison-review-bulk-decision-unavailable-count" =>
          dom_attr_value(row.bulk_decision_count_text),
        "data-dashboard-comparison-review-bulk-decision-unavailable-placements" =>
          dom_attr_value(row.bulk_decision_placement_ids_attr)
      }
    }
  end

  defp bulk_form_presentation(%{bulk_decision_available?: false}), do: nil

  defp bulk_form_presentation(row) do
    %{
      id: "dashboard-comparison-review-bulk-decision-form-#{row.event_id}",
      class: "flex items-center gap-1",
      attrs: %{
        "phx-submit" => "apply_comparison_review_bulk_decision",
        "data-dashboard-comparison-review-bulk-decision-form" => dom_attr_value(row.event_id),
        "data-dashboard-comparison-review-bulk-decision-count" =>
          dom_attr_value(row.bulk_decision_count_text),
        "data-dashboard-comparison-review-bulk-decision-placements" =>
          dom_attr_value(row.bulk_decision_placement_ids_attr)
      },
      hidden_fields: [
        hidden_input(
          "bulk-source-request-event-id",
          "review[source_request_event_id]",
          row.event_id
        ),
        hidden_input("bulk-decision", "review[decision]", "mark_conflict"),
        hidden_input("bulk-confirmed", "review[confirmed]", "confirmed"),
        hidden_input(
          "bulk-decision-reason",
          "review[decision_reason]",
          "dashboard_comparison_review_mark_conflict"
        )
      ],
      text_input: nil,
      button: %{
        id: "dashboard-comparison-review-bulk-decision-#{row.event_id}",
        type: "submit",
        class: "btn btn-ghost btn-xs gap-1",
        text: "Mark conflicts",
        icon: icon_presentation("hero-shield-exclamation"),
        attrs: %{
          "data-dashboard-comparison-review-bulk-decision" => dom_attr_value(row.event_id),
          "data-dashboard-comparison-review-bulk-decision-kind" => "mark_conflict"
        }
      }
    }
  end

  defp resolve_form_presentation(row) do
    %{
      id: "dashboard-comparison-review-resolve-form-#{row.event_id}",
      class: "ml-auto flex items-center gap-1",
      attrs: %{
        "phx-submit" => "resolve_comparison_review",
        "data-dashboard-comparison-review-resolve-form" => dom_attr_value(row.event_id)
      },
      hidden_fields: [
        hidden_input(
          "resolve-source-request-event-id",
          "review[source_request_event_id]",
          row.event_id
        ),
        hidden_input("resolve-disposition", "review[disposition]", "review_completed"),
        hidden_input(
          "resolve-selected-placement-id",
          "review[selected_placement_id]",
          row.selected_placement_id
        ),
        hidden_input(
          "resolve-affected-placement-ids",
          "review[affected_placement_ids]",
          row.placements_attr
        )
      ],
      text_input: %{
        wrapper_class: "fieldset",
        attrs: %{
          "id" => "dashboard-comparison-review-resolution-reason-#{row.event_id}",
          "name" => "review[resolution_reason]",
          "type" => "text",
          "value" => "",
          "placeholder" => "Resolution note",
          "maxlength" => "240",
          "class" => "w-full input input-xs w-40",
          "data-dashboard-comparison-review-resolution-reason" => dom_attr_value(row.event_id)
        }
      },
      button: %{
        id: "dashboard-comparison-review-resolve-#{row.event_id}",
        type: "submit",
        class: "btn btn-ghost btn-xs gap-1",
        text: "Resolve",
        icon: icon_presentation("hero-check-circle"),
        attrs: %{"data-dashboard-comparison-review-resolve" => dom_attr_value(row.event_id)}
      }
    }
  end

  defp findings_presentation([]), do: nil

  defp findings_presentation(findings) do
    %{
      class: "mt-2 space-y-1",
      attrs: %{"data-dashboard-comparison-review-findings" => Integer.to_string(length(findings))},
      items: Enum.map(findings, &finding_presentation/1)
    }
  end

  defp finding_presentation(finding) do
    %{
      key: dom_text(finding.placement_id),
      class: "grid grid-cols-[1fr_auto] gap-2 rounded bg-base-200/60 px-2 py-1",
      attrs: %{
        "data-dashboard-comparison-review-finding" => dom_attr_value(finding.placement_id),
        "data-dashboard-comparison-review-finding-state" => dom_attr_value(finding.state),
        "data-dashboard-comparison-review-finding-status" =>
          dom_attr_value(finding.decision_status),
        "data-dashboard-comparison-review-finding-observation-identity" =>
          dom_attr_value(finding.observation_identity_id),
        "data-dashboard-comparison-review-finding-scope-kind" =>
          dom_attr_value(finding.scope_kind),
        "data-dashboard-comparison-review-finding-scope-id" => dom_attr_value(finding.scope_id),
        "data-dashboard-comparison-review-finding-scope-ids" => dom_attr_value(finding.scope_ids),
        "data-dashboard-comparison-review-finding-resource-id" =>
          dom_attr_value(finding.resource_id),
        "data-dashboard-comparison-review-finding-spacecraft-id" =>
          dom_attr_value(finding.spacecraft_id),
        "data-dashboard-comparison-review-finding-contact-id" =>
          dom_attr_value(finding.contact_id),
        "data-dashboard-comparison-review-finding-contact-ids" =>
          dom_attr_value(finding.contact_ids),
        "data-dashboard-comparison-review-finding-transport-id" =>
          dom_attr_value(finding.transport_id),
        "data-dashboard-comparison-review-finding-source-endpoint-id" =>
          dom_attr_value(finding.source_endpoint_id),
        "data-dashboard-comparison-review-finding-ground-station-id" =>
          dom_attr_value(finding.ground_station_id),
        "data-dashboard-comparison-review-finding-scope-link-id" =>
          dom_attr_value(finding.scope_link_id),
        "data-dashboard-comparison-review-finding-bulk-decision" =>
          dom_attr_value(finding.bulk_decision_status),
        "data-dashboard-comparison-review-finding-bulk-decision-reason" =>
          dom_attr_value(finding.bulk_decision_reason),
        "data-dashboard-comparison-review-finding-bulk-decision-label" =>
          dom_attr_value(finding.bulk_decision_label)
      },
      placement_link: %{
        href: dom_text(finding.placement_href),
        class: "link link-hover min-w-0 truncate",
        text: dom_text(finding.title),
        attrs: %{
          "phx-click" => "select_review_placement",
          "phx-value-placement-id" => dom_attr_value(finding.placement_id),
          "data-dashboard-comparison-review-finding-placement-link" =>
            dom_attr_value(finding.placement_id),
          "data-dashboard-review-placement-selected" =>
            dom_attr_value(finding.placement_selected_text)
        }
      },
      status: %{
        class: "font-mono text-base-content/60",
        text: dom_text(finding.decision_status)
      },
      bulk_decision_badge: %{
        class: "badge badge-outline badge-xs",
        text: dom_text(finding.bulk_decision_label),
        attrs: %{
          "data-dashboard-comparison-review-finding-bulk-decision-badge" =>
            dom_attr_value(finding.placement_id)
        }
      },
      status_class: "flex flex-wrap items-center justify-end gap-1"
    }
  end

  defp resolution_detail_rows(row) do
    [
      detail_row(
        "request",
        "Request",
        "Resolved request",
        row.source_request_event_id,
        "font-mono text-base-content/70"
      ),
      detail_row(
        "result",
        "Result",
        "Resolution disposition",
        row.disposition,
        "font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.resolution_reason != "-",
        "reason",
        "Reason",
        "Resolution reason",
        row.resolution_reason,
        "text-base-content/70"
      ),
      optional_detail_row(
        row.selected_placement_id != "-",
        "placement",
        "Placement",
        "Resolution placement",
        row.selected_placement_id,
        "font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.affected_placements_text != "-",
        "affected",
        "Affected",
        "Resolution affected placements",
        row.affected_placements_text,
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.source_scope_kind != "-",
        "scope",
        "Scope",
        "Resolution source scope",
        row.source_scope_kind,
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.source_scope_ids_attr != "",
        "scope-ids",
        "Scope IDs",
        "Resolution source scope IDs",
        row.source_scope_ids_attr,
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.source_contact_ids_attr != "",
        "contacts",
        "Contacts",
        "Resolution source contacts",
        row.source_contact_ids_attr,
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.source_resource_ids_attr != "",
        "resources",
        "Resources",
        "Resolution source resources",
        row.source_resource_ids_attr,
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.source_transport_ids_attr != "",
        "transports",
        "Transports",
        "Resolution source transports",
        row.source_transport_ids_attr,
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.source_endpoint_ids_attr != "",
        "source-endpoints",
        "Source endpoints",
        "Resolution source endpoints",
        row.source_endpoint_ids_attr,
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.source_ground_station_ids_attr != "",
        "ground-stations",
        "Ground stations",
        "Resolution source ground stations",
        row.source_ground_station_ids_attr,
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.source_scope_link_ids_attr != "",
        "scope-links",
        "Scope links",
        "Resolution source scope links",
        row.source_scope_link_ids_attr,
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.workflow_intent_kind != "-",
        "workflow",
        "Workflow",
        "Resolution workflow",
        "#{row.workflow_intent_kind} / #{row.workflow_selection_count_text}",
        "break-all font-mono text-base-content/70"
      ),
      optional_detail_row(
        row.source_bulk_decision_summary_text != "-",
        "bulk-action",
        "Bulk action",
        "Resolution bulk decision source",
        row.source_bulk_decision_summary_text,
        "break-all font-mono text-base-content/70"
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp detail_row(key, label, field, value, value_class) do
    %{
      key: key,
      kind: "text",
      label: label,
      label_class: "hud-label",
      value: dom_text(value),
      value_class: value_class,
      value_attrs: %{"data-activity-field" => field},
      links_class: "",
      links: [],
      empty_text: ""
    }
  end

  defp optional_detail_row(true, key, label, field, value, value_class),
    do: detail_row(key, label, field, value, value_class)

  defp optional_detail_row(false, _key, _label, _field, _value, _value_class), do: nil

  defp placement_link_presentation(placement) do
    %{
      key: dom_text(placement.placement_id),
      href: dom_text(placement.href),
      class: "link link-hover",
      text: dom_text(placement.placement_id),
      attrs: %{
        "phx-click" => "select_review_placement",
        "phx-value-placement-id" => dom_attr_value(placement.placement_id),
        "data-dashboard-comparison-review-placement-link" =>
          dom_attr_value(placement.placement_id),
        "data-dashboard-review-placement-selected" => dom_attr_value(placement.selected_text)
      }
    }
  end

  defp hidden_input(key, name, value) do
    %{
      key: key,
      attrs: %{
        "type" => "hidden",
        "name" => name,
        "value" => dom_attr_value(value)
      }
    }
  end

  defp icon_presentation(name), do: %{name: name, class: "h-3.5 w-3.5"}

  def component_id(kind, %{render?: true, event_id: event_id})
      when kind in ["request", "resolution"] do
    "dashboard-comparison-review-#{kind}-#{event_id}-component"
  end

  def component_id(_kind, _row), do: nil

  defp normalize_attribute_maps(%{} = presentation) do
    Map.new(presentation, fn
      {:attrs, attributes} when is_map(attributes) ->
        {:attrs, raw_attributes(attributes)}

      {key, value} ->
        {key, normalize_attribute_maps(value)}
    end)
  end

  defp normalize_attribute_maps(values) when is_list(values),
    do: Enum.map(values, &normalize_attribute_maps/1)

  defp normalize_attribute_maps(value), do: value

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), dom_text(value))
    end)
  end

  defp dom_attr_value(nil), do: nil
  defp dom_attr_value(value), do: dom_text(value)

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value), do: to_string(value)
end
