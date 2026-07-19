defmodule Cadence.Dashboards.DataLinkResolver.BackfillLifecycleRows do
  @moduledoc """
  Builds telemetry backfill lifecycle inspector rows and group progress.
  """

  import Cadence.Dashboards.DataLinkResolver.Support

  alias Cadence.Jobs
  alias Cadence.Telemetry.Storage, as: TelemetryStorage
  alias Cadence.Telemetry.Storage.BackfillLifecycleGroup

  @spec rows(struct(), binary(), binary()) :: [map() | nil]
  def rows(event, organization_id, mission_id) do
    [
      row("Backfill lifecycle event", event.backfill_lifecycle_event_id),
      row("Backfill run", event.backfill_run_id),
      row("Event type", event.event_type),
      row("Workflow", payload_value(event.payload, :workflow)),
      row("Workflow stage", payload_value(event.payload, :stage)),
      row("Workflow run", payload_value(event.payload, :run_id)),
      row("Dashboard context", dashboard_context_value(event.payload, :dashboard_id)),
      row(
        "Dashboard context version",
        dashboard_context_value(event.payload, :dashboard_version)
      ),
      row(
        "Dashboard context time mode",
        dashboard_context_value(event.payload, :dashboard_time_mode)
      ),
      row(
        "Dashboard context replay run",
        dashboard_context_value(event.payload, :dashboard_replay_run_id)
      ),
      row(
        "Dashboard context data view",
        dashboard_context_value(event.payload, :dashboard_data_view)
      ),
      row(
        "Dashboard context limit mode",
        dashboard_context_value(event.payload, :dashboard_limit_mode)
      ),
      row(
        "Comparison review request",
        comparison_review_origin_value(event.payload, :request_event_id)
      ),
      row(
        "Comparison review kind",
        comparison_review_origin_value(event.payload, :request_kind)
      ),
      row(
        "Comparison review open count",
        comparison_review_origin_value(event.payload, :open_count)
      ),
      row(
        "Comparison review placements",
        comparison_review_origin_value(event.payload, :open_placement_ids)
      ),
      row(
        "Comparison review workflow kind",
        comparison_review_origin_value(event.payload, :workflow_kind)
      ),
      row(
        "Comparison review workflow action",
        comparison_review_origin_value(event.payload, :workflow_action)
      ),
      row(
        "Comparison review workflow selection kind",
        comparison_review_origin_value(event.payload, :workflow_selection_kind)
      ),
      row(
        "Comparison review workflow selection count",
        comparison_review_origin_value(event.payload, :workflow_selection_count)
      ),
      row(
        "Comparison review primary data view",
        comparison_review_origin_value(event.payload, :primary_data_view)
      ),
      row(
        "Comparison review compare data view",
        comparison_review_origin_value(event.payload, :compare_data_view)
      ),
      row(
        "Comparison review scope kind",
        comparison_review_origin_value(event.payload, :scope_kind)
      ),
      row(
        "Comparison review scope ids",
        comparison_review_origin_value(event.payload, :scope_ids)
      ),
      row(
        "Comparison review contact ids",
        comparison_review_origin_value(event.payload, :contact_ids)
      ),
      row(
        "Comparison review resource ids",
        comparison_review_origin_value(event.payload, :resource_ids)
      ),
      row(
        "Comparison review transport ids",
        comparison_review_origin_value(event.payload, :transport_ids)
      ),
      row(
        "Comparison review source endpoint ids",
        comparison_review_origin_value(event.payload, :source_endpoint_ids)
      ),
      row(
        "Comparison review ground station ids",
        comparison_review_origin_value(event.payload, :ground_station_ids)
      ),
      row(
        "Comparison review scope link ids",
        comparison_review_origin_value(event.payload, :scope_link_ids)
      ),
      row("Request mode", payload_value(event.payload, :request_mode)),
      row("Request group", payload_value(event.payload, :request_group_id)),
      row("Request item", request_item(event.payload)),
      row("Occurred", event.occurred_at),
      row("Realm", event.realm),
      row("Replay run", event.replay_run_id),
      row("Data source", event.data_source_id),
      row("Source binding", event.binding_id),
      row("Observable", event.observable_id),
      row("Point", event.point_id),
      row("Spacecraft", event.spacecraft_id),
      row("Source from", event.source_from),
      row("Source to", event.source_to),
      row("Receipt from", event.receipt_from),
      row("Receipt to", event.receipt_to),
      row("Sample count", event.sample_count),
      row("Authority", event.authority),
      row("Reason", event.reason),
      row("Actor", event.actor_id),
      row("Actor kind", event.actor_kind),
      row("Payload", event.payload)
    ]
    |> Kernel.++(group_rows(event, organization_id, mission_id))
    |> Kernel.++(failure_rows(event))
    |> Kernel.++(retry_rows(event))
    |> Kernel.++(missing_replacement_rows(event))
    |> Kernel.++(stale_replacement_rows(event))
    |> Kernel.++(correction_rows(event))
    |> Kernel.++(late_data_policy_rows(event))
    |> Kernel.++(job_rows(event))
  end

  defp group_rows(event, organization_id, mission_id) do
    case payload_value(event.payload, :request_group_id) do
      group_id when is_binary(group_id) and group_id != "" ->
        lifecycle_events =
          mission_id
          |> TelemetryStorage.list_backfill_lifecycle_events(
            organization_id: organization_id,
            limit: 1_000
          )

        group_events =
          Enum.filter(
            lifecycle_events,
            &(payload_value(&1.payload, :request_group_id) == group_id)
          )

        group =
          BackfillLifecycleGroup.summary(group_events, lifecycle_events,
            retry_ready_fun: &group_retry_ready?/1
          )

        [
          row("Request group state", group.state),
          row("Request group terminal", group.terminal?),
          row("Request group size", group.size),
          row("Request group progress", group.progress),
          row("Request group job progress", group_job_progress(group_events)),
          row("Request group job items", group_job_items(group_events)),
          row("Request group retried items", group_retried_items(group_events)),
          row("Request group corrected items", group_corrected_items(group_events)),
          row("Request group correction tasks", group_correction_tasks(group_events)),
          row("Request group requested", group.requested),
          row("Request group approved", group.approved),
          row("Request group started", group.started),
          row("Request group completed", group.completed),
          row("Request group failed", group.failed),
          row("Request group resolved failed", group.resolved_failed),
          row("Request group retry resolved", group.retry_resolved),
          row("Request group correction requested", group.correction_requested),
          row("Request group correction started", group.correction_started),
          row("Request group correction completed", group.correction_completed),
          row("Request group correction superseded", group.correction_superseded),
          row("Request group request eligible", group.request_eligible),
          row("Request group approve eligible", group.approve_eligible),
          row("Request group reject eligible", group.reject_eligible),
          row("Request group start eligible", group.start_eligible),
          row("Request group complete eligible", group.complete_eligible),
          row("Request group fail eligible", group.fail_eligible),
          row("Request group retryable failed", group.retryable_failed),
          row("Request group nonretryable failed", group.nonretryable_failed),
          row("Request group failed items", group.failed_items),
          row("Request group failed item events", group.failed_item_events)
        ]

      _other ->
        []
    end
  end

  defp failure_rows(event) do
    source = payload_value(event.payload, :source)
    failure = state_value(source, :failure)
    source_window = state_value(source, :source_window)
    source_identity = state_value(source, :source_identity)

    [
      row("Workflow failure code", state_value(failure, :code)),
      row("Workflow failure detail", state_value(failure, :detail)),
      row("Workflow retryable", state_value(failure, :retryable)),
      row("Workflow retry blockers", state_value(failure, :retry_blockers)),
      row("Workflow recovery action", state_value(failure, :recovery_action)),
      row("Workflow source point", state_value(source, :point_id)),
      row("Workflow source realm", state_value(source_identity, :realm)),
      row("Workflow source replay run", state_value(source_identity, :replay_run_id)),
      row("Workflow source data source", state_value(source_identity, :data_source_id)),
      row("Workflow source binding", state_value(source_identity, :source_binding_id)),
      row("Workflow source from", state_value(source_window, :from_observed_at)),
      row("Workflow source to", state_value(source_window, :to_observed_at)),
      row("Workflow receipt from", state_value(source_window, :from_receipt_time)),
      row("Workflow receipt to", state_value(source_window, :to_receipt_time)),
      row("Workflow source limit", state_value(source, :source_limit))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp group_job_progress(group_events) when is_list(group_events) do
    statuses =
      group_events
      |> group_job_item_details()
      |> Enum.map(&Map.fetch!(&1, :job_status))

    if statuses == [] do
      nil
    else
      statuses
      |> Enum.frequencies()
      |> Enum.sort_by(fn {status, _count} -> group_job_status_order(status) end)
      |> Enum.map_join(", ", fn {status, count} -> "#{status} #{count}" end)
    end
  end

  defp group_job_items(group_events) when is_list(group_events) do
    group_events
    |> group_job_item_details()
    |> case do
      [] ->
        nil

      details ->
        Enum.map_join(details, "; ", fn detail ->
          [
            detail.item_label,
            detail.run_id,
            detail.job_status,
            detail.job_id,
            job_text_token("event", detail.event_id),
            job_time_token("started", detail.job_started_at),
            job_time_token("completed", detail.job_completed_at)
          ]
          |> Enum.reject(&blank_text?/1)
          |> Enum.join(" ")
        end)
    end
  end

  defp group_job_item_details(group_events) when is_list(group_events) do
    requested_events = BackfillLifecycleGroup.effective_requested_events(group_events)
    effective_events = BackfillLifecycleGroup.effective_events(group_events)
    latest_event_by_item = BackfillLifecycleGroup.latest_event_by_item(effective_events)

    requested_events
    |> Enum.sort_by(&group_item_sort_key/1)
    |> Enum.map(fn requested_event ->
      item_key = BackfillLifecycleGroup.item_key(requested_event)
      latest_event = Map.get(latest_event_by_item, item_key, requested_event)
      run_id = latest_event.backfill_run_id || requested_event.backfill_run_id
      job = group_job(run_id)

      %{
        item_label: group_item_label(latest_event, requested_event),
        event_id: latest_event.backfill_lifecycle_event_id,
        run_id: run_id,
        job_id: group_job_id(job),
        job_status: group_job_status(job),
        job_started_at: group_job_started_at(job),
        job_completed_at: group_job_completed_at(job)
      }
    end)
  end

  defp group_item_sort_key(event) do
    {payload_value(event.payload, :request_item_index) || 0,
     event.point_id || event.observable_id || event.backfill_run_id}
  end

  defp group_item_label(latest_event, requested_event) do
    index =
      payload_value(latest_event.payload, :request_item_index) ||
        payload_value(requested_event.payload, :request_item_index)

    point =
      latest_event.point_id ||
        latest_event.observable_id ||
        requested_event.point_id ||
        requested_event.observable_id ||
        latest_event.backfill_run_id ||
        requested_event.backfill_run_id

    [index, point]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp group_job_id({:ok, job}), do: job.job_id
  defp group_job_id({:error, _reason}), do: nil

  defp group_job_status({:ok, job}), do: Atom.to_string(job.status)
  defp group_job_status({:error, _reason}), do: "missing"

  defp group_job_started_at({:ok, job}), do: job.started_at
  defp group_job_started_at({:error, _reason}), do: nil

  defp group_job_completed_at({:ok, job}), do: job.completed_at
  defp group_job_completed_at({:error, _reason}), do: nil

  defp job_time_token(_label, nil), do: nil
  defp job_time_token(label, %DateTime{} = value), do: "#{label}=#{DateTime.to_iso8601(value)}"

  defp job_text_token(_label, nil), do: nil
  defp job_text_token(_label, ""), do: nil
  defp job_text_token(label, value) when is_binary(value), do: "#{label}=#{value}"

  defp group_job(run_id) when is_binary(run_id) and run_id != "" do
    Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run_id)
  end

  defp group_job(_run_id), do: {:error, :missing_run_id}

  defp group_job_status_order("queued"), do: {0, "queued"}
  defp group_job_status_order("running"), do: {1, "running"}
  defp group_job_status_order("completed"), do: {2, "completed"}
  defp group_job_status_order("failed"), do: {3, "failed"}
  defp group_job_status_order("missing"), do: {4, "missing"}
  defp group_job_status_order(status), do: {5, status}

  defp blank_text?(nil), do: true
  defp blank_text?(""), do: true
  defp blank_text?(_value), do: false

  defp group_retried_items(group_events) when is_list(group_events) do
    group_resolution_items(group_events, :retry_source_event_id, &group_retry_item/2)
  end

  defp group_corrected_items(group_events) when is_list(group_events) do
    group_resolution_items(group_events, :corrects_event_id, &group_correction_item/2)
  end

  defp group_correction_tasks(group_events) when is_list(group_events) do
    group_resolution_items(group_events, :corrects_event_id, &group_correction_task_item/2)
  end

  defp group_resolution_items(group_events, source_key, format_fun) do
    source_failed_event_by_id =
      group_events
      |> Enum.filter(&(payload_value(&1.payload, :stage) == "failed"))
      |> Map.new(&{&1.backfill_lifecycle_event_id, &1})

    group_events
    |> Enum.reduce(%{}, fn event, latest_event_by_source_id ->
      source_event_id = payload_value(event.payload, source_key)

      if Map.has_key?(source_failed_event_by_id, source_event_id) do
        Map.put(latest_event_by_source_id, source_event_id, event)
      else
        latest_event_by_source_id
      end
    end)
    |> Map.values()
    |> Enum.sort_by(fn event ->
      source_event_id = payload_value(event.payload, source_key)
      source_event = Map.fetch!(source_failed_event_by_id, source_event_id)
      group_item_sort_key(source_event)
    end)
    |> Enum.map(fn event ->
      source_event_id = payload_value(event.payload, source_key)
      source_event = Map.fetch!(source_failed_event_by_id, source_event_id)
      format_fun.(source_event, event)
    end)
    |> case do
      [] -> nil
      items -> Enum.join(items, "; ")
    end
  end

  defp group_retry_item(source_event, retry_event) do
    [
      group_resolution_item_label(source_event),
      source_event.backfill_run_id,
      "retried",
      payload_value(retry_event.payload, :retry_job_status),
      payload_value(retry_event.payload, :retry_job_id)
    ]
    |> Enum.reject(&blank_text?/1)
    |> Enum.join(" ")
  end

  defp group_correction_item(source_event, correction_event) do
    [
      group_resolution_item_label(source_event),
      source_event.backfill_run_id,
      "corrected",
      correction_event.backfill_run_id,
      payload_value(correction_event.payload, :stage),
      payload_value(correction_event.payload, :corrects_job_id)
    ]
    |> Enum.reject(&blank_text?/1)
    |> Enum.join(" ")
  end

  defp group_correction_task_item(source_event, correction_event) do
    stage = payload_value(correction_event.payload, :stage)

    [
      group_resolution_item_label(source_event),
      source_event.backfill_run_id,
      "replacement",
      correction_event.backfill_run_id,
      "stage",
      stage,
      "next",
      correction_next_action(stage)
    ]
    |> Enum.reject(&blank_text?/1)
    |> Enum.join(" ")
  end

  defp correction_next_action("requested"), do: "approve"
  defp correction_next_action("approved"), do: "start"
  defp correction_next_action("started"), do: "complete"
  defp correction_next_action("retried"), do: "complete"
  defp correction_next_action("completed"), do: "done"
  defp correction_next_action("failed"), do: "review"
  defp correction_next_action(_stage), do: "inspect"

  defp group_resolution_item_label(event) do
    event.point_id || event.observable_id || event.backfill_run_id
  end

  defp retry_rows(event) do
    [
      row("Workflow retry action", payload_value(event.payload, :retry_action)),
      row("Workflow retry source event", payload_value(event.payload, :retry_source_event_id)),
      row(
        "Workflow retry source event type",
        payload_value(event.payload, :retry_source_event_type)
      ),
      row("Workflow retry job", payload_value(event.payload, :retry_job_id)),
      row("Workflow retry job status", payload_value(event.payload, :retry_job_status))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp missing_replacement_rows(event) do
    [
      row(
        "Missing replacement action",
        payload_value(event.payload, :missing_replacement_action)
      ),
      row(
        "Missing replacement source event",
        payload_value(event.payload, :missing_replacement_source_event_id)
      ),
      row(
        "Missing replacement source event type",
        payload_value(event.payload, :missing_replacement_source_event_type)
      ),
      row("Missing replacement run", payload_value(event.payload, :missing_replacement_run_id)),
      row(
        "Missing replacement expected job type",
        payload_value(event.payload, :missing_replacement_expected_job_type)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp stale_replacement_rows(event) do
    [
      row("Stale replacement action", payload_value(event.payload, :stale_replacement_action)),
      row(
        "Stale replacement source event",
        payload_value(event.payload, :stale_replacement_source_event_id)
      ),
      row(
        "Stale replacement source event type",
        payload_value(event.payload, :stale_replacement_source_event_type)
      ),
      row("Stale replacement run", payload_value(event.payload, :stale_replacement_run_id)),
      row("Stale replacement job", payload_value(event.payload, :stale_replacement_job_id)),
      row(
        "Stale replacement job status",
        payload_value(event.payload, :stale_replacement_job_status)
      ),
      row(
        "Stale replacement job started",
        payload_value(event.payload, :stale_replacement_job_started_at)
      ),
      row(
        "Stale replacement job age seconds",
        payload_value(event.payload, :stale_replacement_job_age_seconds)
      ),
      row(
        "Stale replacement stale after seconds",
        payload_value(event.payload, :stale_replacement_stale_after_seconds)
      ),
      row(
        "Stale replacement requeued job",
        payload_value(event.payload, :stale_replacement_requeued_job_id)
      ),
      row(
        "Stale replacement requeued job status",
        payload_value(event.payload, :stale_replacement_requeued_job_status)
      ),
      row(
        "Stale replacement requeued job attempts",
        payload_value(event.payload, :stale_replacement_requeued_job_attempt_count)
      ),
      row(
        "Stale replacement requeued reason",
        payload_value(event.payload, :stale_replacement_requeued_failure_reason)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp correction_rows(event) do
    [
      row("Workflow correction action", payload_value(event.payload, :recovery_action)),
      row("Workflow correction source", payload_value(event.payload, :correction_source)),
      row(
        "Workflow correction source event type",
        payload_value(event.payload, :correction_source_event_type)
      ),
      row("Workflow correction source run", payload_value(event.payload, :corrects_run_id)),
      row("Workflow correction source event", payload_value(event.payload, :corrects_event_id)),
      row("Workflow correction source job", payload_value(event.payload, :corrects_job_id))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp late_data_policy_rows(event) do
    [
      row("Late data policy decision", payload_value(event.payload, :policy_decision)),
      row("Late data execution mode", payload_value(event.payload, :execution_mode)),
      row("Late data source event", payload_value(event.payload, :source_event_id)),
      row("Late data source event type", payload_value(event.payload, :source_event_type)),
      row("Late data selected samples", payload_value(event.payload, :selected_sample_count)),
      row("Late data write validity", payload_value(event.payload, :write_validity_state)),
      row("Late data current projection", payload_value(event.payload, :record_current_values)),
      row("Late data latest refresh", payload_value(event.payload, :refresh_latest_value)),
      row("Late data projection effect", payload_value(event.payload, :projection_effect))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp job_rows(event) do
    with run_id when is_binary(run_id) and run_id != "" <- workflow_run_id(event),
         {:ok, %Jobs.Job{} = job} <-
           Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run_id) do
      [
        row("Workflow job", job.job_id),
        row("Workflow job status", job.status),
        row("Workflow job attempts", job.attempt_count),
        row("Workflow job started", job.started_at),
        row("Workflow job completed", job.completed_at),
        row("Workflow job failure", job.failure_reason)
      ]
    else
      _other -> missing_job_rows(event)
    end
  end

  defp missing_job_rows(%{event_type: event_type})
       when event_type in [
              :backfill_missing_replacement_inspected,
              :import_missing_replacement_inspected
            ] do
    [row("Workflow job status", "missing")]
  end

  defp missing_job_rows(_event), do: []

  defp workflow_run_id(event) do
    payload_value(event.payload, :run_id) || event.backfill_run_id
  end

  defp request_item(payload) do
    case {payload_value(payload, :request_item_index),
          payload_value(payload, :request_item_count)} do
      {nil, _count} -> nil
      {_index, nil} -> nil
      {index, count} -> "#{index}/#{count}"
    end
  end

  defp group_retryable?(event) do
    failure =
      event.payload
      |> state_value(:source)
      |> state_value(:failure)

    case state_value(failure, :recovery_action) do
      "correct_workflow_request" ->
        false

      _recovery_action ->
        case state_value(failure, :retryable) do
          false -> false
          "false" -> false
          _other -> true
        end
    end
  end

  defp group_retry_ready?(event) do
    group_retryable?(event) and group_job_failed?(event)
  end

  defp group_job_failed?(event) do
    with run_id when is_binary(run_id) and run_id != "" <- workflow_run_id(event),
         {:ok, %Jobs.Job{status: :failed}} <-
           Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run_id) do
      true
    else
      _other -> false
    end
  end

  defp payload_value(payload, key), do: state_value(payload, key)

  defp dashboard_context_value(payload, key) do
    payload
    |> state_value(:dashboard_context)
    |> state_value(key)
  end

  defp comparison_review_origin_value(payload, key) do
    payload
    |> state_value(:comparison_review_origin)
    |> state_value(key)
  end
end
