defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementStatusComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr(:workflow_context, :map, required: true)
  attr(:replacement_recovery, :map, required: true)
  attr(:closure_readiness, :map, required: true)
  attr(:group_recovery_forms, :map, required: true)

  def replacement_status(assigns) do
    assigns =
      assign(
        assigns,
        :presentation,
        presentation(
          assigns.workflow_context,
          assigns.replacement_recovery,
          assigns.closure_readiness,
          assigns.group_recovery_forms
        )
      )

    ~H"""
    <.vue
      id="dashboard-historical-workflow-replacement-status-component"
      v-component="HistoricalWorkflowReplacementStatus"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(
        workflow_context,
        replacement_recovery,
        closure_readiness,
        group_recovery_forms
      ) do
    %{
      remaining_work: remaining_work_dto(workflow_context, replacement_recovery),
      closure_readiness: closure_readiness_dto(closure_readiness, group_recovery_forms)
    }
  end

  defp remaining_work_dto(_workflow_context, %{entries: []}), do: %{visible: false}

  defp remaining_work_dto(workflow_context, replacement_recovery) do
    %{
      visible: true,
      id: "dashboard-historical-workflow-group-recovery-remaining-work",
      class: "mt-2 space-y-2 rounded border border-primary/30 bg-primary/5 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-recovery-remaining-work-count" =>
            replacement_recovery.total_count,
          "data-historical-workflow-group-recovery-remaining-work-pending-count" =>
            replacement_recovery.pending_count,
          "data-historical-workflow-group-recovery-remaining-work-completed-count" =>
            replacement_recovery.completed_count,
          "data-historical-workflow-group-recovery-remaining-work-next-actions" =>
            replacement_recovery.next_actions,
          "data-historical-workflow-group-recovery-remaining-work-pending-runs" =>
            replacement_recovery.pending_runs,
          "data-historical-workflow-group-recovery-remaining-work-summary" =>
            replacement_recovery.work_summary,
          "data-historical-workflow-group-recovery-remaining-work-job-summary" =>
            replacement_recovery.job_summary,
          "data-historical-workflow-group-recovery-remaining-work-active-jobs" =>
            replacement_recovery.active_job_count,
          "data-historical-workflow-group-recovery-remaining-work-active-runs" =>
            replacement_recovery.active_run_ids,
          "data-historical-workflow-group-recovery-remaining-work-active-summary" =>
            replacement_recovery.active_summary,
          "data-historical-workflow-group-recovery-remaining-work-stale-jobs" =>
            replacement_recovery.stale_job_count,
          "data-historical-workflow-group-recovery-remaining-work-stale-runs" =>
            replacement_recovery.stale_run_ids,
          "data-historical-workflow-group-recovery-remaining-work-stale-summary" =>
            replacement_recovery.stale_summary,
          "data-historical-workflow-group-recovery-remaining-work-blocked-jobs" =>
            replacement_recovery.blocked_job_count,
          "data-historical-workflow-group-recovery-remaining-work-missing-jobs" =>
            replacement_recovery.missing_job_count,
          "data-historical-workflow-group-recovery-remaining-work-missing-runs" =>
            replacement_recovery.missing_run_ids
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: %{class: "hud-label", text: "Replacement Work"},
        count: %{
          class: "font-mono text-base-content/70",
          text: dom_text(replacement_recovery.pending_count) <> " pending"
        }
      },
      items: %{
        class: "space-y-1",
        entries:
          replacement_recovery.entries
          |> Enum.with_index()
          |> Enum.map(fn {entry, index} ->
            remaining_work_entry_dto(
              entry,
              index,
              workflow_context,
              replacement_recovery
            )
          end)
      },
      job_summaries: replacement_job_summaries_dto(replacement_recovery),
      retry_button: group_retry_button_dto(workflow_context, replacement_recovery)
    }
  end

  defp remaining_work_entry_dto(
         entry,
         index,
         workflow_context,
         replacement_recovery
       ) do
    %{
      key: "historical-workflow-replacement-work-#{index}",
      class: "rounded border border-base-300/60 bg-base-100/70 px-2 py-1",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-recovery-remaining-work-item" => entry.raw,
          "data-historical-workflow-group-recovery-remaining-work-source" => entry.source,
          "data-historical-workflow-group-recovery-remaining-work-replacement-run" =>
            entry.replacement_run,
          "data-historical-workflow-group-recovery-remaining-work-stage" => entry.stage,
          "data-historical-workflow-group-recovery-remaining-work-next-action" =>
            entry.next_action,
          "data-historical-workflow-group-recovery-remaining-work-status" => entry.status,
          "data-historical-workflow-group-recovery-remaining-work-job-status" => entry.job_status,
          "data-historical-workflow-group-recovery-remaining-work-job-id" => entry.job_id,
          "data-historical-workflow-group-recovery-remaining-work-event-id" => entry.event_id,
          "data-historical-workflow-group-recovery-remaining-work-job-started" =>
            entry.job_started_at,
          "data-historical-workflow-group-recovery-remaining-work-job-completed" =>
            entry.job_completed_at,
          "data-historical-workflow-group-recovery-remaining-work-job-age-state" =>
            entry.job_age_state,
          "data-historical-workflow-group-recovery-remaining-work-job-action" => entry.job_action,
          "data-historical-workflow-group-recovery-remaining-work-job-item" => entry.job_item
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        replacement_run: %{
          class: "min-w-0 truncate font-mono",
          text: dom_text(entry.replacement_run)
        },
        status: %{
          class: "badge badge-xs badge-outline",
          text: dom_text(entry.status)
        }
      },
      work_details: %{
        class: "mt-1 flex flex-wrap gap-2 text-[0.68rem] text-base-content/65",
        values: [
          %{class: "font-mono", text: dom_text(entry.stage)},
          %{class: "font-mono", text: dom_text(entry.next_action)},
          %{class: "min-w-0 break-all", text: dom_text(entry.source)}
        ]
      },
      job_details: replacement_job_details_dto(entry),
      actions:
        replacement_entry_actions_dto(
          entry,
          workflow_context,
          replacement_recovery
        )
    }
  end

  defp replacement_job_details_dto(entry) do
    if present_text?(entry.job_status) do
      %{
        visible: true,
        class: "mt-1 flex flex-wrap gap-2 text-[0.68rem] text-base-content/65",
        values: [
          %{class: "font-mono", text: dom_text(entry.job_status)},
          %{class: "font-mono", text: dom_text(entry.job_id)},
          %{class: "font-mono", text: dom_text(entry.job_action)}
        ]
      }
    else
      %{visible: false}
    end
  end

  defp replacement_entry_actions_dto(entry, workflow_context, replacement_recovery) do
    [
      stale_replacement_action_dto(entry, :inspect),
      stale_replacement_action_dto(entry, :requeue),
      missing_replacement_action_dto(entry, workflow_context),
      failed_replacement_action_dto(entry, replacement_recovery)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp stale_replacement_action_dto(
         %{job_action: "inspect_stale_replacement_job"} = entry,
         :inspect
       ) do
    %{
      id: "dashboard-historical-workflow-stale-replacement-inspect-#{entry.replacement_run}",
      type: "button",
      class: "btn btn-xs btn-warning btn-outline mt-1",
      text: "Inspect stale job",
      icon: %{name: "hero-magnifying-glass", class: "size-3"},
      attrs:
        raw_attrs(%{
          "phx-click" => "inspect_stale_historical_workflow_replacement_job",
          "phx-value-job-id" => entry.job_id,
          "phx-value-event-id" => entry.event_id,
          "phx-value-replacement-run-id" => entry.replacement_run,
          "data-workflow-action-id" => "inspect_stale_replacement_job",
          "data-workflow-action-scope" => "replacement_job",
          "data-workflow-action-replacement-run" => entry.replacement_run,
          "data-workflow-action-job-id" => entry.job_id,
          "data-workflow-action-event-id" => entry.event_id,
          "data-workflow-action-job-started" => entry.job_started_at
        })
    }
  end

  defp stale_replacement_action_dto(
         %{job_action: "inspect_stale_replacement_job"} = entry,
         :requeue
       ) do
    %{
      id: "dashboard-historical-workflow-stale-replacement-requeue-#{entry.replacement_run}",
      type: "button",
      class: "btn btn-xs btn-warning mt-1",
      text: "Requeue stale job",
      icon: %{name: "hero-arrow-path", class: "size-3"},
      attrs:
        raw_attrs(%{
          "phx-click" => "requeue_stale_historical_workflow_replacement_job",
          "phx-value-job-id" => entry.job_id,
          "phx-value-event-id" => entry.event_id,
          "phx-value-replacement-run-id" => entry.replacement_run,
          "data-workflow-action-id" => "requeue_stale_replacement_job",
          "data-workflow-action-scope" => "replacement_job",
          "data-workflow-action-replacement-run" => entry.replacement_run,
          "data-workflow-action-job-id" => entry.job_id,
          "data-workflow-action-event-id" => entry.event_id,
          "data-workflow-action-job-started" => entry.job_started_at
        })
    }
  end

  defp stale_replacement_action_dto(_entry, _kind), do: nil

  defp missing_replacement_action_dto(
         %{job_action: "inspect_missing_replacement_job"} = entry,
         workflow_context
       ) do
    %{
      id: "dashboard-historical-workflow-missing-replacement-inspect-#{entry.replacement_run}",
      type: "button",
      class: "btn btn-xs btn-warning btn-outline mt-1",
      text: "Inspect missing job",
      icon: %{name: "hero-magnifying-glass", class: "size-3"},
      attrs:
        raw_attrs(%{
          "phx-click" => "inspect_missing_historical_workflow_replacement_job",
          "phx-value-request-group-id" => workflow_context.request_group_id,
          "phx-value-replacement-run-id" => entry.replacement_run,
          "data-workflow-action-id" => "inspect_missing_replacement_job",
          "data-workflow-action-scope" => "replacement_job",
          "data-workflow-action-request-group" => workflow_context.request_group_id,
          "data-workflow-action-replacement-run" => entry.replacement_run,
          "data-workflow-action-source" => entry.source,
          "data-workflow-action-stage" => entry.stage,
          "data-workflow-action-next-action" => entry.next_action
        })
    }
  end

  defp missing_replacement_action_dto(_entry, _workflow_context), do: nil

  defp failed_replacement_action_dto(
         %{job_action: "inspect_failed_replacement_job"} = entry,
         replacement_recovery
       ) do
    if replacement_recovery.retry_action.present and present_text?(entry.job_id) and
         present_text?(entry.event_id) do
      %{
        id: "dashboard-historical-workflow-failed-replacement-retry-#{entry.replacement_run}",
        type: "button",
        class: "btn btn-xs btn-error btn-outline mt-1",
        text: "Retry failed job",
        icon: %{name: "hero-arrow-path", class: "size-3"},
        attrs:
          raw_attrs(%{
            "phx-click" => "retry_historical_workflow_job",
            "phx-value-job-id" => entry.job_id,
            "phx-value-event-id" => entry.event_id,
            "phx-value-replacement-run-id" => entry.replacement_run,
            "data-workflow-action-id" => "retry_failed_replacement_job",
            "data-workflow-action-scope" => "replacement_job",
            "data-workflow-action-replacement-run" => entry.replacement_run,
            "data-workflow-action-job-id" => entry.job_id,
            "data-workflow-action-event-id" => entry.event_id,
            "data-workflow-action-reason" => replacement_recovery.retry_action.reason,
            "data-workflow-action-preview" => replacement_recovery.retry_action.preview
          })
      }
    end
  end

  defp failed_replacement_action_dto(_entry, _replacement_recovery), do: nil

  defp replacement_job_summaries_dto(replacement_recovery) do
    [
      replacement_job_summary_dto(replacement_recovery, :active),
      replacement_job_summary_dto(replacement_recovery, :stale),
      replacement_job_summary_dto(replacement_recovery, :missing)
    ]
  end

  defp replacement_job_summary_dto(replacement_recovery, :active) do
    id = "dashboard-historical-workflow-group-recovery-active-replacement-jobs"

    if replacement_recovery.active_job_count != "0" do
      visible_replacement_job_summary_dto(
        id,
        "rounded border border-info/40 bg-info/10 p-2",
        %{
          "data-historical-workflow-group-recovery-active-replacement-job-count" =>
            replacement_recovery.active_job_count,
          "data-historical-workflow-group-recovery-active-replacement-runs" =>
            replacement_recovery.active_run_ids,
          "data-historical-workflow-group-recovery-active-replacement-summary" =>
            replacement_recovery.active_summary
        },
        replacement_recovery.active_job_count,
        replacement_recovery.active_summary,
        "Active Replacement Jobs"
      )
    else
      %{visible: false, key: id}
    end
  end

  defp replacement_job_summary_dto(replacement_recovery, :stale) do
    id = "dashboard-historical-workflow-group-recovery-stale-replacement-jobs"

    if replacement_recovery.stale_job_count != "0" do
      visible_replacement_job_summary_dto(
        id,
        "rounded border border-warning/40 bg-warning/10 p-2",
        %{
          "data-historical-workflow-group-recovery-stale-replacement-job-count" =>
            replacement_recovery.stale_job_count,
          "data-historical-workflow-group-recovery-stale-replacement-runs" =>
            replacement_recovery.stale_run_ids,
          "data-historical-workflow-group-recovery-stale-replacement-summary" =>
            replacement_recovery.stale_summary
        },
        replacement_recovery.stale_job_count,
        replacement_recovery.stale_summary,
        "Stale Replacement Jobs"
      )
    else
      %{visible: false, key: id}
    end
  end

  defp replacement_job_summary_dto(replacement_recovery, :missing) do
    id = "dashboard-historical-workflow-group-recovery-missing-replacement-jobs"

    if replacement_recovery.missing_job_count != "0" do
      visible_replacement_job_summary_dto(
        id,
        "rounded border border-warning/40 bg-warning/10 p-2",
        %{
          "data-historical-workflow-group-recovery-missing-replacement-job-count" =>
            replacement_recovery.missing_job_count,
          "data-historical-workflow-group-recovery-missing-replacement-runs" =>
            replacement_recovery.missing_run_ids,
          "data-historical-workflow-group-recovery-missing-replacement-summary" =>
            replacement_recovery.missing_summary
        },
        replacement_recovery.missing_job_count,
        replacement_recovery.missing_summary,
        "Missing Replacement Jobs"
      )
    else
      %{visible: false, key: id}
    end
  end

  defp visible_replacement_job_summary_dto(
         id,
         class,
         attrs,
         count,
         summary,
         label
       ) do
    %{
      visible: true,
      key: id,
      id: id,
      class: class,
      attrs: raw_attrs(attrs),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: %{class: "hud-label", text: label},
        count: %{class: "font-mono text-base-content/70", text: dom_text(count)}
      },
      summary: %{
        class: "mt-1 font-mono text-[0.68rem] text-base-content/70 break-all",
        text: dom_text(summary)
      }
    }
  end

  defp group_retry_button_dto(workflow_context, replacement_recovery) do
    if replacement_recovery.retry_action.present and
         replacement_recovery.failed_job_count != "0" do
      %{
        visible: true,
        id: "dashboard-historical-workflow-group-retry-failed-replacements",
        type: "button",
        class: "btn btn-xs btn-error btn-outline w-full justify-between gap-2",
        attrs:
          raw_attrs(%{
            "phx-click" => "retry_historical_workflow_group_failed_jobs",
            "phx-value-request-group-id" => workflow_context.request_group_id,
            "phx-value-event-id" => workflow_context.event_id,
            "phx-value-retry-run-ids" => replacement_recovery.failed_run_ids,
            "data-workflow-action-id" => replacement_recovery.retry_action.id,
            "data-workflow-action-scope" => "replacement_jobs",
            "data-workflow-action-eligible" => replacement_recovery.retry_action.eligible,
            "data-workflow-action-eligible-count" => replacement_recovery.failed_job_count,
            "data-workflow-action-retry-run-ids" => replacement_recovery.failed_run_ids,
            "data-workflow-action-reason" => replacement_recovery.retry_action.reason,
            "data-workflow-action-preview" => replacement_recovery.retry_action.preview,
            "data-confirm" => "Retry failed corrected replacement jobs in this request group?"
          }),
        label: %{
          class: "flex min-w-0 items-center gap-1",
          text: "Retry failed replacements",
          icon: %{name: "hero-arrow-path", class: "size-3"}
        },
        count: %{
          class: "font-mono",
          text: dom_text(replacement_recovery.failed_job_count)
        }
      }
    else
      %{visible: false}
    end
  end

  defp closure_readiness_dto(closure_readiness, group_recovery_forms) do
    %{
      id: "dashboard-historical-workflow-group-recovery-closure-readiness",
      class: "mt-2 space-y-2 rounded border border-info/30 bg-info/5 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-recovery-closure-status" => closure_readiness.status,
          "data-historical-workflow-group-recovery-closure-action" => closure_readiness.action,
          "data-historical-workflow-group-recovery-closure-actions" => closure_readiness.actions,
          "data-historical-workflow-group-recovery-closure-unresolved" =>
            closure_readiness.unresolved,
          "data-historical-workflow-group-recovery-closure-pending-replacements" =>
            closure_readiness.pending_replacements,
          "data-historical-workflow-group-recovery-closure-completed-replacements" =>
            closure_readiness.completed_replacements,
          "data-historical-workflow-group-recovery-closure-active-jobs" =>
            closure_readiness.active_jobs,
          "data-historical-workflow-group-recovery-closure-blocked-jobs" =>
            closure_readiness.blocked_jobs,
          "data-historical-workflow-group-recovery-closure-failed-jobs" =>
            closure_readiness.failed_jobs,
          "data-historical-workflow-group-recovery-closure-failed-runs" =>
            closure_readiness.failed_runs,
          "data-historical-workflow-group-recovery-closure-missing-jobs" =>
            closure_readiness.missing_jobs,
          "data-historical-workflow-group-recovery-closure-missing-runs" =>
            closure_readiness.missing_runs,
          "data-historical-workflow-group-recovery-closure-stale-jobs" =>
            closure_readiness.stale_jobs,
          "data-historical-workflow-group-recovery-closure-stale-runs" =>
            closure_readiness.stale_runs,
          "data-historical-workflow-group-recovery-closure-complete-eligible" =>
            closure_readiness.complete_eligible,
          "data-historical-workflow-group-recovery-closure-summary" => closure_readiness.summary
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: %{class: "hud-label", text: "Closure Readiness"},
        status: %{
          class: "font-mono text-base-content/70",
          text: dom_text(closure_readiness.status)
        }
      },
      details: %{
        class: "grid grid-cols-[8rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
        rows: [
          detail_row("action", "Action", "font-mono break-all", closure_readiness.action),
          detail_row(
            "action-queue",
            "Action queue",
            "font-mono break-all",
            closure_readiness.actions
          ),
          detail_row("unresolved", "Unresolved", "font-mono", closure_readiness.unresolved),
          detail_row(
            "replacements",
            "Replacements",
            "font-mono",
            dom_text(closure_readiness.pending_replacements) <>
              " pending / " <>
              dom_text(closure_readiness.completed_replacements) <>
              " complete"
          ),
          detail_row(
            "jobs",
            "Jobs",
            "font-mono",
            dom_text(closure_readiness.active_jobs) <>
              " active / " <>
              dom_text(closure_readiness.blocked_jobs) <>
              " blocked / " <>
              dom_text(closure_readiness.failed_jobs) <>
              " failed / " <>
              dom_text(closure_readiness.missing_jobs) <>
              " missing / " <>
              dom_text(closure_readiness.stale_jobs) <>
              " stale"
          )
        ]
      },
      completion_form:
        completion_form_dto(
          closure_readiness,
          group_recovery_forms
        )
    }
  end

  defp detail_row(key, label, value_class, value) do
    %{
      key: key,
      label: %{class: "text-base-content/60", text: label},
      value: %{class: value_class, text: dom_text(value)}
    }
  end

  defp completion_form_dto(%{status: "ready_to_complete"}, group_recovery_forms) do
    completion = group_recovery_forms.completion

    if truthy?(completion.present) do
      visible_completion_form_dto(completion)
    else
      %{visible: false}
    end
  end

  defp completion_form_dto(_closure_readiness, _group_recovery_forms),
    do: %{visible: false}

  defp visible_completion_form_dto(completion) do
    %{
      visible: true,
      id: completion.id,
      class: "space-y-2 rounded border border-success/30 bg-success/5 p-2",
      attrs:
        raw_attrs(%{
          "phx-submit" => completion.submit_event,
          "data-historical-workflow-group-recovery-complete-request-group" =>
            completion.request_group_id,
          "data-historical-workflow-group-recovery-complete-stage" => completion.stage,
          "data-historical-workflow-group-recovery-complete-eligible" => completion.eligible,
          "data-historical-workflow-group-recovery-complete-count" => completion.count,
          "data-historical-workflow-group-recovery-complete-reason" => completion.reason,
          "data-historical-workflow-group-recovery-complete-preview" => completion.preview
        }),
      hidden_fields:
        completion.hidden_fields
        |> Enum.with_index()
        |> Enum.map(fn {field, index} ->
          %{
            key: "historical-workflow-completion-hidden-#{index}",
            attrs:
              raw_attrs(%{
                "type" => "hidden",
                "name" => field.name,
                "value" => field.value
              })
          }
        end),
      button: %{
        id: "dashboard-historical-workflow-group-recovery-complete",
        type: "submit",
        class:
          class_names([
            "btn btn-xs btn-success btn-outline w-full justify-between gap-2",
            truthy?(completion.disabled_bool) && "btn-disabled"
          ]),
        attrs:
          raw_attrs(%{
            "name" => "historical_workflow_group[stage]",
            "value" => completion.stage,
            "disabled" => completion.disabled_bool,
            "data-workflow-action-id" => completion.action_id,
            "data-workflow-action-stage" => completion.stage,
            "data-workflow-action-eligible" => completion.eligible,
            "data-workflow-action-eligible-count" => completion.count,
            "data-workflow-action-reason" => completion.reason,
            "data-workflow-action-preview" => completion.preview
          }),
        label: %{
          class: "flex min-w-0 items-center gap-1",
          text: "Complete group",
          icon: %{name: "hero-flag", class: "h-3.5 w-3.5"}
        },
        count: %{class: "font-mono", text: dom_text(completion.count)}
      }
    }
  end

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

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false
end
