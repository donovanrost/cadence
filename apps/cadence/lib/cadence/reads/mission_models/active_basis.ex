defmodule Cadence.Reads.MissionModels.ActiveBasis do
  @moduledoc """
  Read-only adaptation of the active Control generation into model evidence.

  Authoring receives bounded immutable command artifacts and an exact generation
  token while the Control owner's read lock remains held through the callback.
  This adapter exposes no activation mutation or runtime process operation.
  """

  import Ecto.Query

  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Control.SpacecraftModelBindings

  alias Cadence.Activations
  alias Cadence.Activations.GenerationReceipts
  alias Cadence.Commanding.AuthoringIdentity
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Repo
  alias Cadence.Runtime.MissionModelPlanDecoder

  @doc "Reads the immutable active generation for saved-versus-active configuration comparison."
  def fetch_activation(organization_id, mission_id),
    do: Activations.fetch_active_activation(organization_id, mission_id)

  @doc "Reads the latest completed generation and its fleet entries for the requested spacecraft."
  def applied_fleet(organization_id, mission_id, spacecraft_ids) do
    with {activation, applied_at} <- GenerationReceipts.latest(organization_id, mission_id),
         {:ok, entries} <- FleetSnapshot.entries_for(activation.metadata, spacecraft_ids) do
      %{activation: activation, applied_at: applied_at, entries: entries}
    else
      _no_applied_fleet -> nil
    end
  end

  def revision_at(org, mission, spacecraft_id, at) do
    org
    |> revision_assignments_at(mission, at)
    |> where([assignment], assignment.spacecraft_id == ^spacecraft_id)
    |> select([assignment], assignment.revision_id)
    |> Repo.one()
  end

  def revisions_at(org, mission, at) do
    org
    |> revision_assignments_at(mission, at)
    |> where([assignment], not is_nil(assignment.revision_id))
    |> group_by([assignment], assignment.revision_id)
    |> select([assignment], {
      assignment.revision_id,
      fragment(
        "array_agg(? ORDER BY ? COLLATE \"C\")",
        assignment.spacecraft_id,
        assignment.spacecraft_id
      )
    })
    |> Repo.all()
    |> Map.new()
  end

  defp revision_assignments_at(org, mission, at) do
    fleet_sha = GenerationReceipts.fleet_sha_at_query(org, mission, at)

    org
    |> FleetSnapshot.revision_assignments_query(mission, fleet_sha)
    |> subquery()
  end

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
         {:ok, catalog} <- MissionModelPlanDecoder.command_authoring_catalog(basis.runtime_plans),
         {:ok, resolved_against} <- command_identity(activation, basis) do
      {:ok,
       %{
         basis: basis,
         catalog: catalog,
         activation_id: activation.activation_id,
         activation: activation,
         generation: activation.generation,
         token: AuthoringIdentity.digest({:command_basis, resolved_against})
       }}
    end
  end

  # What a command resolves against, not the activation as a whole (#1107): each craft's command
  # plan, configuration revision and bindings. A generation that leaves those alone (a monitoring
  # apply, which moves craft to a new head revision with the same command plan) leaves the token
  # equal, so it doesn't void a pending GO or a create in flight; a change to any of them changes
  # it. Model approval isn't in it (`ModelApprovalGate` reads the effective statuses).
  defp command_identity(%{metadata: metadata} = activation, basis) do
    if FleetSnapshot.fleet?(metadata) do
      with {:ok, digest} <- FleetSnapshot.command_digest(metadata), do: {:ok, {:fleet, digest}}
    else
      # A single-model activation has no per-craft entries to narrow to, and a monitoring apply
      # only moves a fleet: any new generation of it voids pending work, as before #1107.
      {:ok, {:single, activation.activation_id, basis.runtime_plans.command.plan_id}}
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

  @doc """
  `for_target/2` for many targets: `%{source_endpoint_id => {:ok, snapshot} | {:error, reason}}`.
  On a fleet activation the entries are one read, and each distinct model is loaded and its
  catalog decoded once, not once per target.
  """
  def for_targets(%{activation: %{metadata: metadata} = activation} = snapshot, targets) do
    ids = Enum.map(targets, & &1.source_endpoint_id)

    if FleetSnapshot.fleet?(metadata) do
      bases = SpacecraftModelBindings.command_bases(activation, ids)

      catalogs =
        bases
        |> Map.values()
        |> Enum.flat_map(fn
          {:ok, basis} -> [basis]
          {:error, _reason} -> []
        end)
        |> Enum.uniq_by(&{&1.mission_model_revision_id, &1.mission_model_content_sha256})
        |> Map.new(
          &{{&1.mission_model_revision_id, &1.mission_model_content_sha256},
           MissionModelPlanDecoder.command_authoring_catalog(&1.runtime_plans)}
        )

      Map.new(ids, fn id ->
        {id, with_catalog(snapshot, Map.fetch!(bases, id), catalogs)}
      end)
    else
      Map.new(ids, &{&1, {:ok, snapshot}})
    end
  end

  def for_targets(snapshot, targets),
    do: Map.new(targets, &{&1.source_endpoint_id, {:ok, snapshot}})

  defp with_catalog(_snapshot, {:error, reason}, _catalogs), do: {:error, reason}

  defp with_catalog(snapshot, {:ok, basis}, catalogs) do
    case Map.fetch!(
           catalogs,
           {basis.mission_model_revision_id, basis.mission_model_content_sha256}
         ) do
      {:ok, catalog} -> {:ok, %{snapshot | basis: basis, catalog: catalog}}
      {:error, reason} -> {:error, reason}
    end
  end

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
