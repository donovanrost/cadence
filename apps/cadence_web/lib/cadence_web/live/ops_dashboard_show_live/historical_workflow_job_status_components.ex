defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobStatusComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobRecoveryPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentation

  attr :workflow_context, :map, required: true
  attr :workflow_controls, :map, required: true
  attr :dashboard_current_path, :string, default: nil

  def job_status(%{workflow_controls: %{job_status: job_status}} = assigns)
      when job_status in [nil, false],
      do: ~H""

  def job_status(assigns) do
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
      id="dashboard-historical-workflow-job-status-component"
      v-component="HistoricalWorkflowJobStatus"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(_workflow_context, %{job_status: job_status}, _dashboard_current_path)
      when job_status in [nil, false],
      do: nil

  def presentation(workflow_context, workflow_controls, dashboard_current_path) do
    comparison_review_links =
      HistoricalWorkflowStatusNavigationPresentation.comparison_review_links(
        workflow_context,
        dashboard_current_path
      )

    job_recovery =
      HistoricalWorkflowJobRecoveryPresentation.build(
        workflow_context,
        workflow_controls
      )

    job_status_dto(
      workflow_context,
      workflow_controls,
      comparison_review_links,
      job_recovery
    )
  end

  defp job_status_dto(
         workflow_context,
         workflow_controls,
         comparison_review_links,
         job_recovery
       ) do
    replacement_run_id =
      Map.get(workflow_context, :missing_replacement_run_id) ||
        Map.get(workflow_context, :run_id)

    %{
      root: %{
        id: "dashboard-historical-workflow-job-status",
        class:
          class_names([
            "rounded border p-2 text-xs",
            workflow_controls.job_status_class
          ]),
        attrs:
          raw_attrs(%{
            "data-historical-workflow-job-id" => workflow_context.job_id,
            "data-historical-workflow-job-status" => workflow_context.job_status,
            "data-historical-workflow-job-comparison-review-request" =>
              workflow_context.comparison_review_request_event_id,
            "data-historical-workflow-job-comparison-review-kind" =>
              workflow_context.comparison_review_request_kind,
            "data-historical-workflow-job-comparison-review-open-count" =>
              workflow_context.comparison_review_open_count,
            "data-historical-workflow-job-comparison-review-placements" =>
              workflow_context.comparison_review_open_placement_ids,
            "data-historical-workflow-job-next-action" => job_recovery.next_action
          })
      },
      header: %{
        class: "flex items-center justify-between gap-2",
        label: %{class: "hud-label", text: "Workflow Job"},
        status: %{
          class: "font-mono uppercase tracking-normal",
          text: dom_text(workflow_context.job_status)
        }
      },
      guidance: guidance_dto(job_recovery),
      review_origin: review_origin_dto(workflow_context, comparison_review_links),
      details: details_dto(workflow_context),
      retry_button: retry_button_dto(workflow_context, job_recovery),
      stale_actions:
        stale_actions_dto(
          workflow_context,
          job_recovery,
          replacement_run_id
        ),
      missing_actions:
        missing_actions_dto(
          workflow_context,
          job_recovery,
          replacement_run_id
        )
    }
  end

  defp guidance_dto(job_recovery) do
    %{
      id: "dashboard-historical-workflow-job-guidance",
      class: "mt-2 rounded border border-base-300/60 bg-base-100/70 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-job-guidance-next-action" => job_recovery.next_action,
          "data-historical-workflow-job-guidance-retry-eligible" => job_recovery.retry.eligible,
          "data-historical-workflow-job-guidance-retry-reason" => job_recovery.retry.reason,
          "data-historical-workflow-job-guidance-retry-preview" => job_recovery.retry.preview,
          "data-historical-workflow-job-guidance-retry-explanation" =>
            job_recovery.retry.explanation,
          "data-historical-workflow-job-guidance-retry-state" => job_recovery.retry.state,
          "data-historical-workflow-job-guidance-retry-available-when" =>
            job_recovery.retry.available_when,
          "data-historical-workflow-job-guidance-correction-eligible" =>
            job_recovery.correction.eligible,
          "data-historical-workflow-job-guidance-correction-reason" =>
            job_recovery.correction.reason,
          "data-historical-workflow-job-guidance-correction-preview" =>
            job_recovery.correction.preview,
          "data-historical-workflow-job-guidance-correction-explanation" =>
            job_recovery.correction.explanation,
          "data-historical-workflow-job-guidance-correction-state" =>
            job_recovery.correction.state,
          "data-historical-workflow-job-guidance-correction-available-when" =>
            job_recovery.correction.available_when,
          "data-historical-workflow-job-guidance-active-state" => job_recovery.active_job_state,
          "data-historical-workflow-job-guidance-started-at" =>
            job_recovery.active_job_started_at,
          "data-historical-workflow-job-guidance-age-seconds" =>
            job_recovery.active_job_age_seconds,
          "data-historical-workflow-job-guidance-stale-after-seconds" =>
            job_recovery.active_job_stale_after_seconds
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: %{class: "hud-label", text: "Job Guidance"},
        next_action: %{
          class: "font-mono text-base-content/70",
          text: dom_text(job_recovery.next_action)
        }
      },
      guidance: %{
        class: "mt-1 text-base-content/75",
        text: dom_text(job_recovery.guidance)
      },
      policy_state: %{
        visible: DataLinkInspectorPanelPresentation.present_text?(job_recovery.policy_state),
        class: "mt-1 font-mono text-base-content/65",
        text: dom_text(job_recovery.policy_state)
      },
      available_when: %{
        visible: DataLinkInspectorPanelPresentation.present_text?(job_recovery.available_when),
        class: "mt-1 text-base-content/60",
        text: dom_text(job_recovery.available_when)
      }
    }
  end

  defp review_origin_dto(workflow_context, comparison_review_links) do
    placement_count = Integer.to_string(length(comparison_review_links.placement_links))

    %{
      visible: truthy?(comparison_review_links.review_href),
      id: "dashboard-historical-workflow-job-review-origin",
      class: "mt-2 space-y-2 rounded border border-info/40 bg-info/10 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-job-review-origin-request" =>
            workflow_context.comparison_review_request_event_id,
          "data-historical-workflow-job-review-origin-kind" =>
            workflow_context.comparison_review_request_kind,
          "data-historical-workflow-job-review-origin-open-count" =>
            workflow_context.comparison_review_open_count,
          "data-historical-workflow-job-review-origin-placements" =>
            workflow_context.comparison_review_open_placement_ids,
          "data-historical-workflow-job-review-origin-workflow-kind" =>
            Map.get(workflow_context, :comparison_review_workflow_kind),
          "data-historical-workflow-job-review-origin-workflow-action" =>
            Map.get(workflow_context, :comparison_review_workflow_action),
          "data-historical-workflow-job-review-origin-workflow-selection-kind" =>
            Map.get(workflow_context, :comparison_review_workflow_selection_kind),
          "data-historical-workflow-job-review-origin-workflow-selection-count" =>
            Map.get(workflow_context, :comparison_review_workflow_selection_count),
          "data-historical-workflow-job-review-origin-primary-data-view" =>
            Map.get(workflow_context, :comparison_review_primary_data_view),
          "data-historical-workflow-job-review-origin-compare-data-view" =>
            Map.get(workflow_context, :comparison_review_compare_data_view),
          "data-historical-workflow-job-review-origin-placement-count" => placement_count
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: %{class: "hud-label", text: "Review Origin"}
      },
      review_link: %{
        href: comparison_review_links.review_href,
        navigation_kind: "patch",
        class: "inline-flex items-center gap-1 font-mono text-primary hover:text-primary-focus",
        text: "Open review",
        icon: %{name: "hero-arrow-top-right-on-square", class: "h-3 w-3"},
        attrs:
          raw_attrs(%{
            "data-historical-workflow-job-review-origin-link" =>
              workflow_context.comparison_review_request_event_id,
            "data-historical-workflow-job-review-origin-href" =>
              comparison_review_links.review_href,
            "data-phx-link" => "patch",
            "data-phx-link-state" => "push"
          })
      },
      placements: %{
        visible: comparison_review_links.placement_links != [],
        class: "flex flex-wrap gap-1",
        attrs:
          raw_attrs(%{
            "data-historical-workflow-job-review-origin-placement-count" => placement_count
          }),
        links:
          comparison_review_links.placement_links
          |> Enum.with_index()
          |> Enum.map(fn {link, index} -> placement_link_dto(link, index) end)
      }
    }
  end

  defp placement_link_dto(link, index) do
    %{
      key: "historical-workflow-job-review-placement-#{index}",
      href: link.href,
      navigation_kind: "patch",
      class: "badge badge-xs badge-outline",
      text: dom_text(link.placement_id),
      attrs:
        raw_attrs(%{
          "data-historical-workflow-job-review-origin-placement" => link.placement_id,
          "data-historical-workflow-job-review-origin-placement-href" => link.href,
          "data-phx-link" => "patch",
          "data-phx-link-state" => "push"
        })
    }
  end

  defp details_dto(workflow_context) do
    %{
      class: "mt-1 grid grid-cols-[5rem_minmax(0,1fr)] gap-x-2 gap-y-1",
      rows:
        [
          detail_row("job", "Job", workflow_context.job_id, "font-mono break-all"),
          optional_detail_row(
            "attempts",
            "Attempts",
            workflow_context.job_attempts,
            "font-mono"
          ),
          optional_detail_row(
            "failure",
            "Failure",
            workflow_context.job_failure,
            "font-mono break-all"
          ),
          optional_detail_row(
            "failure-code",
            "Failure code",
            workflow_context.failure_code,
            "font-mono break-all"
          ),
          optional_detail_row(
            "retryable",
            "Retryable",
            workflow_context.retryable,
            "font-mono"
          ),
          optional_detail_row(
            "recovery",
            "Recovery",
            workflow_context.recovery_action,
            "font-mono break-all"
          ),
          optional_detail_row(
            "blockers",
            "Blockers",
            workflow_context.retry_blockers,
            "font-mono break-all"
          )
        ]
        |> Enum.reject(&is_nil/1)
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
      label: %{class: "text-base-content/60", text: label},
      value: %{class: value_class, text: dom_text(value)}
    }
  end

  defp retry_button_dto(workflow_context, job_recovery) do
    %{
      visible: truthy?(job_recovery.retry_button.present),
      id: "dashboard-historical-workflow-retry-job",
      type: "button",
      class: "btn btn-xs btn-error btn-outline mt-2",
      text: "Retry job",
      icon: %{name: "hero-arrow-path", class: "size-3"},
      attrs:
        raw_attrs(%{
          "phx-click" => "retry_historical_workflow_job",
          "phx-value-job-id" => workflow_context.job_id,
          "phx-value-event-id" => workflow_context.event_id,
          "data-workflow-action-id" => job_recovery.retry_button.id,
          "data-workflow-action-eligible" => job_recovery.retry_button.eligible,
          "data-workflow-action-reason" => job_recovery.retry_button.reason,
          "data-workflow-action-preview" => job_recovery.retry_button.preview
        })
    }
  end

  defp stale_actions_dto(workflow_context, job_recovery, replacement_run_id) do
    %{
      visible:
        job_recovery.next_action == "inspect_stale_job" and
          DataLinkInspectorPanelPresentation.present_text?(workflow_context.job_id) and
          DataLinkInspectorPanelPresentation.present_text?(workflow_context.event_id),
      id: "dashboard-historical-workflow-stale-job-actions",
      class: "mt-2 flex flex-wrap gap-2",
      attrs:
        raw_attrs(%{
          "data-workflow-action-scope" => "job_status",
          "data-workflow-action-job-id" => workflow_context.job_id,
          "data-workflow-action-event-id" => workflow_context.event_id,
          "data-workflow-action-job-started" => job_recovery.active_job_started_at,
          "data-workflow-action-job-age-seconds" => job_recovery.active_job_age_seconds,
          "data-workflow-action-job-stale-after-seconds" =>
            job_recovery.active_job_stale_after_seconds
        }),
      buttons: [
        %{
          id: "dashboard-historical-workflow-stale-job-inspect",
          type: "button",
          class: "btn btn-xs btn-warning btn-outline",
          text: "Inspect stale job",
          icon: %{name: "hero-magnifying-glass", class: "size-3"},
          attrs:
            raw_attrs(%{
              "phx-click" => "inspect_stale_historical_workflow_replacement_job",
              "phx-value-job-id" => workflow_context.job_id,
              "phx-value-event-id" => workflow_context.event_id,
              "phx-value-replacement-run-id" => replacement_run_id,
              "data-workflow-action-id" => "inspect_stale_replacement_job",
              "data-workflow-action-job-id" => workflow_context.job_id,
              "data-workflow-action-event-id" => workflow_context.event_id,
              "data-workflow-action-replacement-run" => replacement_run_id,
              "data-workflow-action-job-started" => job_recovery.active_job_started_at
            })
        },
        %{
          id: "dashboard-historical-workflow-stale-job-requeue",
          type: "button",
          class: "btn btn-xs btn-warning",
          text: "Requeue stale job",
          icon: %{name: "hero-arrow-path", class: "size-3"},
          attrs:
            raw_attrs(%{
              "phx-click" => "requeue_stale_historical_workflow_replacement_job",
              "phx-value-job-id" => workflow_context.job_id,
              "phx-value-event-id" => workflow_context.event_id,
              "phx-value-replacement-run-id" => replacement_run_id,
              "data-workflow-action-id" => "requeue_stale_replacement_job",
              "data-workflow-action-job-id" => workflow_context.job_id,
              "data-workflow-action-event-id" => workflow_context.event_id,
              "data-workflow-action-replacement-run" => replacement_run_id,
              "data-workflow-action-job-started" => job_recovery.active_job_started_at
            })
        }
      ]
    }
  end

  defp missing_actions_dto(workflow_context, job_recovery, replacement_run_id) do
    request_group_id = Map.get(workflow_context, :request_group_id)

    %{
      visible:
        job_recovery.next_action == "inspect_missing_job" and
          DataLinkInspectorPanelPresentation.present_text?(request_group_id) and
          DataLinkInspectorPanelPresentation.present_text?(replacement_run_id),
      id: "dashboard-historical-workflow-missing-job-actions",
      class: "mt-2 flex flex-wrap gap-2",
      attrs:
        raw_attrs(%{
          "data-workflow-action-scope" => "job_status",
          "data-workflow-action-request-group-id" => request_group_id,
          "data-workflow-action-replacement-run" => replacement_run_id,
          "data-workflow-action-expected-job-type" =>
            Map.get(workflow_context, :missing_replacement_expected_job_type)
        }),
      buttons: [
        %{
          id: "dashboard-historical-workflow-missing-job-inspect",
          type: "button",
          class: "btn btn-xs btn-warning btn-outline",
          text: "Inspect missing job",
          icon: %{name: "hero-magnifying-glass", class: "size-3"},
          attrs:
            raw_attrs(%{
              "phx-click" => "inspect_missing_historical_workflow_replacement_job",
              "phx-value-request-group-id" => request_group_id,
              "phx-value-replacement-run-id" => replacement_run_id,
              "data-workflow-action-id" => "inspect_missing_replacement_job",
              "data-workflow-action-request-group-id" => request_group_id,
              "data-workflow-action-replacement-run" => replacement_run_id,
              "data-workflow-action-expected-job-type" =>
                Map.get(workflow_context, :missing_replacement_expected_job_type)
            })
        }
      ]
    }
  end

  defp truthy?(value), do: value not in [nil, false]

  defp class_names(values) do
    values
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map_join(" ", &dom_text/1)
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
end
