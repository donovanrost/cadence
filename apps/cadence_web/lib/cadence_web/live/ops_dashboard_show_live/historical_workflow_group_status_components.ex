defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryFormPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecovery
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementStatusComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentation

  attr(:workflow_context, :map, required: true)
  attr(:workflow_controls, :map, required: true)
  attr(:dashboard_current_path, :string, default: nil)

  def group_status(%{workflow_controls: %{group_summary: group_summary}} = assigns)
      when group_summary in [nil, false],
      do: ~H""

  def group_status(assigns) do
    assigns =
      assign(
        assigns,
        :presentation,
        presentation(
          assigns.workflow_context,
          assigns.workflow_controls,
          assigns.dashboard_current_path
        )
      )

    ~H"""
    <.vue
      id="dashboard-historical-workflow-group-status-component"
      v-component="HistoricalWorkflowGroupStatus"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(_workflow_context, %{group_summary: group_summary}, _dashboard_current_path)
      when group_summary in [nil, false],
      do: nil

  def presentation(workflow_context, workflow_controls, dashboard_current_path) do
    comparison_review_links =
      HistoricalWorkflowStatusNavigationPresentation.comparison_review_links(
        workflow_context,
        dashboard_current_path
      )

    failed_item_handoffs =
      HistoricalWorkflowStatusNavigationPresentation.group_failed_item_handoffs(
        workflow_context,
        dashboard_current_path
      )

    replacement_recovery =
      HistoricalWorkflowReplacementRecovery.build(
        workflow_context,
        workflow_controls
      )

    closure_readiness = replacement_recovery.closure_readiness

    group_recovery_forms =
      HistoricalWorkflowGroupRecoveryFormPresentation.build(
        workflow_context,
        replacement_recovery
      )

    group_recovery =
      HistoricalWorkflowGroupRecoveryPresentation.build(workflow_context)

    group_status_presentation(
      workflow_context,
      comparison_review_links,
      failed_item_handoffs,
      replacement_recovery,
      closure_readiness,
      group_recovery_forms,
      group_recovery
    )
  end

  defp group_status_presentation(
         workflow_context,
         comparison_review_links,
         failed_item_handoffs,
         replacement_recovery,
         closure_readiness,
         group_recovery_forms,
         group_recovery
       ) do
    %{
      root: root_presentation(workflow_context, group_recovery),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: text_presentation("hud-label", "Group Status"),
        state: text_presentation("font-mono", workflow_context.request_group_state)
      },
      job_progress: job_progress_presentation(workflow_context, group_recovery),
      execution_audit: execution_audit_presentation(workflow_context, group_recovery),
      review_origin: review_origin_presentation(workflow_context, comparison_review_links),
      details: group_details_presentation(workflow_context, group_recovery),
      recovery:
        recovery_presentation(
          workflow_context,
          comparison_review_links,
          failed_item_handoffs,
          replacement_recovery,
          closure_readiness,
          group_recovery_forms,
          group_recovery
        )
    }
  end

  defp root_presentation(workflow_context, group_recovery) do
    %{
      id: "dashboard-historical-workflow-group-summary",
      class: "rounded border border-primary/30 bg-primary/5 p-2 text-xs",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-id" => workflow_context.request_group_id,
          "data-historical-workflow-group-state" => workflow_context.request_group_state,
          "data-historical-workflow-group-terminal" => workflow_context.request_group_terminal,
          "data-historical-workflow-group-size" => workflow_context.request_group_size,
          "data-historical-workflow-group-progress" => workflow_context.request_group_progress,
          "data-historical-workflow-group-requested" => workflow_context.request_group_requested,
          "data-historical-workflow-group-approved" => workflow_context.request_group_approved,
          "data-historical-workflow-group-started" => workflow_context.request_group_started,
          "data-historical-workflow-group-completed" => workflow_context.request_group_completed,
          "data-historical-workflow-group-failed" => workflow_context.request_group_failed,
          "data-historical-workflow-group-resolved-failed" =>
            workflow_context.request_group_resolved_failed,
          "data-historical-workflow-group-retry-resolved" =>
            workflow_context.request_group_retry_resolved,
          "data-historical-workflow-group-correction-requested" =>
            workflow_context.request_group_correction_requested,
          "data-historical-workflow-group-correction-started" =>
            workflow_context.request_group_correction_started,
          "data-historical-workflow-group-correction-completed" =>
            workflow_context.request_group_correction_completed,
          "data-historical-workflow-group-correction-superseded" =>
            workflow_context.request_group_correction_superseded,
          "data-historical-workflow-group-request-eligible" =>
            workflow_context.request_group_request_eligible,
          "data-historical-workflow-group-approve-eligible" =>
            workflow_context.request_group_approve_eligible,
          "data-historical-workflow-group-reject-eligible" =>
            workflow_context.request_group_reject_eligible,
          "data-historical-workflow-group-start-eligible" =>
            workflow_context.request_group_start_eligible,
          "data-historical-workflow-group-complete-eligible" =>
            workflow_context.request_group_complete_eligible,
          "data-historical-workflow-group-fail-eligible" =>
            workflow_context.request_group_fail_eligible,
          "data-historical-workflow-group-retryable-failed" =>
            workflow_context.request_group_retryable_failed,
          "data-historical-workflow-group-nonretryable-failed" =>
            workflow_context.request_group_nonretryable_failed,
          "data-historical-workflow-group-comparison-review-request" =>
            workflow_context.comparison_review_request_event_id,
          "data-historical-workflow-group-comparison-review-kind" =>
            workflow_context.comparison_review_request_kind,
          "data-historical-workflow-group-comparison-review-open-count" =>
            workflow_context.comparison_review_open_count,
          "data-historical-workflow-group-comparison-review-placements" =>
            workflow_context.comparison_review_open_placement_ids,
          "data-historical-workflow-group-comparison-review-workflow-kind" =>
            Map.get(workflow_context, :comparison_review_workflow_kind),
          "data-historical-workflow-group-comparison-review-workflow-action" =>
            Map.get(workflow_context, :comparison_review_workflow_action),
          "data-historical-workflow-group-comparison-review-workflow-selection-kind" =>
            Map.get(workflow_context, :comparison_review_workflow_selection_kind),
          "data-historical-workflow-group-comparison-review-workflow-selection-count" =>
            Map.get(workflow_context, :comparison_review_workflow_selection_count),
          "data-historical-workflow-group-comparison-review-primary-data-view" =>
            Map.get(workflow_context, :comparison_review_primary_data_view),
          "data-historical-workflow-group-comparison-review-compare-data-view" =>
            Map.get(workflow_context, :comparison_review_compare_data_view),
          "data-historical-workflow-group-comparison-review-scope-kind" =>
            Map.get(workflow_context, :comparison_review_scope_kind),
          "data-historical-workflow-group-comparison-review-scope-ids" =>
            Map.get(workflow_context, :comparison_review_scope_ids),
          "data-historical-workflow-group-comparison-review-contact-ids" =>
            Map.get(workflow_context, :comparison_review_contact_ids),
          "data-historical-workflow-group-comparison-review-resource-ids" =>
            Map.get(workflow_context, :comparison_review_resource_ids),
          "data-historical-workflow-group-comparison-review-transport-ids" =>
            Map.get(workflow_context, :comparison_review_transport_ids),
          "data-historical-workflow-group-comparison-review-source-endpoint-ids" =>
            Map.get(workflow_context, :comparison_review_source_endpoint_ids),
          "data-historical-workflow-group-comparison-review-ground-station-ids" =>
            Map.get(workflow_context, :comparison_review_ground_station_ids),
          "data-historical-workflow-group-comparison-review-scope-link-ids" =>
            Map.get(workflow_context, :comparison_review_scope_link_ids),
          "data-historical-workflow-group-handoff-summary" => group_recovery.handoff_summary
        })
    }
  end

  defp job_progress_presentation(workflow_context, group_recovery) do
    progress = Map.get(workflow_context, :request_group_job_progress)

    %{
      visible: DataLinkInspectorPanelPresentation.present_text?(progress),
      id: "dashboard-historical-workflow-group-job-progress",
      class: "mt-2 space-y-1 rounded border border-base-300/60 bg-base-100/70 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-job-progress" => progress,
          "data-historical-workflow-group-job-progress-queued" =>
            job_progress_count(workflow_context, "queued"),
          "data-historical-workflow-group-job-progress-running" =>
            job_progress_count(workflow_context, "running"),
          "data-historical-workflow-group-job-progress-completed" =>
            job_progress_count(workflow_context, "completed"),
          "data-historical-workflow-group-job-progress-failed" =>
            job_progress_count(workflow_context, "failed"),
          "data-historical-workflow-group-job-progress-missing" =>
            job_progress_count(workflow_context, "missing"),
          "data-historical-workflow-group-job-items" =>
            Map.get(workflow_context, :request_group_job_items)
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: text_presentation("hud-label", "Job Progress"),
        progress: text_presentation("font-mono text-base-content/70", progress)
      },
      items: %{
        class: "space-y-1",
        entries:
          group_recovery.job_items
          |> Enum.with_index()
          |> Enum.map(fn {item, index} ->
            %{
              key: "historical-workflow-group-job-item-#{index}",
              class:
                "rounded border border-base-300/50 bg-base-200/40 px-2 py-1 font-mono text-base-content/75 break-all",
              text: dom_text(item),
              attrs:
                raw_attrs(%{
                  "data-historical-workflow-group-job-item" => item
                })
            }
          end)
      }
    }
  end

  defp execution_audit_presentation(workflow_context, group_recovery) do
    entries = group_recovery.execution_audit_entries
    count = Integer.to_string(length(entries))

    %{
      visible: entries != [],
      id: "dashboard-historical-workflow-group-execution-audit",
      class: "mt-2 space-y-2 rounded border border-base-300/60 bg-base-100/70 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-execution-audit-count" => count,
          "data-historical-workflow-group-execution-audit-summary" =>
            group_recovery.execution_audit_summary,
          "data-historical-workflow-group-execution-audit-request-group" =>
            Map.get(workflow_context, :request_group_id)
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: text_presentation("hud-label", "Execution Audit"),
        count: text_presentation("font-mono text-base-content/70", count)
      },
      items: %{
        class: "space-y-1",
        entries:
          entries
          |> Enum.with_index()
          |> Enum.map(fn {entry, index} ->
            %{
              key: "historical-workflow-group-execution-audit-#{index}",
              class: "rounded border border-base-300/50 bg-base-200/40 px-2 py-1",
              attrs:
                raw_attrs(%{
                  "data-historical-workflow-group-execution-step" => entry.key,
                  "data-historical-workflow-group-execution-count" => entry.count,
                  "data-historical-workflow-group-execution-detail" => entry.detail
                }),
              header: %{
                class: "flex items-center justify-between gap-2",
                label: text_presentation("font-mono text-base-content", entry.label),
                count: text_presentation("badge badge-xs badge-outline font-mono", entry.count)
              },
              detail: %{
                visible: DataLinkInspectorPanelPresentation.present_text?(entry.detail),
                class: "mt-1 font-mono text-base-content/65 break-all",
                text: dom_text(entry.detail)
              }
            }
          end)
      }
    }
  end

  defp review_origin_presentation(workflow_context, comparison_review_links) do
    placement_count = Integer.to_string(length(comparison_review_links.placement_links))

    %{
      visible: truthy?(comparison_review_links.review_href),
      id: "dashboard-historical-workflow-review-origin",
      class: "mt-2 space-y-2 rounded border border-info/40 bg-info/10 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-review-origin-request" =>
            workflow_context.comparison_review_request_event_id,
          "data-historical-workflow-review-origin-kind" =>
            workflow_context.comparison_review_request_kind,
          "data-historical-workflow-review-origin-open-count" =>
            workflow_context.comparison_review_open_count,
          "data-historical-workflow-review-origin-placements" =>
            workflow_context.comparison_review_open_placement_ids,
          "data-historical-workflow-review-origin-workflow-kind" =>
            Map.get(workflow_context, :comparison_review_workflow_kind),
          "data-historical-workflow-review-origin-workflow-action" =>
            Map.get(workflow_context, :comparison_review_workflow_action),
          "data-historical-workflow-review-origin-workflow-selection-kind" =>
            Map.get(workflow_context, :comparison_review_workflow_selection_kind),
          "data-historical-workflow-review-origin-workflow-selection-count" =>
            Map.get(workflow_context, :comparison_review_workflow_selection_count),
          "data-historical-workflow-review-origin-primary-data-view" =>
            Map.get(workflow_context, :comparison_review_primary_data_view),
          "data-historical-workflow-review-origin-compare-data-view" =>
            Map.get(workflow_context, :comparison_review_compare_data_view),
          "data-historical-workflow-review-origin-placement-count" => placement_count
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: text_presentation("hud-label", "Review Origin")
      },
      review_link:
        review_link_presentation(
          comparison_review_links.review_href,
          workflow_context.comparison_review_request_event_id,
          "data-historical-workflow-review-origin-link",
          "data-historical-workflow-review-origin-href"
        ),
      placements: %{
        visible: comparison_review_links.placement_links != [],
        class: "flex flex-wrap gap-1",
        attrs:
          raw_attrs(%{
            "data-historical-workflow-review-origin-placement-count" => placement_count
          }),
        links:
          comparison_review_links.placement_links
          |> Enum.with_index()
          |> Enum.map(fn {link, index} -> placement_link_presentation(link, index) end)
      }
    }
  end

  defp review_link_presentation(href, request_event_id, link_attr, href_attr) do
    %{
      href: href,
      class: "inline-flex items-center gap-1 font-mono text-primary hover:text-primary-focus",
      text: "Open review",
      icon: %{name: "hero-arrow-top-right-on-square", class: "h-3 w-3"},
      attrs:
        raw_attrs(%{
          link_attr => request_event_id,
          href_attr => href,
          "data-phx-link" => "patch",
          "data-phx-link-state" => "push"
        })
    }
  end

  defp placement_link_presentation(link, index) do
    %{
      key: "historical-workflow-review-placement-#{index}",
      href: link.href,
      class: "badge badge-xs badge-outline",
      text: dom_text(link.placement_id),
      attrs:
        raw_attrs(%{
          "data-historical-workflow-review-origin-placement" => link.placement_id,
          "data-historical-workflow-review-origin-placement-href" => link.href,
          "data-phx-link" => "patch",
          "data-phx-link-state" => "push"
        })
    }
  end

  defp group_details_presentation(workflow_context, group_recovery) do
    %{
      class: "mt-2 grid grid-cols-[5rem_minmax(0,1fr)] gap-x-2 gap-y-1",
      rows:
        [
          detail_row("group", "Group", workflow_context.request_group_id, "font-mono break-all"),
          detail_row("state", "State", workflow_context.request_group_state, "font-mono"),
          detail_row(
            "terminal",
            "Terminal",
            workflow_context.request_group_terminal,
            "font-mono"
          ),
          detail_row(
            "progress",
            "Progress",
            workflow_context.request_group_progress,
            "font-mono"
          ),
          detail_row("handoff", "Handoff", group_recovery.handoff_summary, "font-mono break-all"),
          optional_detail_row(
            "review",
            "Review",
            workflow_context.comparison_review_request_event_id,
            "font-mono break-all"
          ),
          optional_detail_row(
            "placements",
            "Placements",
            workflow_context.comparison_review_open_placement_ids,
            "font-mono break-all"
          ),
          detail_row("items", "Items", workflow_context.request_group_size, "font-mono"),
          detail_row(
            "requested",
            "Requested",
            workflow_context.request_group_requested,
            "font-mono"
          ),
          detail_row(
            "approved",
            "Approved",
            workflow_context.request_group_approved,
            "font-mono"
          ),
          detail_row("started", "Started", workflow_context.request_group_started, "font-mono"),
          detail_row(
            "completed",
            "Completed",
            workflow_context.request_group_completed,
            "font-mono"
          ),
          detail_row("failed", "Failed", workflow_context.request_group_failed, "font-mono"),
          detail_row(
            "resolved",
            "Resolved",
            workflow_context.request_group_resolved_failed,
            "font-mono"
          ),
          detail_row(
            "retried",
            "Retried",
            workflow_context.request_group_retry_resolved,
            "font-mono"
          ),
          detail_row(
            "correction-requested",
            "Correction requested",
            workflow_context.request_group_correction_requested,
            "font-mono"
          ),
          detail_row(
            "correction-started",
            "Correction started",
            workflow_context.request_group_correction_started,
            "font-mono"
          ),
          detail_row(
            "correction-completed",
            "Correction completed",
            workflow_context.request_group_correction_completed,
            "font-mono"
          ),
          detail_row(
            "correction-superseded",
            "Correction superseded",
            workflow_context.request_group_correction_superseded,
            "font-mono"
          ),
          detail_row(
            "eligible-approve",
            "Eligible approve",
            workflow_context.request_group_approve_eligible,
            "font-mono"
          ),
          detail_row(
            "eligible-start",
            "Eligible start",
            workflow_context.request_group_start_eligible,
            "font-mono"
          ),
          detail_row(
            "eligible-complete",
            "Eligible complete",
            workflow_context.request_group_complete_eligible,
            "font-mono"
          ),
          detail_row(
            "retryable",
            "Retryable",
            workflow_context.request_group_retryable_failed,
            "font-mono"
          ),
          detail_row(
            "correction",
            "Correction",
            workflow_context.request_group_nonretryable_failed,
            "font-mono"
          ),
          optional_detail_row(
            "failed-items",
            "Failed items",
            workflow_context.request_group_failed_items,
            "font-mono break-all"
          )
        ]
        |> Enum.reject(&is_nil/1)
    }
  end

  defp recovery_presentation(
         workflow_context,
         comparison_review_links,
         failed_item_handoffs,
         replacement_recovery,
         closure_readiness,
         group_recovery_forms,
         group_recovery
       ) do
    %{
      visible: truthy?(group_recovery.visible),
      id: "dashboard-historical-workflow-group-recovery",
      class: "mt-2 space-y-1 rounded border border-warning/40 bg-warning/10 p-2",
      attrs:
        recovery_attrs(
          workflow_context,
          failed_item_handoffs,
          replacement_recovery,
          group_recovery
        ),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: text_presentation("hud-label", "Recovery Handoff"),
        resolved:
          text_presentation(
            "font-mono text-base-content/70",
            dom_text(Map.get(workflow_context, :request_group_resolved_failed) || "0") <>
              " resolved"
          )
      },
      review_origin:
        recovery_review_origin_presentation(workflow_context, comparison_review_links),
      guidance: recovery_guidance_presentation(replacement_recovery, group_recovery),
      failed_item_handoffs: failed_item_handoffs_presentation(failed_item_handoffs),
      execution_plan:
        execution_plan_presentation(
          workflow_context,
          replacement_recovery,
          closure_readiness,
          group_recovery_forms,
          group_recovery
        ),
      details: recovery_details_presentation(workflow_context),
      item_groups: recovery_item_groups_presentation(workflow_context, group_recovery),
      guidance_note: %{
        class: "text-base-content/70",
        text:
          "Retryable failures can be requeued from this group. Non-retryable failures require a corrected workflow request from the failed item."
      }
    }
  end

  defp recovery_attrs(
         workflow_context,
         failed_item_handoffs,
         replacement_recovery,
         group_recovery
       ) do
    raw_attrs(%{
      "data-historical-workflow-group-recovery-id" =>
        Map.get(workflow_context, :request_group_id),
      "data-historical-workflow-group-recovery-failed" =>
        Map.get(workflow_context, :request_group_failed),
      "data-historical-workflow-group-recovery-retryable" =>
        Map.get(workflow_context, :request_group_retryable_failed),
      "data-historical-workflow-group-recovery-correction" =>
        Map.get(workflow_context, :request_group_nonretryable_failed),
      "data-historical-workflow-group-recovery-resolved" =>
        Map.get(workflow_context, :request_group_resolved_failed),
      "data-historical-workflow-group-recovery-retried" =>
        Map.get(workflow_context, :request_group_retry_resolved),
      "data-historical-workflow-group-recovery-correction-requested" =>
        Map.get(workflow_context, :request_group_correction_requested),
      "data-historical-workflow-group-recovery-retried-items" =>
        Map.get(workflow_context, :request_group_retried_items),
      "data-historical-workflow-group-recovery-corrected-items" =>
        Map.get(workflow_context, :request_group_corrected_items),
      "data-historical-workflow-group-recovery-correction-tasks" =>
        Map.get(workflow_context, :request_group_correction_tasks),
      "data-historical-workflow-group-recovery-failed-item-events" =>
        Map.get(workflow_context, :request_group_failed_item_events),
      "data-historical-workflow-group-recovery-failed-item-handoffs" =>
        Integer.to_string(length(failed_item_handoffs)),
      "data-historical-workflow-group-recovery-review-request" =>
        workflow_context.comparison_review_request_event_id,
      "data-historical-workflow-group-recovery-review-kind" =>
        workflow_context.comparison_review_request_kind,
      "data-historical-workflow-group-recovery-review-open-count" =>
        workflow_context.comparison_review_open_count,
      "data-historical-workflow-group-recovery-review-placements" =>
        workflow_context.comparison_review_open_placement_ids,
      "data-historical-workflow-group-recovery-review-workflow-kind" =>
        Map.get(workflow_context, :comparison_review_workflow_kind),
      "data-historical-workflow-group-recovery-review-workflow-action" =>
        Map.get(workflow_context, :comparison_review_workflow_action),
      "data-historical-workflow-group-recovery-review-workflow-selection-kind" =>
        Map.get(workflow_context, :comparison_review_workflow_selection_kind),
      "data-historical-workflow-group-recovery-review-workflow-selection-count" =>
        Map.get(workflow_context, :comparison_review_workflow_selection_count),
      "data-historical-workflow-group-recovery-review-primary-data-view" =>
        Map.get(workflow_context, :comparison_review_primary_data_view),
      "data-historical-workflow-group-recovery-review-compare-data-view" =>
        Map.get(workflow_context, :comparison_review_compare_data_view),
      "data-historical-workflow-group-recovery-next-action" => replacement_recovery.next_action,
      "data-historical-workflow-group-recovery-unresolved" => group_recovery.unresolved,
      "data-historical-workflow-group-recovery-correction-task-count" =>
        replacement_recovery.correction_task_count
    })
  end

  defp recovery_review_origin_presentation(workflow_context, comparison_review_links) do
    %{
      visible: truthy?(comparison_review_links.review_href),
      id: "dashboard-historical-workflow-group-recovery-review-origin",
      class:
        "flex items-center justify-between gap-2 rounded border border-info/30 bg-base-100/60 px-2 py-1",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-recovery-review-origin-request" =>
            workflow_context.comparison_review_request_event_id,
          "data-historical-workflow-group-recovery-review-origin-placement-count" =>
            Integer.to_string(length(comparison_review_links.placement_links)),
          "data-historical-workflow-group-recovery-review-workflow-kind" =>
            Map.get(workflow_context, :comparison_review_workflow_kind),
          "data-historical-workflow-group-recovery-review-workflow-action" =>
            Map.get(workflow_context, :comparison_review_workflow_action),
          "data-historical-workflow-group-recovery-review-workflow-selection-kind" =>
            Map.get(workflow_context, :comparison_review_workflow_selection_kind),
          "data-historical-workflow-group-recovery-review-workflow-selection-count" =>
            Map.get(workflow_context, :comparison_review_workflow_selection_count),
          "data-historical-workflow-group-recovery-review-primary-data-view" =>
            Map.get(workflow_context, :comparison_review_primary_data_view),
          "data-historical-workflow-group-recovery-review-compare-data-view" =>
            Map.get(workflow_context, :comparison_review_compare_data_view)
        }),
      label: text_presentation("hud-label", "Review Origin"),
      review_link:
        review_link_presentation(
          comparison_review_links.review_href,
          workflow_context.comparison_review_request_event_id,
          "data-historical-workflow-group-recovery-review-origin-link",
          "data-historical-workflow-group-recovery-review-origin-href"
        )
    }
  end

  defp recovery_guidance_presentation(replacement_recovery, group_recovery) do
    %{
      id: "dashboard-historical-workflow-group-recovery-guidance",
      class: "rounded border border-warning/30 bg-base-100/60 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-recovery-guidance-next-action" =>
            replacement_recovery.next_action,
          "data-historical-workflow-group-recovery-guidance-unresolved" =>
            group_recovery.unresolved,
          "data-historical-workflow-group-recovery-guidance-retry-eligible" =>
            replacement_recovery.retry_action.eligible,
          "data-historical-workflow-group-recovery-guidance-retry-reason" =>
            replacement_recovery.retry_action.reason,
          "data-historical-workflow-group-recovery-guidance-retry-preview" =>
            replacement_recovery.retry_action.preview,
          "data-historical-workflow-group-recovery-guidance-retry-explanation" =>
            replacement_recovery.retry_action.explanation,
          "data-historical-workflow-group-recovery-guidance-retry-state" =>
            replacement_recovery.retry_action.state,
          "data-historical-workflow-group-recovery-guidance-retry-available-when" =>
            replacement_recovery.retry_action.available_when,
          "data-historical-workflow-group-recovery-guidance-correction-task-count" =>
            replacement_recovery.correction_task_count
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: text_presentation("hud-label", "Recovery Guidance"),
        next_action:
          text_presentation("font-mono text-base-content/70", replacement_recovery.next_action)
      },
      guidance: text_presentation("mt-1 text-base-content/75", replacement_recovery.guidance),
      retry_state: %{
        visible:
          DataLinkInspectorPanelPresentation.present_text?(
            replacement_recovery.retry_action.state
          ),
        class: "mt-1 font-mono text-base-content/65",
        text: dom_text(replacement_recovery.retry_action.state)
      },
      available_when: %{
        visible:
          DataLinkInspectorPanelPresentation.present_text?(
            replacement_recovery.retry_action.available_when
          ),
        class: "mt-1 text-base-content/60",
        text: dom_text(replacement_recovery.retry_action.available_when)
      }
    }
  end

  defp failed_item_handoffs_presentation(failed_item_handoffs) do
    count = Integer.to_string(length(failed_item_handoffs))

    %{
      visible: failed_item_handoffs != [],
      id: "dashboard-historical-workflow-group-recovery-failed-item-handoffs",
      class: "rounded border border-warning/30 bg-base-100/70 p-2",
      attrs:
        raw_attrs(%{"data-historical-workflow-group-recovery-failed-item-handoff-count" => count}),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: text_presentation("hud-label", "Failed Item Handoffs"),
        count: text_presentation("font-mono text-base-content/70", count)
      },
      links: %{
        class: "mt-2 flex flex-wrap gap-2",
        entries:
          failed_item_handoffs
          |> Enum.with_index()
          |> Enum.map(fn {handoff, index} ->
            %{
              key: "historical-workflow-group-failed-item-handoff-#{index}",
              href: handoff.href,
              class: "btn btn-xs btn-warning btn-outline",
              text: dom_text(handoff.label),
              icon: %{name: "hero-arrow-top-right-on-square", class: "h-3 w-3"},
              attrs:
                raw_attrs(%{
                  "data-historical-workflow-group-recovery-failed-item" => handoff.event_id,
                  "data-historical-workflow-group-recovery-failed-item-label" => handoff.label,
                  "data-historical-workflow-group-recovery-failed-item-run" => handoff.run_id,
                  "data-historical-workflow-group-recovery-failed-item-recovery" =>
                    handoff.recovery_action,
                  "data-historical-workflow-group-recovery-failed-item-retryable" =>
                    handoff.retryable,
                  "data-historical-workflow-group-recovery-failed-item-href" => handoff.href,
                  "data-phx-link" => "patch",
                  "data-phx-link-state" => "push"
                })
            }
          end)
      }
    }
  end

  defp execution_plan_presentation(
         workflow_context,
         replacement_recovery,
         closure_readiness,
         group_recovery_forms,
         group_recovery
       ) do
    %{
      id: "dashboard-historical-workflow-group-recovery-execution-plan",
      class: "rounded border border-warning/30 bg-base-100/70 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-recovery-execution-plan-request-group" =>
            Map.get(workflow_context, :request_group_id),
          "data-historical-workflow-group-recovery-execution-plan-next-action" =>
            replacement_recovery.next_action,
          "data-historical-workflow-group-recovery-execution-plan-retry-eligible" =>
            replacement_recovery.retry_action.eligible,
          "data-historical-workflow-group-recovery-execution-plan-retry-count" =>
            replacement_recovery.retry_count,
          "data-historical-workflow-group-recovery-execution-plan-correction-count" =>
            Map.get(workflow_context, :request_group_nonretryable_failed),
          "data-historical-workflow-group-recovery-execution-plan-correction-task-count" =>
            replacement_recovery.correction_task_count,
          "data-historical-workflow-group-recovery-execution-plan-unresolved" =>
            group_recovery.unresolved,
          "data-historical-workflow-group-recovery-execution-plan-expected-effect" =>
            replacement_recovery.expected_effect,
          "data-historical-workflow-group-recovery-execution-plan-blockers" =>
            replacement_recovery.blockers,
          "data-historical-workflow-group-recovery-execution-plan-replacement-stage" =>
            replacement_recovery.replacement_action.stage,
          "data-historical-workflow-group-recovery-execution-plan-replacement-eligible" =>
            replacement_recovery.replacement_action.eligible,
          "data-historical-workflow-group-recovery-execution-plan-replacement-preview" =>
            replacement_recovery.replacement_action.preview
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: text_presentation("hud-label", "Recovery Execution Plan"),
        retry_count:
          text_presentation(
            "font-mono text-base-content/70",
            dom_text(replacement_recovery.retry_count) <> " retry"
          )
      },
      details: execution_plan_details_presentation(workflow_context, replacement_recovery),
      replacement_status:
        HistoricalWorkflowReplacementStatusComponents.presentation(
          workflow_context,
          replacement_recovery,
          closure_readiness,
          group_recovery_forms
        ),
      retry_button: group_retry_button_presentation(workflow_context, replacement_recovery),
      advancement_form: replacement_advancement_form_presentation(group_recovery_forms)
    }
  end

  defp execution_plan_details_presentation(workflow_context, replacement_recovery) do
    %{
      class: "mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
      rows:
        [
          detail_row(
            "next-action",
            "Next action",
            replacement_recovery.next_action,
            "font-mono break-all"
          ),
          detail_row("retry-batch", "Retry batch", replacement_recovery.retry_count, "font-mono"),
          detail_row(
            "corrections",
            "Corrections",
            Map.get(workflow_context, :request_group_nonretryable_failed) || "0",
            "font-mono"
          ),
          detail_row("expected", "Expected", replacement_recovery.expected_effect, "break-words"),
          optional_detail_row(
            "blocked-by",
            "Blocked by",
            replacement_recovery.blockers,
            "break-words text-base-content/75"
          )
        ]
        |> Enum.reject(&is_nil/1)
    }
  end

  defp group_retry_button_presentation(workflow_context, replacement_recovery) do
    %{
      visible: truthy?(replacement_recovery.retry_action.present),
      id: "dashboard-historical-workflow-group-retry-failed",
      type: "button",
      class: "btn btn-xs btn-error btn-outline mt-2 w-full justify-start",
      text: "Retry failed items",
      icon: %{name: "hero-arrow-path", class: "size-3"},
      attrs:
        raw_attrs(%{
          "phx-click" => "retry_historical_workflow_group_failed_jobs",
          "phx-value-request-group-id" => workflow_context.request_group_id,
          "phx-value-event-id" => workflow_context.event_id,
          "data-workflow-action-id" => replacement_recovery.retry_action.id,
          "data-workflow-action-eligible" => replacement_recovery.retry_action.eligible,
          "data-workflow-action-eligible-count" => replacement_recovery.retry_count,
          "data-workflow-action-reason" => replacement_recovery.retry_action.reason,
          "data-workflow-action-preview" => replacement_recovery.retry_action.preview,
          "data-workflow-action-expected-effect" => replacement_recovery.expected_effect,
          "data-confirm" => "Retry every retryable failed job in this request group?"
        })
    }
  end

  defp replacement_advancement_form_presentation(group_recovery_forms) do
    advancement = group_recovery_forms.replacement_advancement

    %{
      visible: truthy?(advancement.present),
      id: advancement.id,
      class: "mt-2 space-y-2 rounded border border-primary/30 bg-primary/5 p-2",
      attrs:
        raw_attrs(%{
          "phx-submit" => advancement.submit_event,
          "data-historical-workflow-group-recovery-advance-request-group" =>
            advancement.request_group_id,
          "data-historical-workflow-group-recovery-advance-stage" => advancement.stage,
          "data-historical-workflow-group-recovery-advance-eligible" => advancement.eligible,
          "data-historical-workflow-group-recovery-advance-count" => advancement.count,
          "data-historical-workflow-group-recovery-advance-reason" => advancement.reason,
          "data-historical-workflow-group-recovery-advance-preview" => advancement.preview,
          "data-historical-workflow-group-recovery-advance-correction-tasks" =>
            advancement.correction_tasks
        }),
      hidden_fields:
        advancement.hidden_fields
        |> Enum.with_index()
        |> Enum.map(fn {field, index} ->
          %{
            key: "historical-workflow-advancement-hidden-#{index}",
            attrs: raw_attrs(%{"type" => "hidden", "name" => field.name, "value" => field.value})
          }
        end),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: text_presentation("hud-label", "Replacement Advancement"),
        count: text_presentation("font-mono text-base-content/70", advancement.count)
      },
      preview: text_presentation("text-base-content/75", advancement.preview),
      button: %{
        id: "dashboard-historical-workflow-group-recovery-advance-corrected",
        type: "submit",
        class:
          class_names([
            "btn btn-xs btn-primary btn-outline w-full justify-between gap-2",
            advancement.disabled_bool && "btn-disabled"
          ]),
        attrs:
          raw_attrs(%{
            "name" => "historical_workflow_group[stage]",
            "value" => advancement.stage,
            "disabled" => advancement.disabled_bool,
            "data-workflow-action-id" => advancement.action_id,
            "data-workflow-action-eligible" => advancement.eligible,
            "data-workflow-action-eligible-count" => advancement.count,
            "data-workflow-action-stage" => advancement.stage,
            "data-workflow-action-reason" => advancement.reason,
            "data-workflow-action-preview" => advancement.preview,
            "data-workflow-action-correction-tasks" => advancement.correction_tasks
          }),
        label: %{
          class: "flex min-w-0 items-center gap-1",
          text: "Advance replacements",
          icon: %{name: "hero-forward", class: "h-3.5 w-3.5"}
        },
        count: text_presentation("font-mono", advancement.count)
      }
    }
  end

  defp recovery_details_presentation(workflow_context) do
    %{
      class: "grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 gap-y-1",
      rows:
        [
          detail_row(
            "retryable",
            "Retryable",
            Map.get(workflow_context, :request_group_retryable_failed),
            "font-mono"
          ),
          detail_row(
            "correction",
            "Correction",
            Map.get(workflow_context, :request_group_nonretryable_failed),
            "font-mono"
          ),
          detail_row(
            "retried",
            "Retried",
            Map.get(workflow_context, :request_group_retry_resolved),
            "font-mono"
          ),
          detail_row(
            "corrected",
            "Corrected",
            Map.get(workflow_context, :request_group_correction_requested),
            "font-mono"
          ),
          optional_detail_row(
            "items",
            "Items",
            Map.get(workflow_context, :request_group_failed_items),
            "font-mono break-all"
          )
        ]
        |> Enum.reject(&is_nil/1)
    }
  end

  defp recovery_item_groups_presentation(workflow_context, group_recovery) do
    [
      recovery_item_group(
        "retried",
        "Retried Items",
        Map.get(workflow_context, :request_group_retried_items),
        "data-historical-workflow-group-retried-items",
        "data-historical-workflow-group-retried-item",
        "rounded border border-base-300/50 bg-base-100/60 px-2 py-1 font-mono text-base-content/75 break-all",
        group_recovery.retried_items
      ),
      recovery_item_group(
        "corrected",
        "Corrected Items",
        Map.get(workflow_context, :request_group_corrected_items),
        "data-historical-workflow-group-corrected-items",
        "data-historical-workflow-group-corrected-item",
        "rounded border border-base-300/50 bg-base-100/60 px-2 py-1 font-mono text-base-content/75 break-all",
        group_recovery.corrected_items
      ),
      recovery_item_group(
        "correction-task",
        "Correction Tasks",
        Map.get(workflow_context, :request_group_correction_tasks),
        "data-historical-workflow-group-correction-tasks",
        "data-historical-workflow-group-correction-task",
        "rounded border border-primary/30 bg-primary/5 px-2 py-1 font-mono text-base-content/80 break-all",
        group_recovery.correction_task_items
      )
    ]
  end

  defp recovery_item_group(key, label, raw_value, group_attr, item_attr, item_class, items) do
    %{
      key: key,
      visible: DataLinkInspectorPanelPresentation.present_text?(raw_value),
      class: "space-y-1",
      attrs: raw_attrs(%{group_attr => raw_value}),
      label: text_presentation("hud-label", label),
      items:
        items
        |> Enum.with_index()
        |> Enum.map(fn {item, index} ->
          %{
            key: "historical-workflow-group-#{key}-#{index}",
            class: item_class,
            text: dom_text(item),
            attrs: raw_attrs(%{item_attr => item})
          }
        end)
    }
  end

  defp optional_detail_row(key, label, value, value_class) do
    if DataLinkInspectorPanelPresentation.present_text?(value) do
      detail_row(key, label, value, value_class)
    end
  end

  defp detail_row(key, label, value, value_class) do
    %{
      key: key,
      label: text_presentation("text-base-content/60", label),
      value: text_presentation(value_class, value)
    }
  end

  defp text_presentation(class, text), do: %{class: class, text: dom_text(text)}

  defp truthy?(value), do: value not in [nil, false]

  defp class_names(values) do
    values
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map(&dom_text/1)
    |> Enum.join(" ")
  end

  defp raw_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, dom_text(value))
    end)
  end

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value) when is_number(value), do: to_string(value)
  defp dom_text(value), do: to_string(value)

  defp job_progress_count(workflow_context, status) do
    workflow_context
    |> Map.get(:request_group_job_progress)
    |> job_progress_counts()
    |> Map.get(status, 0)
    |> Integer.to_string()
  end

  defp job_progress_counts(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, fn status_count, counts ->
      case status_count |> String.trim() |> String.split(" ", trim: true) do
        [status, count] -> Map.put(counts, status, parsed_count(count))
        _other -> counts
      end
    end)
  end

  defp job_progress_counts(_value), do: %{}

  defp parsed_count(value) do
    case Integer.parse(to_string(value)) do
      {count, ""} -> count
      _other -> 0
    end
  end
end
