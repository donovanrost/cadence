defmodule Cadence.Reads.MissionModels.ActiveBasis do
  @moduledoc """
  Read-only adaptation of the active Control generation into model evidence.

  Authoring receives bounded immutable command artifacts and an exact generation
  token while the Control owner's read lock remains held through the callback.
  This adapter exposes no activation mutation or runtime process operation.
  """

  alias Cadence.Activations
  alias Cadence.Commanding.AuthoringIdentity
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Runtime.MissionModelPlanDecoder

  def with_command_catalog(organization_id, mission_id, operation) do
    Activations.with_locked_command_basis(organization_id, mission_id, fn activation ->
      with {:ok, basis} <- MissionModelPromotion.command_authoring_basis(activation),
           {:ok, catalog} <-
             MissionModelPlanDecoder.command_authoring_catalog(basis.runtime_plans) do
        snapshot = %{
          basis: basis,
          catalog: catalog,
          activation_id: activation.activation_id,
          generation: activation.generation,
          token: AuthoringIdentity.digest({activation, basis.runtime_plans.command})
        }

        operation.(snapshot)
      end
    end)
  end

  def fetch_runtime_basis(organization_id, mission_id) do
    with {:ok, activation} <- Activations.fetch_active_activation(organization_id, mission_id),
         do: MissionModelPromotion.runtime_basis(activation)
  end

  def active_revision_id(organization_id, mission_id) do
    case Activations.fetch_active_activation(organization_id, mission_id) do
      {:ok, activation} -> get_in(activation.metadata, ["mission_model", "revision_id"])
      {:error, :no_active_binding_set} -> nil
    end
  end
end
