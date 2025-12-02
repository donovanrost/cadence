defmodule Cadence.Targets do
  @moduledoc """
  The Targets context - boundary for target-related operations.

  This context handles:
  - Target CRUD operations
  - Target group management
  - Circuit breaker state management
  - Target status tracking
  """

  import Ecto.Query, warn: false
  alias Cadence.Repo

  alias Cadence.Targets.{Target, TargetGroup}
  alias Cadence.Missions.Mission

  ## Target CRUD

  @doc """
  Returns the list of targets for a mission.
  """
  def list_targets(%Mission{id: mission_id}) do
    Target
    |> where([t], t.mission_id == ^mission_id)
    |> order_by([t], t.identifier)
    |> preload([definition_set: :database])
    |> Repo.all()
  end

  @doc """
  Gets a single target.

  Raises `Ecto.NoResultsError` if the Target does not exist.
  """
  def get_target!(id), do: Repo.get!(Target, id)

  @doc """
  Gets a target by identifier within a mission.
  """
  def get_target_by_identifier(%Mission{id: mission_id}, identifier) do
    get_target_by_identifier(mission_id, identifier)
  end

  def get_target_by_identifier(mission_id, identifier) when is_binary(mission_id) do
    Target
    |> where([t], t.mission_id == ^mission_id and t.identifier == ^identifier)
    |> Repo.one()
  end

  @doc """
  Creates a target.
  """
  def create_target(attrs \\ %{}) do
    %Target{}
    |> Target.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a target.
  """
  def update_target(%Target{} = target, attrs) do
    target
    |> Target.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a target.
  """
  def delete_target(%Target{} = target) do
    Repo.delete(target)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking target changes.
  """
  def change_target(%Target{} = target, attrs \\ %{}) do
    Target.changeset(target, attrs)
  end

  ## Definition Set Assignment

  @doc """
  Assigns a definition set to a target.

  This determines which command/telemetry dictionary the target uses.
  """
  def assign_definition_set(%Target{} = target, definition_set_id) do
    target
    |> Target.assign_definition_set(definition_set_id)
    |> Repo.update()
  end

  @doc """
  Gets the definition_set_id for a target by mission_id and identifier.

  Returns nil if target not found or has no definition_set assigned.
  This is used by the telemetry pipeline to look up the correct dictionary.
  """
  def get_definition_set_id(mission_id, target_identifier) when is_binary(mission_id) and is_binary(target_identifier) do
    Target
    |> where([t], t.mission_id == ^mission_id and t.identifier == ^target_identifier)
    |> select([t], t.definition_set_id)
    |> Repo.one()
  end

  @doc """
  Gets the definition_set_id for a target by its ID.

  Returns nil if target not found or has no definition_set assigned.
  """
  def get_definition_set_id_by_target_id(target_id) when is_binary(target_id) do
    Target
    |> where([t], t.id == ^target_id)
    |> select([t], t.definition_set_id)
    |> Repo.one()
  end

  @doc """
  Gets a target with its definition_set preloaded.
  """
  def get_target_with_definition_set!(id) do
    Target
    |> Repo.get!(id)
    |> Repo.preload(:definition_set)
  end

  @doc """
  Returns all targets using a specific definition set.

  Useful for determining which targets are affected by a given
  command/telemetry database version.
  """
  def list_targets_by_definition_set(definition_set_id) do
    Target
    |> where([t], t.definition_set_id == ^definition_set_id)
    |> order_by([t], t.identifier)
    |> Repo.all()
  end

  ## Circuit Breaker Management

  @doc """
  Opens the circuit breaker for a target after command failures.
  """
  def open_circuit_breaker(%Target{} = target) do
    target
    |> Target.open_circuit_breaker()
    |> Repo.update()
  end

  @doc """
  Closes the circuit breaker, resetting failure count.
  """
  def close_circuit_breaker(%Target{} = target) do
    target
    |> Target.close_circuit_breaker()
    |> Repo.update()
  end

  @doc """
  Increments the failure count for a target's circuit breaker.

  If the failure count exceeds the threshold (default: 3), opens the circuit breaker.
  """
  def increment_circuit_breaker_failures(%Target{} = target, threshold \\ 3) do
    changeset = Target.increment_failures(target)

    with {:ok, updated_target} <- Repo.update(changeset) do
      if updated_target.circuit_breaker_failures >= threshold do
        open_circuit_breaker(updated_target)
      else
        {:ok, updated_target}
      end
    end
  end

  @doc """
  Checks if a target's circuit breaker is open.
  """
  def circuit_breaker_open?(%Target{circuit_breaker_status: status}) do
    status == "open"
  end

  ## Target Groups

  @doc """
  Returns the list of target groups for a mission.
  """
  def list_target_groups(%Mission{id: mission_id}) do
    TargetGroup
    |> where([tg], tg.mission_id == ^mission_id)
    |> order_by([tg], [tg.parent_id, tg.name])
    |> Repo.all()
  end

  @doc """
  Gets a single target group.

  Raises `Ecto.NoResultsError` if the TargetGroup does not exist.
  """
  def get_target_group!(id), do: Repo.get!(TargetGroup, id)

  @doc """
  Gets a target group by slug within a mission.
  """
  def get_target_group_by_slug(%Mission{id: mission_id}, slug) do
    TargetGroup
    |> where([tg], tg.mission_id == ^mission_id and tg.slug == ^slug)
    |> Repo.one()
  end

  @doc """
  Creates a target group.
  """
  def create_target_group(attrs \\ %{}) do
    %TargetGroup{}
    |> TargetGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a target group.
  """
  def update_target_group(%TargetGroup{} = target_group, attrs) do
    target_group
    |> TargetGroup.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a target group.
  """
  def delete_target_group(%TargetGroup{} = target_group) do
    Repo.delete(target_group)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking target group changes.
  """
  def change_target_group(%TargetGroup{} = target_group, attrs \\ %{}) do
    TargetGroup.changeset(target_group, attrs)
  end

  @doc """
  Adds a target to a target group.
  """
  def add_target_to_group(%Target{} = target, %TargetGroup{} = group) do
    # Ensure target and group belong to the same mission
    if target.mission_id == group.mission_id do
      # Insert a membership record directly
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        target_group_id: Ecto.UUID.dump!(group.id),
        target_id: Ecto.UUID.dump!(target.id),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
      |> then(&Repo.insert_all("target_group_memberships", [&1]))

      # Return the group with updated targets
      {:ok, Repo.preload(group, :targets, force: true)}
    else
      {:error, :mission_mismatch}
    end
  end

  @doc """
  Removes a target from a target group.
  """
  def remove_target_from_group(%Target{} = target, %TargetGroup{} = group) do
    group = Repo.preload(group, :targets)

    group
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:targets, Enum.reject(group.targets, &(&1.id == target.id)))
    |> Repo.update()
  end

  @doc """
  Gets all targets in a target group (including nested groups).
  """
  def get_group_targets(%TargetGroup{} = group, opts \\ []) do
    include_nested = Keyword.get(opts, :include_nested, true)

    if include_nested do
      get_targets_recursive(group)
    else
      group
      |> Repo.preload(:targets)
      |> Map.get(:targets)
    end
  end

  ## Private Functions

  defp get_targets_recursive(group) do
    group = Repo.preload(group, [:targets, :children])

    direct_targets = group.targets

    nested_targets =
      group.children
      |> Enum.flat_map(&get_targets_recursive/1)

    (direct_targets ++ nested_targets)
    |> Enum.uniq_by(& &1.id)
  end
end
