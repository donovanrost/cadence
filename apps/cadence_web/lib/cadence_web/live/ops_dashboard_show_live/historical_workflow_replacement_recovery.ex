defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecovery do
  @moduledoc false

  @stale_replacement_job_seconds 15 * 60
  @empty_replacement_action %{
    present: false,
    id: nil,
    stage: nil,
    eligible: "false",
    eligible_bool: false,
    disabled_bool: true,
    count: "0",
    reason: nil,
    preview: "Advance 0 corrected replacement requests to next stage.",
    correction_tasks: nil,
    submit_reason: "dashboard_recovery_replacement_advanced"
  }
  @empty_completion_action %{
    present: false,
    id: nil,
    stage: "completed",
    eligible: "false",
    eligible_bool: false,
    disabled_bool: true,
    count: "0",
    reason: nil,
    preview: nil,
    submit_reason: "dashboard_recovery_group_completed"
  }
  @empty_retry_action %{
    present: false,
    id: nil,
    eligible: "false",
    eligible_bool: false,
    count: "0",
    reason: nil,
    preview: nil,
    explanation: nil,
    state: nil,
    available_when: nil
  }

  @type entry :: %{
          raw: binary(),
          source: binary(),
          replacement_run: binary(),
          stage: binary(),
          next_action: binary(),
          status: binary(),
          job_item: binary() | nil,
          event_id: binary() | nil,
          job_id: binary() | nil,
          job_status: binary(),
          job_started_at: binary() | nil,
          job_completed_at: binary() | nil,
          job_age_state: binary(),
          job_action: binary()
        }

  @type replacement_action :: %{
          present: boolean(),
          id: binary() | nil,
          stage: binary() | nil,
          eligible: binary(),
          eligible_bool: boolean(),
          disabled_bool: boolean(),
          count: binary(),
          reason: binary() | nil,
          preview: binary(),
          correction_tasks: binary() | nil,
          submit_reason: binary()
        }

  @type completion_action :: %{
          present: boolean(),
          id: binary() | nil,
          stage: binary(),
          eligible: binary(),
          eligible_bool: boolean(),
          disabled_bool: boolean(),
          count: binary(),
          reason: binary() | nil,
          preview: binary() | nil,
          submit_reason: binary()
        }

  @type retry_action :: %{
          present: boolean(),
          id: binary() | nil,
          eligible: binary(),
          eligible_bool: boolean(),
          count: binary(),
          reason: binary() | nil,
          preview: binary() | nil,
          explanation: binary() | nil,
          state: binary() | nil,
          available_when: binary() | nil
        }

  @type t :: %__MODULE__{
          entries: [entry()],
          closure_readiness: map(),
          next_action: binary(),
          guidance: binary(),
          retry_count: binary(),
          correction_task_count: binary(),
          expected_effect: binary(),
          blockers: binary() | nil,
          retry_action: retry_action(),
          replacement_action: replacement_action(),
          completion_action: completion_action(),
          total_count: binary(),
          pending_count: binary(),
          completed_count: binary(),
          next_actions: binary(),
          pending_runs: binary(),
          work_summary: binary(),
          job_summary: binary(),
          active_job_count: binary(),
          active_run_ids: binary(),
          active_summary: binary(),
          stale_job_count: binary(),
          stale_run_ids: binary(),
          stale_summary: binary(),
          blocked_job_count: binary(),
          failed_job_count: binary(),
          failed_run_ids: binary(),
          missing_job_count: binary(),
          missing_run_ids: binary(),
          missing_summary: binary()
        }

  defstruct entries: [],
            closure_readiness: %{
              status: "monitor_group",
              action: "monitor_group",
              actions: "monitor_group",
              unresolved: "0",
              pending_replacements: "0",
              completed_replacements: "0",
              active_jobs: "0",
              blocked_jobs: "0",
              failed_jobs: "0",
              failed_runs: "",
              missing_jobs: "0",
              missing_runs: "",
              stale_jobs: "0",
              stale_runs: "",
              complete_eligible: "0",
              summary:
                "status monitor_group; action monitor_group; unresolved 0; replacements pending 0 completed 0; jobs active 0 blocked 0 failed 0 missing 0 stale 0; complete_eligible 0"
            },
            next_action: "monitor_recovered_group",
            guidance:
              "All failed items have a recovery handoff; monitor replacement jobs until the group closes.",
            retry_count: "0",
            correction_task_count: "0",
            expected_effect:
              "All failed items have a recovery handoff; monitor replacement work until the group closes.",
            blockers: nil,
            retry_action: @empty_retry_action,
            replacement_action: @empty_replacement_action,
            completion_action: @empty_completion_action,
            total_count: "0",
            pending_count: "0",
            completed_count: "0",
            next_actions: "",
            pending_runs: "",
            work_summary: "",
            job_summary: "",
            active_job_count: "0",
            active_run_ids: "",
            active_summary: "",
            stale_job_count: "0",
            stale_run_ids: "",
            stale_summary: "",
            blocked_job_count: "0",
            failed_job_count: "0",
            failed_run_ids: "",
            missing_job_count: "0",
            missing_run_ids: "",
            missing_summary: ""

  @spec build(map() | nil) :: t()
  def build(workflow_context), do: build(workflow_context, %{}, DateTime.utc_now())

  @spec build(map() | nil, DateTime.t() | map()) :: t()
  def build(workflow_context, %DateTime{} = now), do: build(workflow_context, %{}, now)

  def build(workflow_context, workflow_controls) when is_map(workflow_controls),
    do: build(workflow_context, workflow_controls, DateTime.utc_now())

  @spec build(map() | nil, map(), DateTime.t()) :: t()
  def build(workflow_context, workflow_controls, %DateTime{} = now)
      when is_map(workflow_context) and is_map(workflow_controls) do
    entries = replacement_work(workflow_context, now)
    next_action = next_action(workflow_context, workflow_controls)
    retry_count = retry_count(workflow_context, workflow_controls)
    correction_task_count = correction_task_count(workflow_context)

    recovery = %__MODULE__{
      entries: entries,
      next_action: next_action,
      guidance: guidance_text(workflow_context, workflow_controls, next_action),
      retry_count: retry_count,
      correction_task_count: correction_task_count,
      expected_effect:
        expected_effect(
          workflow_context,
          workflow_controls,
          next_action,
          retry_count,
          correction_task_count
        ),
      blockers: blockers(workflow_controls, next_action),
      retry_action: retry_action(workflow_controls, retry_count),
      replacement_action: replacement_action(workflow_controls),
      completion_action: completion_action(workflow_controls),
      total_count: Integer.to_string(length(entries)),
      pending_count: pending_count(entries),
      completed_count: completed_count(entries),
      next_actions: next_actions(entries),
      pending_runs: pending_runs(entries),
      work_summary: work_summary(entries),
      job_summary: job_summary(entries),
      active_job_count: active_job_count(entries),
      active_run_ids: active_run_ids(entries),
      active_summary: active_summary(entries),
      stale_job_count: stale_job_count(entries),
      stale_run_ids: stale_run_ids(entries),
      stale_summary: stale_summary(entries),
      blocked_job_count: blocked_job_count(entries),
      failed_job_count: failed_job_count(entries),
      failed_run_ids: failed_run_ids(entries),
      missing_job_count: missing_job_count(entries),
      missing_run_ids: missing_run_ids(entries),
      missing_summary: missing_summary(entries)
    }

    %{
      recovery
      | closure_readiness: closure_readiness(workflow_context, workflow_controls, recovery)
    }
  end

  def build(_workflow_context, _workflow_controls, %DateTime{}), do: %__MODULE__{}

  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @spec next_action(map(), map()) :: binary()
  def next_action(workflow_context, workflow_controls) do
    cond do
      action_eligible?(Map.get(workflow_controls, :group_retry_action)) ->
        "retry_failed_items"

      positive_text?(Map.get(workflow_context, :request_group_nonretryable_failed)) ->
        "create_corrected_requests"

      correction_task_count(workflow_context) != "0" ->
        "advance_corrected_requests"

      unresolved(workflow_context) == "0" ->
        "monitor_recovered_group"

      true ->
        "inspect_failed_items"
    end
  end

  defp guidance_text(_workflow_context, workflow_controls, next_action) do
    case next_action do
      "retry_failed_items" ->
        action_value(Map.get(workflow_controls, :group_retry_action), :preview) ||
          "Retry eligible failed jobs in this request group."

      "create_corrected_requests" ->
        "Create corrected workflow requests for non-retryable failed items."

      "advance_corrected_requests" ->
        "Advance corrected replacement requests through their remaining workflow stages."

      "monitor_recovered_group" ->
        "All failed items have a recovery handoff; monitor replacement jobs until the group closes."

      _action ->
        "Inspect failed items to decide whether retry or correction is required."
    end
  end

  defp expected_effect(
         _workflow_context,
         _workflow_controls,
         "retry_failed_items",
         retry_count,
         _correction_task_count
       ) do
    "Retry will requeue #{retry_count} #{pluralized(retry_count, "failed item", "failed items")} and select the retried lifecycle event."
  end

  defp expected_effect(
         workflow_context,
         _workflow_controls,
         "create_corrected_requests",
         _retry_count,
         _correction_task_count
       ) do
    count = Map.get(workflow_context, :request_group_nonretryable_failed) || "0"

    "Create corrected requests for #{count} #{pluralized(count, "non-retryable failure", "non-retryable failures")}."
  end

  defp expected_effect(
         _workflow_context,
         _workflow_controls,
         "advance_corrected_requests",
         _retry_count,
         correction_task_count
       ) do
    "Advance #{correction_task_count} #{pluralized(correction_task_count, "corrected replacement request", "corrected replacement requests")} through the remaining workflow stages."
  end

  defp expected_effect(
         _workflow_context,
         _workflow_controls,
         "monitor_recovered_group",
         _retry_count,
         _correction_task_count
       ) do
    "All failed items have a recovery handoff; monitor replacement work until the group closes."
  end

  defp expected_effect(
         _workflow_context,
         _workflow_controls,
         _action,
         _retry_count,
         _correction_task_count
       ) do
    "Inspect failed item evidence before executing retry or correction."
  end

  defp blockers(_workflow_controls, "retry_failed_items"), do: nil

  defp blockers(_workflow_controls, "create_corrected_requests"),
    do:
      "Non-retryable failures require corrected workflow requests from their failed-item inspectors."

  defp blockers(_workflow_controls, "advance_corrected_requests"), do: nil
  defp blockers(_workflow_controls, "monitor_recovered_group"), do: nil

  defp blockers(workflow_controls, _action) do
    action_value(Map.get(workflow_controls, :group_retry_action), :available_when) ||
      "No executable group recovery action is currently eligible."
  end

  defp retry_action(workflow_controls, retry_count) do
    action = Map.get(workflow_controls, :group_retry_action)

    %{
      present: Map.get(workflow_controls, :group_retryable_failures) == true,
      id: action_value(action, :id),
      eligible: bool_attr(action_eligible?(action)),
      eligible_bool: action_eligible?(action),
      count: retry_count,
      reason: action_value(action, :reason),
      preview: action_value(action, :preview),
      explanation: action_value(action, :explanation),
      state: action_value(action, :state_summary),
      available_when: action_value(action, :available_when)
    }
  end

  defp replacement_action(workflow_controls) do
    case selected_replacement_action(workflow_controls) do
      nil ->
        @empty_replacement_action

      action ->
        count = replacement_action_count(action)
        stage = action_value(action, :stage)

        %{
          present: true,
          id: action_value(action, :id),
          stage: stage,
          eligible: bool_attr(action_eligible?(action)),
          eligible_bool: action_eligible?(action),
          disabled_bool: not action_eligible?(action),
          count: count,
          reason: action_value(action, :reason),
          preview: replacement_action_preview(count, stage),
          correction_tasks: action_value(action, :correction_tasks),
          submit_reason: replacement_action_submit_reason(stage)
        }
    end
  end

  defp selected_replacement_action(workflow_controls) when is_map(workflow_controls) do
    actions =
      workflow_controls
      |> Map.get(:group_stage_actions, [])
      |> Enum.filter(fn action ->
        present_text?(action_value(action, :correction_tasks))
      end)

    Enum.find(actions, &action_eligible?/1) || List.first(actions)
  end

  defp selected_replacement_action(_workflow_controls), do: nil

  defp replacement_action_count(action) do
    correction_count =
      action
      |> action_value(:correction_tasks)
      |> items()
      |> length()

    if correction_count > 0 do
      Integer.to_string(correction_count)
    else
      case action_value(action, :eligible_count) do
        count when is_integer(count) -> Integer.to_string(count)
        count when is_binary(count) and count != "" -> count
        _other -> "0"
      end
    end
  end

  defp replacement_action_preview(count, stage) do
    stage = stage || "next stage"

    "Advance #{count} corrected #{pluralized(count, "replacement request", "replacement requests")} to #{stage}."
  end

  defp replacement_action_submit_reason(stage) when is_binary(stage) and stage != "",
    do: "dashboard_recovery_replacement_#{stage}"

  defp replacement_action_submit_reason(_stage), do: "dashboard_recovery_replacement_advanced"

  defp completion_action(workflow_controls) do
    case selected_completion_action(workflow_controls) do
      nil ->
        @empty_completion_action

      action ->
        %{
          present: true,
          id: action_value(action, :id),
          stage: action_value(action, :stage) || "completed",
          eligible: bool_attr(action_eligible?(action)),
          eligible_bool: action_eligible?(action),
          disabled_bool: truthy?(action_value(action, :disabled?)),
          count: action_count(action),
          reason: action_value(action, :reason),
          preview: action_value(action, :preview),
          submit_reason: "dashboard_recovery_group_completed"
        }
    end
  end

  defp selected_completion_action(workflow_controls) when is_map(workflow_controls) do
    workflow_controls
    |> Map.get(:group_stage_actions, [])
    |> Enum.find(&(action_value(&1, :stage) == "completed"))
  end

  defp selected_completion_action(_workflow_controls), do: nil

  defp action_count(action) do
    case action_value(action, :eligible_count) do
      count when is_integer(count) -> Integer.to_string(count)
      count when is_binary(count) and count != "" -> count
      _other -> "0"
    end
  end

  defp closure_readiness(workflow_context, workflow_controls, recovery) do
    unresolved_count = integer_value(unresolved(workflow_context))
    pending_replacements = integer_value(recovery.pending_count)
    completed_replacements = integer_value(recovery.completed_count)

    active_jobs =
      max(
        active_group_job_count(workflow_context),
        integer_value(recovery.active_job_count)
      )

    group_blocked_jobs = blocked_group_job_count(workflow_context)
    replacement_blocked_jobs = integer_value(recovery.blocked_job_count)
    stale_jobs = integer_value(recovery.stale_job_count)
    failed_jobs = integer_value(recovery.failed_job_count)
    missing_jobs = integer_value(recovery.missing_job_count)
    blocked_jobs = max(group_blocked_jobs, replacement_blocked_jobs)
    complete_eligible = integer_value(Map.get(workflow_context, :request_group_complete_eligible))

    status =
      closure_status(
        unresolved_count,
        pending_replacements,
        active_jobs,
        group_blocked_jobs,
        replacement_blocked_jobs,
        stale_jobs,
        complete_eligible
      )

    actions =
      closure_actions(
        status,
        workflow_context,
        workflow_controls,
        replacement_blocked_jobs,
        failed_jobs,
        missing_jobs,
        stale_jobs
      )

    action = List.first(actions) || "monitor_group"

    %{
      status: status,
      action: action,
      actions: Enum.join(actions, ","),
      unresolved: Integer.to_string(unresolved_count),
      pending_replacements: Integer.to_string(pending_replacements),
      completed_replacements: Integer.to_string(completed_replacements),
      active_jobs: Integer.to_string(active_jobs),
      blocked_jobs: Integer.to_string(blocked_jobs),
      failed_jobs: Integer.to_string(failed_jobs),
      failed_runs: recovery.failed_run_ids,
      missing_jobs: Integer.to_string(missing_jobs),
      missing_runs: recovery.missing_run_ids,
      stale_jobs: Integer.to_string(stale_jobs),
      stale_runs: recovery.stale_run_ids,
      complete_eligible: Integer.to_string(complete_eligible),
      summary:
        closure_summary(status, action, %{
          unresolved: unresolved_count,
          pending_replacements: pending_replacements,
          completed_replacements: completed_replacements,
          active_jobs: active_jobs,
          blocked_jobs: blocked_jobs,
          failed_jobs: failed_jobs,
          missing_jobs: missing_jobs,
          stale_jobs: stale_jobs,
          complete_eligible: complete_eligible
        })
    }
  end

  defp closure_status(
         unresolved_count,
         _pending_replacements,
         _active_jobs,
         _group_blocked_jobs,
         _replacement_blocked_jobs,
         _stale_jobs,
         _complete_eligible
       )
       when unresolved_count > 0,
       do: "operator_action_required"

  defp closure_status(
         _unresolved,
         _pending_replacements,
         _active_jobs,
         _group_blocked_jobs,
         replacement_blocked_jobs,
         _stale_jobs,
         _complete_eligible
       )
       when replacement_blocked_jobs > 0,
       do: "inspect_job_state"

  defp closure_status(
         _unresolved,
         _pending_replacements,
         _active_jobs,
         _group_blocked_jobs,
         _replacement_blocked_jobs,
         stale_jobs,
         _complete_eligible
       )
       when stale_jobs > 0,
       do: "inspect_job_state"

  defp closure_status(
         _unresolved,
         pending_replacements,
         _active_jobs,
         _group_blocked_jobs,
         _replacement_blocked_jobs,
         _stale_jobs,
         _complete_eligible
       )
       when pending_replacements > 0,
       do: "replacement_work_pending"

  defp closure_status(
         _unresolved,
         _pending_replacements,
         active_jobs,
         _group_blocked_jobs,
         _replacement_blocked_jobs,
         _stale_jobs,
         _complete_eligible
       )
       when active_jobs > 0,
       do: "monitor_jobs"

  defp closure_status(
         _unresolved,
         _pending_replacements,
         _active_jobs,
         group_blocked_jobs,
         _replacement_blocked_jobs,
         _stale_jobs,
         _complete_eligible
       )
       when group_blocked_jobs > 0,
       do: "inspect_job_state"

  defp closure_status(
         _unresolved,
         _pending_replacements,
         _active_jobs,
         _group_blocked_jobs,
         _replacement_blocked_jobs,
         _stale_jobs,
         complete_eligible
       )
       when complete_eligible > 0,
       do: "ready_to_complete"

  defp closure_status(
         _unresolved,
         _pending_replacements,
         _active_jobs,
         _group_blocked_jobs,
         _replacement_blocked_jobs,
         _stale_jobs,
         _complete_eligible
       ),
       do: "monitor_group"

  defp closure_actions(
         "operator_action_required",
         workflow_context,
         workflow_controls,
         _replacement_blocked_jobs,
         _failed_jobs,
         _missing_jobs,
         _stale_jobs
       ) do
    [next_action(workflow_context, workflow_controls)]
  end

  defp closure_actions(
         "replacement_work_pending",
         _workflow_context,
         _workflow_controls,
         _replacement_blocked_jobs,
         _failed_jobs,
         _missing_jobs,
         _stale_jobs
       ),
       do: ["advance_corrected_requests"]

  defp closure_actions(
         "monitor_jobs",
         _workflow_context,
         _workflow_controls,
         _replacement_blocked_jobs,
         _failed_jobs,
         _missing_jobs,
         _stale_jobs
       ),
       do: ["monitor_replacement_jobs"]

  defp closure_actions(
         "inspect_job_state",
         _workflow_context,
         workflow_controls,
         _replacement_blocked_jobs,
         failed_jobs,
         missing_jobs,
         stale_jobs
       ) do
    [
      if(missing_jobs > 0, do: "inspect_missing_replacement_jobs"),
      failed_replacement_action(failed_jobs, workflow_controls),
      if(stale_jobs > 0, do: "inspect_stale_replacement_jobs")
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ["inspect_job_state"]
      actions -> actions
    end
  end

  defp closure_actions(
         "ready_to_complete",
         _workflow_context,
         _workflow_controls,
         _replacement_blocked_jobs,
         _failed_jobs,
         _missing_jobs,
         _stale_jobs
       ),
       do: ["complete_group"]

  defp closure_actions(
         _status,
         _workflow_context,
         _workflow_controls,
         _replacement_blocked_jobs,
         _failed_jobs,
         _missing_jobs,
         _stale_jobs
       ),
       do: ["monitor_group"]

  defp failed_replacement_action(failed_jobs, workflow_controls) when failed_jobs > 0 do
    if action_eligible?(Map.get(workflow_controls, :group_retry_action)) do
      "retry_failed_replacement_jobs"
    else
      "inspect_failed_replacement_jobs"
    end
  end

  defp failed_replacement_action(_failed_jobs, _workflow_controls), do: nil

  defp closure_summary(status, action, counts) do
    [
      "status #{status}",
      "action #{action}",
      "unresolved #{counts.unresolved}",
      "replacements pending #{counts.pending_replacements} completed #{counts.completed_replacements}",
      "jobs active #{counts.active_jobs} blocked #{counts.blocked_jobs} failed #{counts.failed_jobs} missing #{counts.missing_jobs} stale #{counts.stale_jobs}",
      "complete_eligible #{counts.complete_eligible}"
    ]
    |> Enum.join("; ")
  end

  defp replacement_work(workflow_context, now) do
    job_items_by_run = job_items_by_run(workflow_context)

    workflow_context
    |> Map.get(:request_group_correction_tasks)
    |> items()
    |> Enum.map(&replacement_work_entry(&1, job_items_by_run, now))
  end

  defp replacement_work_entry(task, job_items_by_run, now) do
    replacement_run = replacement_run(task)
    job_item = Map.get(job_items_by_run, replacement_run, empty_job_item())

    parsed_stage = task_stage(task)
    parsed_next_action = task_next_action(task)
    job_status = replacement_job_status(job_item, parsed_stage, parsed_next_action)

    entry = %{
      raw: task,
      source: replacement_source(task),
      replacement_run: replacement_run,
      stage: parsed_stage,
      next_action: parsed_next_action,
      job_item: Map.get(job_item, :raw),
      event_id: Map.get(job_item, :event_id),
      job_id: Map.get(job_item, :job_id),
      job_status: job_status,
      job_started_at: Map.get(job_item, :started_at),
      job_completed_at: Map.get(job_item, :completed_at),
      job_age_state: replacement_job_age_state(job_item, now)
    }

    entry
    |> Map.put(:status, replacement_work_status(task))
    |> Map.put(:job_action, replacement_job_action(entry))
  end

  defp replacement_source(task) do
    case String.split(task, " replacement ", parts: 2) do
      [source, _replacement] -> source
      _parts -> task
    end
  end

  defp replacement_run(task) do
    with [_source, replacement] <- String.split(task, " replacement ", parts: 2),
         [replacement_run, _stage] <- String.split(replacement, " stage ", parts: 2) do
      replacement_run
    else
      _parts -> ""
    end
  end

  defp task_stage(task) do
    with [_source, replacement] <- String.split(task, " replacement ", parts: 2),
         [_replacement_run, stage] <- String.split(replacement, " stage ", parts: 2),
         [stage, _next_action] <- String.split(stage, " next ", parts: 2) do
      stage
    else
      _parts -> ""
    end
  end

  defp task_next_action(task) do
    with [_source, replacement] <- String.split(task, " replacement ", parts: 2),
         [_replacement_run, stage] <- String.split(replacement, " stage ", parts: 2),
         [_stage, next_action] <- String.split(stage, " next ", parts: 2) do
      next_action
    else
      _parts -> ""
    end
  end

  defp replacement_work_status(task) do
    case task_next_action(task) do
      "done" -> "complete"
      _next_action -> "pending"
    end
  end

  defp replacement_job_status(job_item, stage, next_action) do
    case Map.get(job_item, :status) do
      status when is_binary(status) and status != "" ->
        status

      _status ->
        if replacement_job_expected?(stage, next_action), do: "missing", else: ""
    end
  end

  defp replacement_job_expected?(stage, next_action) do
    stage in ["started", "completed"] or next_action in ["complete", "done"]
  end

  defp pending_count(entries) do
    entries
    |> Enum.count(&(&1.status == "pending"))
    |> Integer.to_string()
  end

  defp completed_count(entries) do
    entries
    |> Enum.count(&(&1.status == "complete"))
    |> Integer.to_string()
  end

  defp next_actions(entries) do
    entries
    |> Enum.filter(&(&1.status == "pending"))
    |> Enum.map(& &1.next_action)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp pending_runs(entries) do
    entries
    |> Enum.filter(&(&1.status == "pending"))
    |> Enum.map(& &1.replacement_run)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(",")
  end

  defp work_summary(entries) do
    entries
    |> Enum.map_join("; ", fn entry ->
      "#{entry.replacement_run} #{entry.stage} next #{entry.next_action} #{entry.status}"
    end)
  end

  defp job_summary(entries) do
    entries
    |> Enum.filter(&present_text?(&1.job_status))
    |> Enum.map_join("; ", fn entry ->
      "#{entry.replacement_run} #{entry.job_status} #{replacement_job_id(entry)} #{entry.job_action}"
    end)
  end

  defp active_job_count(entries) do
    entries
    |> Enum.count(&(&1.job_status in ["queued", "running"]))
    |> Integer.to_string()
  end

  defp active_run_ids(entries) do
    entries
    |> Enum.filter(&(&1.job_status in ["queued", "running"]))
    |> Enum.map(& &1.replacement_run)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp active_summary(entries) do
    entries
    |> Enum.filter(&(&1.job_status in ["queued", "running"]))
    |> Enum.map_join("; ", fn entry ->
      "#{entry.replacement_run} #{entry.job_status} #{replacement_job_id(entry)} #{entry.job_action}"
    end)
  end

  defp stale_job_count(entries) do
    entries
    |> Enum.count(&(&1.job_age_state == "stale"))
    |> Integer.to_string()
  end

  defp stale_run_ids(entries) do
    entries
    |> Enum.filter(&(&1.job_age_state == "stale"))
    |> Enum.map(& &1.replacement_run)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp stale_summary(entries) do
    entries
    |> Enum.filter(&(&1.job_age_state == "stale"))
    |> Enum.map_join("; ", fn entry ->
      "#{entry.replacement_run} #{entry.job_status} #{replacement_job_id(entry)} #{entry.job_started_at} #{entry.job_action}"
    end)
  end

  defp blocked_job_count(entries) do
    entries
    |> Enum.count(&(&1.job_status in ["failed", "missing"]))
    |> Integer.to_string()
  end

  defp failed_job_count(entries) do
    entries
    |> Enum.count(&(&1.job_status == "failed"))
    |> Integer.to_string()
  end

  defp failed_run_ids(entries) do
    entries
    |> Enum.filter(&(&1.job_status == "failed"))
    |> Enum.map(& &1.replacement_run)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp missing_job_count(entries) do
    entries
    |> Enum.count(&(&1.job_status == "missing"))
    |> Integer.to_string()
  end

  defp missing_run_ids(entries) do
    entries
    |> Enum.filter(&(&1.job_status == "missing"))
    |> Enum.map(& &1.replacement_run)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp missing_summary(entries) do
    entries
    |> Enum.filter(&(&1.job_status == "missing"))
    |> Enum.map_join("; ", fn entry ->
      "#{entry.replacement_run} #{entry.stage} next #{entry.next_action} #{entry.job_action}"
    end)
  end

  defp replacement_job_id(%{job_id: job_id}) when is_binary(job_id) and job_id != "",
    do: job_id

  defp replacement_job_id(_entry), do: "job-missing"

  defp replacement_job_action(%{job_status: "running", job_age_state: "stale"}),
    do: "inspect_stale_replacement_job"

  defp replacement_job_action(%{job_status: "queued"}),
    do: "wait_for_replacement_job_start"

  defp replacement_job_action(%{job_status: "running"}),
    do: "monitor_running_replacement_job"

  defp replacement_job_action(%{job_status: "failed"}),
    do: "inspect_failed_replacement_job"

  defp replacement_job_action(%{job_status: "missing"}),
    do: "inspect_missing_replacement_job"

  defp replacement_job_action(%{job_status: "completed", next_action: "done"}),
    do: "replacement_complete"

  defp replacement_job_action(%{job_status: "completed"}),
    do: "advance_replacement_request"

  defp replacement_job_action(%{next_action: next_action})
       when is_binary(next_action) and next_action != "",
       do: "advance_replacement_request"

  defp replacement_job_action(_entry), do: "inspect_replacement_request"

  defp job_items_by_run(workflow_context) do
    workflow_context
    |> Map.get(:request_group_job_items)
    |> job_item_entries()
    |> Map.new(&{&1.run, &1})
  end

  defp job_item_entries(value) when is_binary(value) do
    value
    |> items()
    |> Enum.map(&job_item_entry/1)
  end

  defp job_item_entries(_value), do: []

  defp job_item_entry(item) do
    captures =
      Regex.named_captures(
        ~r/^(?:(?<index>\d+):)?(?<source>.+?) (?<run>\S+) (?<status>queued|running|failed|completed|missing) (?<job_id>\S+)(?: (?<attrs>.*))?$/,
        item
      )

    if captures do
      attrs = job_item_attrs(Map.get(captures, "attrs"))

      %{
        raw: item,
        index: Map.get(captures, "index"),
        source: Map.get(captures, "source"),
        run: Map.get(captures, "run"),
        status: Map.get(captures, "status"),
        job_id: Map.get(captures, "job_id"),
        event_id: Map.get(attrs, "event"),
        started_at: Map.get(attrs, "started"),
        completed_at: Map.get(attrs, "completed")
      }
    else
      empty_job_item(item)
    end
  end

  defp empty_job_item(raw \\ "") do
    %{
      raw: raw,
      index: "",
      source: "",
      run: "",
      status: "",
      job_id: "",
      event_id: "",
      started_at: "",
      completed_at: ""
    }
  end

  defp job_item_attrs(nil), do: %{}
  defp job_item_attrs(""), do: %{}

  defp job_item_attrs(attrs) when is_binary(attrs) do
    attrs
    |> String.split(" ", trim: true)
    |> Enum.reduce(%{}, fn token, parsed ->
      case String.split(token, "=", parts: 2) do
        [key, value] -> Map.put(parsed, key, value)
        _other -> parsed
      end
    end)
  end

  defp replacement_job_age_state(%{status: "running", started_at: started_at}, now)
       when is_binary(started_at) and started_at != "" do
    case DateTime.from_iso8601(started_at) do
      {:ok, started_at, _offset} ->
        if DateTime.diff(now, started_at, :second) >= @stale_replacement_job_seconds do
          "stale"
        else
          "active"
        end

      {:error, _reason} ->
        "unknown"
    end
  end

  defp replacement_job_age_state(%{status: status}, _now)
       when status in ["queued", "running"],
       do: "active"

  defp replacement_job_age_state(_job_item, _now), do: ""

  defp unresolved(workflow_context) do
    failed = integer_value(Map.get(workflow_context, :request_group_failed))
    resolved = integer_value(Map.get(workflow_context, :request_group_resolved_failed))

    failed
    |> Kernel.-(resolved)
    |> max(0)
    |> Integer.to_string()
  end

  defp correction_task_count(workflow_context) do
    workflow_context
    |> Map.get(:request_group_correction_tasks)
    |> items()
    |> length()
    |> Integer.to_string()
  end

  defp retry_count(workflow_context, workflow_controls) do
    case action_value(Map.get(workflow_controls, :group_retry_action), :eligible_count) do
      count when is_integer(count) ->
        Integer.to_string(count)

      count when is_binary(count) and count != "" ->
        count

      _other ->
        Map.get(workflow_context, :request_group_retryable_failed) || "0"
    end
  end

  defp active_group_job_count(workflow_context) do
    workflow_context
    |> group_job_status_counts()
    |> Map.take(["queued", "running"])
    |> Map.values()
    |> Enum.sum()
  end

  defp blocked_group_job_count(workflow_context) do
    workflow_context
    |> group_job_status_counts()
    |> Map.take(["failed", "missing"])
    |> Map.values()
    |> Enum.sum()
  end

  defp group_job_status_counts(workflow_context) when is_map(workflow_context) do
    workflow_context
    |> Map.get(:request_group_job_progress)
    |> group_job_status_counts()
  end

  defp group_job_status_counts(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, fn status_count, counts ->
      case status_count |> String.trim() |> String.split(" ", trim: true) do
        [status, count] -> Map.put(counts, status, integer_value(count))
        _other -> counts
      end
    end)
  end

  defp group_job_status_counts(_value), do: %{}

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> 0
    end
  end

  defp integer_value(_value), do: 0

  defp positive_text?(value), do: integer_value(value) > 0

  defp action_value(action, key) when is_map(action), do: Map.get(action, key)
  defp action_value(_action, _key), do: nil

  defp action_eligible?(action) when is_map(action), do: Map.get(action, :eligible?) == true
  defp action_eligible?(_action), do: false

  defp bool_attr(true), do: "true"
  defp bool_attr(_value), do: "false"

  defp truthy?(true), do: true
  defp truthy?(_value), do: false

  defp pluralized(count, singular, plural) do
    if integer_value(count) == 1, do: singular, else: plural
  end

  defp items(value) when is_list(value), do: value

  defp items(value) when is_binary(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp items(_value), do: []

  defp present_text?(value), do: is_binary(value) and value != ""
end
