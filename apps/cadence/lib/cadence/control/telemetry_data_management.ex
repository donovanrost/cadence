defmodule Cadence.Control.TelemetryDataManagement do
  @moduledoc """
  Command boundary for governed telemetry correction and historical-data workflows.

  Presentation layers call this facade instead of depending on workflow
  implementation modules or storage details.
  """

  alias Cadence.Telemetry.DataManagement

  defdelegate record_historical_data_workflow_event(workflow, stage, attrs, opts),
    to: DataManagement

  defdelegate record_historical_data_workflow_request(workflow, attrs, point_ids, opts),
    to: DataManagement

  defdelegate record_historical_data_workflow_correction_request(
                workflow,
                attrs,
                correction,
                opts
              ),
              to: DataManagement

  defdelegate record_historical_data_workflow_stage_transition(
                workflow,
                stage,
                source_event_id,
                attrs,
                opts
              ),
              to: DataManagement

  defdelegate record_historical_data_workflow_group_transition(
                workflow,
                stage,
                request_group_id,
                attrs,
                opts
              ),
              to: DataManagement

  defdelegate start_historical_data_workflow_job(workflow, attrs, opts), to: DataManagement

  defdelegate retry_historical_data_workflow_job(job_id, event_id, attrs, opts),
    to: DataManagement

  defdelegate retry_historical_data_workflow_group_failed_jobs(request_group_id, attrs, opts),
    to: DataManagement

  defdelegate record_historical_data_workflow_missing_replacement_inspection(
                request_group_id,
                replacement_run_id,
                attrs,
                opts
              ),
              to: DataManagement

  defdelegate record_historical_data_workflow_stale_replacement_inspection(
                job_id,
                event_id,
                attrs,
                opts
              ),
              to: DataManagement

  defdelegate requeue_historical_data_workflow_stale_replacement_job(
                job_id,
                event_id,
                attrs,
                opts
              ),
              to: DataManagement

  defdelegate apply_observation_identity_decision(identity_id, decision, attrs, opts),
    to: DataManagement

  defdelegate apply_observation_identity_decisions(items, decision, attrs, opts),
    to: DataManagement

  defdelegate record_late_data_policy_decision(decision, attrs, opts), to: DataManagement
  defdelegate execute_late_data_policy(decision, attrs, opts), to: DataManagement
end
