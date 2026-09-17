defmodule Cadence.Activations.ApprovalAdmission do
  @moduledoc "Checks durable approval and current requirements inside the activation transaction."
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations

  def lock_and_admit(%{activation_request_id: id} = attrs) when is_binary(id) do
    ActivationPolicy.with_lock(attrs.organization_id, fn ->
      with {:ok, approved} <- Activations.fetch_approved(id),
           true <- approved.organization_id == attrs.organization_id,
           true <- approved.mission_id == attrs.mission_id,
           true <- approved.binding_set_id == attrs.binding_set_id,
           true <- approved.binding_set_version == attrs.binding_set_version,
           true <- approved.binding_set_content_sha256 == attrs.binding_set_content_sha256,
           true <- approved.metadata == attrs.metadata,
           :ok <-
             ActivationPolicy.validate(
               attrs.organization_id,
               attrs.mission_id,
               approved.policy_document
             ) do
        {:ok, :approved}
      else
        false -> {:error, :approved_activation_content_mismatch}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def lock_and_admit(%{metadata: %{"spacecraft_configuration_version" => _}}),
    do: {:error, :activation_approval_required}

  # Retained internal bootstrap callers do not represent a spacecraft review.
  def lock_and_admit(%{activation_request_id: nil}), do: {:ok, :internal_basis}
end
