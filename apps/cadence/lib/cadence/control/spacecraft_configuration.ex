defmodule Cadence.Control.SpacecraftConfiguration do
  @moduledoc "Explicit human submission and direct activation of a spacecraft revision; a review is decided from the activation."
  alias Cadence.Applications.SpacecraftConfiguration.Review
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Management.Activations
  alias Cadence.Platform.ScopedReadUpdates

  def submit(scope, mission_id, spacecraft_id, token, policy_token, intent)
      when intent in [:review, :activate] and is_binary(policy_token) and is_binary(token) and
             is_binary(mission_id) and is_binary(spacecraft_id) do
    with {:ok, request} <-
           Review.request(scope, mission_id, spacecraft_id, token,
             expected_policy_token: policy_token,
             expected_approval_required: intent == :review
           ) do
      complete_submission(scope, mission_id, request, intent)
    end
  end

  def submit(_, _, _, _, _, _), do: {:error, :invalid_activation_decision}

  defp complete_submission(_scope, _mission, request, :review),
    do: {:ok, %{state: "approval_pending", request_id: request.activation_request_id}}

  defp complete_submission(scope, mission_id, request, :activate) do
    result =
      with {:ok, approved} <- Activations.fetch_approved(request.activation_request_id),
           do: apply_direct(approved)

    ScopedReadUpdates.publish(
      :spacecraft_configuration_changed,
      scope.organization_id,
      mission_id
    )

    result
  end

  defp apply_direct(approved) do
    case ControlActivations.execute(approved) do
      {:ok, execution} ->
        {:ok, %{state: "active", execution_id: execution.activation_execution_id}}

      {:error, reason}
      when reason in [
             :activation_policy_changed,
             :spacecraft_configuration_changed,
             :spacecraft_configuration_review_stale
           ] ->
        {:error, reason}

      {:error, _} ->
        {:ok, %{"outcome" => "application_needs_review"}}
    end
  rescue
    _ -> {:ok, %{"outcome" => "application_needs_review"}}
  end
end
