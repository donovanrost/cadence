defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobRecoveryPresentation do
  @moduledoc false

  @type action_attrs :: %{
          eligible: binary(),
          reason: binary() | nil,
          preview: binary() | nil,
          explanation: binary() | nil,
          state: binary() | nil,
          available_when: binary() | nil
        }

  @type retry_button :: %{
          present: boolean(),
          id: binary() | nil,
          eligible: binary(),
          reason: binary() | nil,
          preview: binary() | nil
        }

  @type correction_form :: %{
          present: boolean(),
          id: binary() | nil,
          eligible: binary(),
          reason: binary() | nil,
          preview: binary() | nil
        }

  @type t :: %__MODULE__{
          next_action: binary(),
          guidance: binary(),
          policy_state: binary() | nil,
          available_when: binary() | nil,
          retry_button: retry_button(),
          correction_form: correction_form(),
          retry: action_attrs(),
          correction: action_attrs()
        }

  defstruct next_action: "inspect_job",
            guidance: "Inspect the workflow job status and policy details before taking action.",
            policy_state: nil,
            available_when: nil,
            retry_button: %{
              present: false,
              id: nil,
              eligible: "false",
              reason: nil,
              preview: nil
            },
            correction_form: %{
              present: false,
              id: nil,
              eligible: "false",
              reason: nil,
              preview: nil
            },
            retry: %{
              eligible: "false",
              reason: nil,
              preview: nil,
              explanation: nil,
              state: nil,
              available_when: nil
            },
            correction: %{
              eligible: "false",
              reason: nil,
              preview: nil,
              explanation: nil,
              state: nil,
              available_when: nil
            }

  @spec build(map() | nil, map() | nil) :: t()
  def build(workflow_context, workflow_controls)
      when is_map(workflow_context) and is_map(workflow_controls) do
    retry = action_attrs(Map.get(workflow_controls, :job_retry_action))
    correction = action_attrs(Map.get(workflow_controls, :correction_request_action))
    next_action = next_action(workflow_context, workflow_controls)

    %__MODULE__{
      next_action: next_action,
      guidance: guidance_text(next_action, retry, correction),
      policy_state: retry.state || correction.state,
      available_when: retry.available_when || correction.available_when,
      retry_button: retry_button(workflow_controls),
      correction_form: correction_form(workflow_controls),
      retry: retry,
      correction: correction
    }
  end

  def build(_workflow_context, _workflow_controls), do: %__MODULE__{}

  defp next_action(workflow_context, workflow_controls) do
    cond do
      action_eligible?(Map.get(workflow_controls, :job_retry_action)) ->
        "retry_job"

      action_eligible?(Map.get(workflow_controls, :correction_request_action)) ->
        "create_corrected_request"

      Map.get(workflow_context, :job_status) in ["queued", "running"] ->
        "monitor_job"

      Map.get(workflow_context, :job_status) == "completed" ->
        "inspect_results"

      true ->
        "inspect_job"
    end
  end

  defp guidance_text("retry_job", retry, _correction) do
    retry.preview || "Retry this failed workflow job."
  end

  defp guidance_text("create_corrected_request", _retry, correction) do
    correction.preview || "Create a corrected request for this failed workflow job."
  end

  defp guidance_text("monitor_job", _retry, _correction) do
    "The workflow job is not terminal yet; monitor the worker outcome before recording recovery."
  end

  defp guidance_text("inspect_results", _retry, _correction) do
    "The workflow job completed; inspect the resulting lifecycle event and data changes."
  end

  defp guidance_text(_next_action, _retry, _correction) do
    "Inspect the workflow job status and policy details before taking action."
  end

  defp action_attrs(action) when is_map(action) do
    %{
      eligible: bool_attr(Map.get(action, :eligible?)),
      reason: Map.get(action, :reason),
      preview: Map.get(action, :preview),
      explanation: Map.get(action, :explanation),
      state: Map.get(action, :state_summary),
      available_when: Map.get(action, :available_when)
    }
  end

  defp action_attrs(_action) do
    %{
      eligible: "false",
      reason: nil,
      preview: nil,
      explanation: nil,
      state: nil,
      available_when: nil
    }
  end

  defp retry_button(workflow_controls) do
    action = Map.get(workflow_controls, :job_retry_action)

    %{
      present: Map.get(workflow_controls, :job_retryable) == true,
      id: action_value(action, :id),
      eligible: bool_attr(action_value(action, :eligible?)),
      reason: action_value(action, :reason),
      preview: action_value(action, :preview)
    }
  end

  defp correction_form(workflow_controls) do
    action = Map.get(workflow_controls, :correction_request_action)

    %{
      present: Map.get(workflow_controls, :correction_requestable) == true,
      id: action_value(action, :id),
      eligible: bool_attr(action_value(action, :eligible?)),
      reason: action_value(action, :reason),
      preview: action_value(action, :preview)
    }
  end

  defp action_eligible?(action) when is_map(action), do: Map.get(action, :eligible?) == true
  defp action_eligible?(_action), do: false

  defp action_value(action, key) when is_map(action), do: Map.get(action, key)
  defp action_value(_action, _key), do: nil

  defp bool_attr(true), do: "true"
  defp bool_attr(_value), do: "false"
end
