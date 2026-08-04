defmodule Cadence.Reads.TelemetryDataManagement do
  @moduledoc """
  Read and policy boundary for governed telemetry data-management workflows.
  """

  alias Cadence.Telemetry.DataManagement

  defdelegate historical_data_workflow_action_policy(context), to: DataManagement
  defdelegate historical_data_workflow_stage_action_policy(context, stage), to: DataManagement

  defdelegate historical_data_workflow_group_stage_action_policy(context, stage),
    to: DataManagement

  defdelegate historical_data_workflow_explanation_summary(context), to: DataManagement
  defdelegate late_data_policy_execution_mode(attrs), to: DataManagement
end
