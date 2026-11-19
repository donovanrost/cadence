defmodule Cadence.Reads.MissionModels.ActiveBasis do
  @moduledoc """
  Read-only adaptation of the active Control generation into model evidence.

  Authoring receives bounded immutable command artifacts and an exact generation
  token while the Control owner's read lock remains held through the callback.
  This adapter exposes no activation mutation or runtime process operation.
  """

  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Control.SpacecraftModelBindings

  alias Cadence.Activations
  alias Cadence.Commanding.AuthoringIdentity
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Runtime.MissionModelPlanDecoder

  @doc "Reads the immutable active generation for saved-versus-active configuration comparison."
  def fetch_activation(organization_id, mission_id),
    do: Activations.fetch_active_activation(organization_id, mission_id)

  def with_command_catalog(organization_id, mission_id, operation) do
    Activations.with_locked_command_basis(organization_id, mission_id, fn activation ->
      with {:ok, snapshot} <- command_snapshot(activation), do: operation.(snapshot)
    end)
  end

  @doc """
  The same snapshot as `with_command_catalog/3`, read **without** the activation
  lock, for long read-only validation (group preflight). Its `token` identifies
  the generation, so a later locked step can check nothing changed in between.
  """
  def command_catalog_snapshot(organization_id, mission_id) do
    with {:ok, activation} <- Activations.fetch_active_activation(organization_id, mission_id),
         do: command_snapshot(activation)
  end

  defp command_snapshot(activation) do
    with {:ok, basis} <- MissionModelPromotion.command_authoring_basis(activation),
         {:ok, catalog} <- MissionModelPlanDecoder.command_authoring_catalog(basis.runtime_plans) do
      {:ok,
       %{
         basis: basis,
         catalog: catalog,
         activation_id: activation.activation_id,
         activation: activation,
         generation: activation.generation,
         token: AuthoringIdentity.digest({activation, basis.runtime_plans.command})
       }}
    end
  end

  def fetch_runtime_basis(organization_id, mission_id) do
    with {:ok, activation} <- Activations.fetch_active_activation(organization_id, mission_id),
         do: MissionModelPromotion.runtime_basis(activation)
  end

  def fetch_command_runtime_basis(organization_id, mission_id, source_endpoint_id) do
    with {:ok, activation} <- Activations.fetch_active_activation(organization_id, mission_id) do
      if FleetSnapshot.fleet?(activation.metadata),
        do: command_runtime_basis(activation, source_endpoint_id),
        else: MissionModelPromotion.runtime_basis(activation)
    end
  end

  defp command_runtime_basis(activation, source) do
    case FleetSnapshot.entry_for_source(activation.metadata, source) do
      {:ok, %{"commanding_enabled" => true}} ->
        SpacecraftModelBindings.runtime_basis(activation, source)

      _ ->
        {:error, :spacecraft_commanding_not_active}
    end
  end

  @doc "Selects a target's immutable plan while the caller retains the generation lock."
  def for_target(%{activation: %{metadata: metadata} = activation} = snapshot, target) do
    if FleetSnapshot.fleet?(metadata),
      do: target_basis(snapshot, activation, target),
      else: {:ok, snapshot}
  end

  def for_target(snapshot, _target), do: {:ok, snapshot}

  defp target_basis(snapshot, activation, target) do
    with {:ok, basis} <-
           SpacecraftModelBindings.command_basis(
             activation,
             target.source_endpoint_id
           ),
         {:ok, catalog} <- MissionModelPlanDecoder.command_authoring_catalog(basis.runtime_plans) do
      {:ok, %{snapshot | basis: basis, catalog: catalog}}
    end
  end

  def active_revision_id(organization_id, mission_id) do
    case Activations.fetch_active_activation(organization_id, mission_id) do
      {:ok, activation} -> get_in(activation.metadata, ["mission_model", "revision_id"])
      {:error, :no_active_binding_set} -> nil
    end
  end
end
