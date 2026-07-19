defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecovery.WorkProjection do
  @moduledoc false

  @stale_replacement_job_seconds 15 * 60

  def build(workflow_context, %DateTime{} = now) when is_map(workflow_context) do
    entries = replacement_work(workflow_context, now)

    %{
      entries: entries,
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
