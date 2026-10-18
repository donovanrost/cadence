defmodule Cadence.Control.Activations.Review do
  @moduledoc "Scoped human review of an exact activation request, independent of frontend delivery."
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Management.Activations

  def decide(scope, mission_id, input) do
    with :ok <- Activations.authorize_review(scope, mission_id),
         {:ok, id, reason, decision} <- validate(input),
         {:ok, request} <- Activations.fetch(scope, id),
         true <- request.mission_id == mission_id do
      execute(scope, id, reason, decision)
    else
      false -> {:error, :activation_request_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate(%{"activation_decision" => values, "decision" => decision} = input)
       when map_size(input) == 2 and is_map(values) and map_size(values) == 2 and
              decision in ["approved", "rejected"] do
    with %{"request_id" => id, "reason" => reason} <- values,
         true <- text?(id, 255) and text?(reason, 4096) do
      {:ok, id, String.trim(reason), decision}
    else
      _ -> {:error, :invalid_activation_decision}
    end
  end

  defp validate(_input), do: {:error, :invalid_activation_decision}

  defp text?(value, max),
    do:
      is_binary(value) and byte_size(value) in 1..max and String.valid?(value) and
        String.trim(value) != ""

  defp execute(scope, id, reason, "rejected") do
    with {:ok, request, decision} <- Activations.reject(scope, id, reason) do
      {:ok,
       %{
         "activationRequestId" => request.activation_request_id,
         "decision" => to_string(decision.decision),
         "state" => to_string(request.state),
         "outcome" => "rejected"
       }}
    end
  end

  defp execute(scope, id, reason, "approved") do
    with {:ok, request, _decision, approved} <- Activations.approve(scope, id, reason) do
      {:ok, apply_approved(request.activation_request_id, approved)}
    end
  end

  defp apply_approved(id, approved) do
    case ControlActivations.execute(approved) do
      {:ok, execution} ->
        %{
          "activationRequestId" => id,
          "activationExecutionId" => execution.activation_execution_id,
          "decision" => "approved",
          "state" => "approved",
          "status" => to_string(execution.status),
          "missionId" => execution.mission_id,
          "outcome" => "applied"
        }

      {:error, _reason} ->
        application_uncertain(id)
    end
  rescue
    _exception -> application_uncertain(id)
  catch
    _, _ -> application_uncertain(id)
  end

  defp application_uncertain(id),
    do: %{
      "activationRequestId" => id,
      "decision" => "approved",
      "state" => "approved",
      "outcome" => "application_needs_review"
    }
end
