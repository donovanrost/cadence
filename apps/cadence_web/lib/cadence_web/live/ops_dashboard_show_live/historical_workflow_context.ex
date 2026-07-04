defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowContext do
  @moduledoc false

  @type t :: %__MODULE__{
          event_id: String.t() | nil,
          event_type: String.t() | nil,
          workflow: String.t() | nil,
          stage: String.t() | nil,
          run_id: String.t() | nil,
          realm: String.t() | nil,
          data_source_id: String.t() | nil,
          source_binding_id: String.t() | nil,
          observable_id: String.t() | nil,
          point_id: String.t() | nil,
          source_from: String.t() | nil,
          source_to: String.t() | nil,
          dashboard_id: String.t() | nil,
          dashboard_version: String.t() | nil,
          dashboard_time_mode: String.t() | nil,
          dashboard_replay_run_id: String.t() | nil,
          dashboard_data_view: String.t() | nil,
          dashboard_limit_mode: String.t() | nil,
          comparison_review_request_event_id: String.t() | nil,
          comparison_review_request_kind: String.t() | nil,
          comparison_review_open_count: String.t() | nil,
          comparison_review_open_placement_ids: String.t() | nil,
          comparison_review_workflow_kind: String.t() | nil,
          comparison_review_workflow_action: String.t() | nil,
          comparison_review_workflow_selection_kind: String.t() | nil,
          comparison_review_workflow_selection_count: String.t() | nil,
          comparison_review_primary_data_view: String.t() | nil,
          comparison_review_compare_data_view: String.t() | nil,
          reason: String.t() | nil,
          request_mode: String.t() | nil,
          request_group_id: String.t() | nil,
          request_item: String.t() | nil,
          request_item_count: non_neg_integer(),
          job_id: String.t() | nil,
          job_status: String.t() | nil,
          job_attempts: String.t() | nil,
          job_failure: String.t() | nil,
          failure_code: String.t() | nil,
          retryable: String.t() | nil,
          retry_blockers: String.t() | nil,
          recovery_action: String.t() | nil,
          retry_source_event_id: String.t() | nil,
          retry_source_event_type: String.t() | nil,
          correction_source_event_id: String.t() | nil,
          correction_source_job_id: String.t() | nil,
          late_data_policy_decision: String.t() | nil,
          late_data_source_event_id: String.t() | nil,
          late_data_selected_samples: String.t() | nil,
          late_data_write_validity: String.t() | nil,
          late_data_current_projection: String.t() | nil,
          late_data_latest_refresh: String.t() | nil,
          late_data_projection_effect: String.t() | nil,
          source_point_id: String.t() | nil,
          source_realm: String.t() | nil,
          source_data_source_id: String.t() | nil,
          source_binding_id_override: String.t() | nil,
          source_from_override: String.t() | nil,
          source_to_override: String.t() | nil,
          request_group_state: String.t() | nil,
          request_group_terminal: String.t() | nil,
          request_group_size: String.t() | nil,
          request_group_progress: String.t() | nil,
          request_group_job_progress: String.t() | nil,
          request_group_job_items: String.t() | nil,
          request_group_retried_items: String.t() | nil,
          request_group_corrected_items: String.t() | nil,
          request_group_correction_tasks: String.t() | nil,
          request_group_requested: String.t() | nil,
          request_group_approved: String.t() | nil,
          request_group_started: String.t() | nil,
          request_group_completed: String.t() | nil,
          request_group_failed: String.t() | nil,
          request_group_resolved_failed: String.t() | nil,
          request_group_retry_resolved: String.t() | nil,
          request_group_correction_requested: String.t() | nil,
          request_group_correction_started: String.t() | nil,
          request_group_correction_completed: String.t() | nil,
          request_group_correction_superseded: String.t() | nil,
          request_group_request_eligible: String.t() | nil,
          request_group_approve_eligible: String.t() | nil,
          request_group_reject_eligible: String.t() | nil,
          request_group_start_eligible: String.t() | nil,
          request_group_complete_eligible: String.t() | nil,
          request_group_fail_eligible: String.t() | nil,
          request_group_retryable_failed: String.t() | nil,
          request_group_nonretryable_failed: String.t() | nil,
          request_group_failed_items: String.t() | nil,
          request_group_failed_item_events: String.t() | nil
        }

  # This mirrors the inspector row contract while downstream workflow presenters are still flat.
  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
  defstruct [
    :event_id,
    :event_type,
    :workflow,
    :stage,
    :run_id,
    :realm,
    :data_source_id,
    :source_binding_id,
    :observable_id,
    :point_id,
    :source_from,
    :source_to,
    :dashboard_id,
    :dashboard_version,
    :dashboard_time_mode,
    :dashboard_replay_run_id,
    :dashboard_data_view,
    :dashboard_limit_mode,
    :comparison_review_request_event_id,
    :comparison_review_request_kind,
    :comparison_review_open_count,
    :comparison_review_open_placement_ids,
    :comparison_review_workflow_kind,
    :comparison_review_workflow_action,
    :comparison_review_workflow_selection_kind,
    :comparison_review_workflow_selection_count,
    :comparison_review_primary_data_view,
    :comparison_review_compare_data_view,
    :reason,
    :request_mode,
    :request_group_id,
    :request_item,
    :job_id,
    :job_status,
    :job_attempts,
    :job_failure,
    :failure_code,
    :retryable,
    :retry_blockers,
    :recovery_action,
    :retry_source_event_id,
    :retry_source_event_type,
    :correction_source_event_id,
    :correction_source_job_id,
    :late_data_policy_decision,
    :late_data_source_event_id,
    :late_data_selected_samples,
    :late_data_write_validity,
    :late_data_current_projection,
    :late_data_latest_refresh,
    :late_data_projection_effect,
    :source_point_id,
    :source_realm,
    :source_data_source_id,
    :source_binding_id_override,
    :source_from_override,
    :source_to_override,
    :request_group_state,
    :request_group_terminal,
    :request_group_size,
    :request_group_progress,
    :request_group_job_progress,
    :request_group_job_items,
    :request_group_retried_items,
    :request_group_corrected_items,
    :request_group_correction_tasks,
    :request_group_requested,
    :request_group_approved,
    :request_group_started,
    :request_group_completed,
    :request_group_failed,
    :request_group_resolved_failed,
    :request_group_retry_resolved,
    :request_group_correction_requested,
    :request_group_correction_started,
    :request_group_correction_completed,
    :request_group_correction_superseded,
    :request_group_request_eligible,
    :request_group_approve_eligible,
    :request_group_reject_eligible,
    :request_group_start_eligible,
    :request_group_complete_eligible,
    :request_group_fail_eligible,
    :request_group_retryable_failed,
    :request_group_nonretryable_failed,
    :request_group_failed_items,
    :request_group_failed_item_events,
    request_item_count: 0
  ]

  @spec build(map() | term()) :: t()
  def build(inspector) when is_map(inspector) do
    rows = Map.get(inspector, :rows, [])
    event_type = row_value(rows, "Event type")
    request_item = row_value(rows, "Request item")

    %__MODULE__{
      event_id: row_value(rows, "Backfill lifecycle event"),
      event_type: event_type,
      workflow: row_value(rows, "Workflow") || workflow_from_event_type(event_type),
      stage: row_value(rows, "Workflow stage") || stage_from_event_type(event_type),
      run_id: row_value(rows, "Workflow run") || row_value(rows, "Backfill run"),
      realm: row_value(rows, "Realm"),
      data_source_id: row_value(rows, "Data source"),
      source_binding_id: row_value(rows, "Source binding"),
      observable_id: row_value(rows, "Observable"),
      point_id: row_value(rows, "Point"),
      source_from: row_value(rows, "Source from"),
      source_to: row_value(rows, "Source to"),
      dashboard_id: row_value(rows, "Dashboard context"),
      dashboard_version: row_value(rows, "Dashboard context version"),
      dashboard_time_mode: row_value(rows, "Dashboard context time mode"),
      dashboard_replay_run_id: row_value(rows, "Dashboard context replay run"),
      dashboard_data_view: row_value(rows, "Dashboard context data view"),
      dashboard_limit_mode: row_value(rows, "Dashboard context limit mode"),
      comparison_review_request_event_id: row_value(rows, "Comparison review request"),
      comparison_review_request_kind: row_value(rows, "Comparison review kind"),
      comparison_review_open_count: row_value(rows, "Comparison review open count"),
      comparison_review_open_placement_ids: row_value(rows, "Comparison review placements"),
      comparison_review_workflow_kind: row_value(rows, "Comparison review workflow kind"),
      comparison_review_workflow_action: row_value(rows, "Comparison review workflow action"),
      comparison_review_workflow_selection_kind:
        row_value(rows, "Comparison review workflow selection kind"),
      comparison_review_workflow_selection_count:
        row_value(rows, "Comparison review workflow selection count"),
      comparison_review_primary_data_view: row_value(rows, "Comparison review primary data view"),
      comparison_review_compare_data_view: row_value(rows, "Comparison review compare data view"),
      reason: row_value(rows, "Reason"),
      request_mode: row_value(rows, "Request mode"),
      request_group_id: row_value(rows, "Request group"),
      request_item: request_item,
      request_item_count: request_item_count(request_item),
      job_id: row_value(rows, "Workflow job"),
      job_status: row_value(rows, "Workflow job status"),
      job_attempts: row_value(rows, "Workflow job attempts"),
      job_failure: row_value(rows, "Workflow job failure"),
      failure_code: row_value(rows, "Workflow failure code"),
      retryable: row_value(rows, "Workflow retryable"),
      retry_blockers: row_value(rows, "Workflow retry blockers"),
      recovery_action: row_value(rows, "Workflow recovery action"),
      retry_source_event_id: row_value(rows, "Workflow retry source event"),
      retry_source_event_type: row_value(rows, "Workflow retry source event type"),
      correction_source_event_id: row_value(rows, "Workflow correction source event"),
      correction_source_job_id: row_value(rows, "Workflow correction source job"),
      late_data_policy_decision: row_value(rows, "Late data policy decision"),
      late_data_source_event_id: row_value(rows, "Late data source event"),
      late_data_selected_samples: row_value(rows, "Late data selected samples"),
      late_data_write_validity: row_value(rows, "Late data write validity"),
      late_data_current_projection: row_value(rows, "Late data current projection"),
      late_data_latest_refresh: row_value(rows, "Late data latest refresh"),
      late_data_projection_effect: row_value(rows, "Late data projection effect"),
      source_point_id: row_value(rows, "Workflow source point"),
      source_realm: row_value(rows, "Workflow source realm"),
      source_data_source_id: row_value(rows, "Workflow source data source"),
      source_binding_id_override: row_value(rows, "Workflow source binding"),
      source_from_override: row_value(rows, "Workflow source from"),
      source_to_override: row_value(rows, "Workflow source to"),
      request_group_state: row_value(rows, "Request group state"),
      request_group_terminal: row_value(rows, "Request group terminal"),
      request_group_size: row_value(rows, "Request group size"),
      request_group_progress: row_value(rows, "Request group progress"),
      request_group_job_progress: row_value(rows, "Request group job progress"),
      request_group_job_items: row_value(rows, "Request group job items"),
      request_group_retried_items: row_value(rows, "Request group retried items"),
      request_group_corrected_items: row_value(rows, "Request group corrected items"),
      request_group_correction_tasks: row_value(rows, "Request group correction tasks"),
      request_group_requested: row_value(rows, "Request group requested"),
      request_group_approved: row_value(rows, "Request group approved"),
      request_group_started: row_value(rows, "Request group started"),
      request_group_completed: row_value(rows, "Request group completed"),
      request_group_failed: row_value(rows, "Request group failed"),
      request_group_resolved_failed: row_value(rows, "Request group resolved failed"),
      request_group_retry_resolved: row_value(rows, "Request group retry resolved"),
      request_group_correction_requested: row_value(rows, "Request group correction requested"),
      request_group_correction_started: row_value(rows, "Request group correction started"),
      request_group_correction_completed: row_value(rows, "Request group correction completed"),
      request_group_correction_superseded: row_value(rows, "Request group correction superseded"),
      request_group_request_eligible: row_value(rows, "Request group request eligible"),
      request_group_approve_eligible: row_value(rows, "Request group approve eligible"),
      request_group_reject_eligible: row_value(rows, "Request group reject eligible"),
      request_group_start_eligible: row_value(rows, "Request group start eligible"),
      request_group_complete_eligible: row_value(rows, "Request group complete eligible"),
      request_group_fail_eligible: row_value(rows, "Request group fail eligible"),
      request_group_retryable_failed: row_value(rows, "Request group retryable failed"),
      request_group_nonretryable_failed: row_value(rows, "Request group nonretryable failed"),
      request_group_failed_items: row_value(rows, "Request group failed items"),
      request_group_failed_item_events: row_value(rows, "Request group failed item events")
    }
  end

  def build(_inspector), do: build(%{})

  defp row_value(rows, label) when is_list(rows) do
    rows
    |> Enum.find_value(fn
      %{label: ^label, value: value} -> empty_to_nil(value)
      %{"label" => ^label, "value" => value} -> empty_to_nil(value)
      _row -> nil
    end)
  end

  defp request_item_count(value) when is_binary(value) do
    case String.split(value, "/", parts: 2) do
      [_index, count] ->
        count
        |> Integer.parse()
        |> case do
          {count, ""} -> count
          _other -> 0
        end

      _other ->
        0
    end
  end

  defp request_item_count(_value), do: 0

  defp workflow_from_event_type("backfill_" <> _stage), do: "backfill"
  defp workflow_from_event_type("import_" <> _stage), do: "import"
  defp workflow_from_event_type(_event_type), do: nil

  defp stage_from_event_type("backfill_" <> stage), do: stage
  defp stage_from_event_type("import_" <> stage), do: stage
  defp stage_from_event_type(_event_type), do: nil

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
