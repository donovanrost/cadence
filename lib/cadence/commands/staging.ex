defmodule Cadence.Commands.Staging do
  @moduledoc """
  Context module for command staging operations.

  Manages the mission-wide staging workbench where operators prepare commands
  before queuing them for execution.

  ## Visibility

  Staged commands are shared across the mission team - all operators on a mission
  can see and manage staged commands. This supports collaborative operations and
  shift handovers.

  ## Usage

      # Add a command to staging
      {:ok, staged} = Staging.add_to_stage(user, mission_id, meta_command, targets, opts)

      # Update a target's parameters
      {:ok, target_entry} = Staging.update_target_params(target_entry_id, new_params)

      # Queue all staged commands
      {:ok, queued_count} = Staging.queue_all(mission_id)

      # Clear staging area
      {:ok, count} = Staging.clear_stage(mission_id)
  """

  import Ecto.Query, warn: false

  alias Cadence.Repo
  alias Cadence.Commands.{StagedCommand, StagedCommandTarget, TargetQueue}
  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Outbox
  alias Ecto.Multi

  @pubsub Cadence.PubSub

  # ============================================================================
  # Query Operations
  # ============================================================================

  @doc """
  Lists all staged commands for a mission.

  Returns staged commands with their target entries preloaded.
  """
  @spec list_staged(String.t()) :: [StagedCommand.t()]
  def list_staged(mission_id) do
    from(sc in StagedCommand,
      where: sc.mission_id == ^mission_id,
      order_by: [asc: sc.inserted_at],
      preload: [targets: ^from(t in StagedCommandTarget, order_by: t.position)]
    )
    |> Repo.all()
  end

  @doc """
  Gets a staged command by ID.
  """
  @spec get_staged_command(String.t()) :: StagedCommand.t() | nil
  def get_staged_command(id) do
    StagedCommand
    |> Repo.get(id)
    |> Repo.preload(:targets)
  end

  @doc """
  Gets a staged command by ID, raising if not found.
  """
  @spec get_staged_command!(String.t()) :: StagedCommand.t()
  def get_staged_command!(id) do
    StagedCommand
    |> Repo.get!(id)
    |> Repo.preload(:targets)
  end

  @doc """
  Gets a staged command target entry by ID.
  """
  @spec get_target_entry(String.t()) :: StagedCommandTarget.t() | nil
  def get_target_entry(id) do
    StagedCommandTarget
    |> Repo.get(id)
    |> Repo.preload(:staged_command)
  end

  @doc """
  Gets a staged command target entry by ID, raising if not found.
  """
  @spec get_target_entry!(String.t()) :: StagedCommandTarget.t()
  def get_target_entry!(id) do
    StagedCommandTarget
    |> Repo.get!(id)
    |> Repo.preload(:staged_command)
  end

  @doc """
  Counts staged commands for a mission.
  """
  @spec count_staged(String.t()) :: non_neg_integer()
  def count_staged(mission_id) do
    from(sc in StagedCommand,
      where: sc.mission_id == ^mission_id,
      select: count(sc.id)
    )
    |> Repo.one()
  end

  @doc """
  Counts total target entries across all staged commands for a mission.
  """
  @spec count_staged_targets(String.t()) :: non_neg_integer()
  def count_staged_targets(mission_id) do
    from(t in StagedCommandTarget,
      join: sc in assoc(t, :staged_command),
      where: sc.mission_id == ^mission_id,
      select: count(t.id)
    )
    |> Repo.one()
  end

  # ============================================================================
  # Mutation Operations
  # ============================================================================

  @doc """
  Adds a command to the staging area.

  Creates a StagedCommand with StagedCommandTarget entries for each target.

  ## Options

  - `:priority` - Priority level 0-5 (default: 3)
  - `:client_id` - Client-generated ID for deduplication

  ## Example

      targets = [
        %{target_id: "abc", target_name: "SAT-001", params: %{"mode" => 1}},
        %{target_id: "def", target_name: "SAT-002", params: %{"mode" => 2}}
      ]
      {:ok, staged} = Staging.add_to_stage(user, mission_id, command, targets)
  """
  @spec add_to_stage(map(), String.t(), MetaCommand.t(), [map()], keyword()) ::
          {:ok, StagedCommand.t()} | {:error, Ecto.Changeset.t()}
  def add_to_stage(user, mission_id, %MetaCommand{} = command, targets, opts \\ []) do
    organization_id = get_organization_id(mission_id)
    priority = Keyword.get(opts, :priority, 3)
    client_id = Keyword.get(opts, :client_id)

    staged_attrs = %{
      organization_id: organization_id,
      mission_id: mission_id,
      created_by_user_id: user.id,
      meta_command_id: command.id,
      command_name: command.name,
      priority: priority,
      client_id: client_id
    }

    Multi.new()
    |> Multi.insert(:staged_command, StagedCommand.changeset(%StagedCommand{}, staged_attrs))
    |> Multi.insert_all(:targets, StagedCommandTarget, fn %{staged_command: sc} ->
      now = DateTime.utc_now()

      targets
      |> Enum.with_index()
      |> Enum.map(fn {target, index} ->
        %{
          id: Ecto.UUID.generate(),
          staged_command_id: sc.id,
          target_id: target.target_id || target["target_id"],
          target_name: target.target_name || target["target_name"],
          params: target.params || target["params"] || %{},
          position: index,
          inserted_at: now,
          updated_at: now
        }
      end)
    end)
    |> Outbox.append(:outbox, fn %{staged_command: sc} ->
      %{
        organization_id: organization_id,
        mission_id: mission_id,
        event_type: "command_staged",
        aggregate_type: "staged_command",
        aggregate_id: sc.id,
        actor_id: user.id,
        actor_type: "user",
        payload: %{
          command_name: command.name,
          target_count: length(targets),
          priority: priority
        }
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{staged_command: staged}} ->
        broadcast_staging_change(mission_id, :added, staged.id)
        {:ok, Repo.preload(staged, :targets)}

      {:error, :staged_command, changeset, _} ->
        {:error, changeset}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  @doc """
  Updates the parameters for a specific target entry.
  """
  @spec update_target_params(String.t(), map()) ::
          {:ok, StagedCommandTarget.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_target_params(target_entry_id, params) do
    case get_target_entry(target_entry_id) do
      nil ->
        {:error, :not_found}

      entry ->
        entry
        |> StagedCommandTarget.params_changeset(params)
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            sc = entry.staged_command
            broadcast_staging_change(sc.mission_id, :updated, sc.id)
            {:ok, updated}

          error ->
            error
        end
    end
  end

  @doc """
  Updates the priority for a staged command.
  """
  @spec update_priority(String.t(), integer()) ::
          {:ok, StagedCommand.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_priority(staged_command_id, priority) do
    case get_staged_command(staged_command_id) do
      nil ->
        {:error, :not_found}

      staged ->
        staged
        |> StagedCommand.priority_changeset(priority)
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            broadcast_staging_change(staged.mission_id, :updated, staged.id)
            {:ok, updated}

          error ->
            error
        end
    end
  end

  @doc """
  Removes a specific target from a staged command.

  If this is the last target, the entire staged command is deleted.
  """
  @spec remove_target(String.t()) :: {:ok, :removed | :deleted} | {:error, :not_found}
  def remove_target(target_entry_id) do
    case get_target_entry(target_entry_id) do
      nil ->
        {:error, :not_found}

      entry ->
        staged = entry.staged_command

        # Check if this is the last target
        target_count =
          from(t in StagedCommandTarget,
            where: t.staged_command_id == ^staged.id,
            select: count(t.id)
          )
          |> Repo.one()

        if target_count == 1 do
          # Delete the entire staged command (cascades to targets)
          Repo.delete(staged)
          broadcast_staging_change(staged.mission_id, :removed, staged.id)
          {:ok, :deleted}
        else
          Repo.delete(entry)
          broadcast_staging_change(staged.mission_id, :updated, staged.id)
          {:ok, :removed}
        end
    end
  end

  @doc """
  Removes an entire staged command and all its targets.
  """
  @spec remove_staged_command(String.t()) :: {:ok, StagedCommand.t()} | {:error, :not_found}
  def remove_staged_command(staged_command_id) do
    case get_staged_command(staged_command_id) do
      nil ->
        {:error, :not_found}

      staged ->
        Repo.delete(staged)
        broadcast_staging_change(staged.mission_id, :removed, staged.id)
        {:ok, staged}
    end
  end

  @doc """
  Clears all staged commands for a mission.
  """
  @spec clear_stage(String.t()) :: {:ok, non_neg_integer()}
  def clear_stage(mission_id) do
    {count, _} =
      from(sc in StagedCommand,
        where: sc.mission_id == ^mission_id
      )
      |> Repo.delete_all()

    broadcast_staging_change(mission_id, :cleared, nil)
    {:ok, count}
  end

  # ============================================================================
  # Queue Operations
  # ============================================================================

  @doc """
  Queues a single target entry from staging.

  Creates a QueueEntry and removes the target from staging.
  If this was the last target, removes the entire staged command.
  """
  @spec queue_target(String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def queue_target(target_entry_id, opts \\ []) do
    case get_target_entry(target_entry_id) do
      nil ->
        {:error, :not_found}

      entry ->
        staged = entry.staged_command |> Repo.preload(:meta_command)

        result =
          TargetQueue.enqueue(
            staged.mission_id,
            entry.target_id,
            staged.command_name,
            entry.params,
            Keyword.merge(opts, priority: staged.priority, user_id: staged.created_by_user_id)
          )

        case result do
          {:ok, queue_entry} ->
            remove_target(target_entry_id)
            {:ok, queue_entry}

          error ->
            error
        end
    end
  end

  @doc """
  Queues all target entries from a single staged command.
  """
  @spec queue_staged_command(String.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def queue_staged_command(staged_command_id, opts \\ []) do
    case get_staged_command(staged_command_id) do
      nil ->
        {:error, :not_found}

      staged ->
        results =
          Enum.map(staged.targets, fn target_entry ->
            TargetQueue.enqueue(
              staged.mission_id,
              target_entry.target_id,
              staged.command_name,
              target_entry.params,
              Keyword.merge(opts, priority: staged.priority, user_id: staged.created_by_user_id)
            )
          end)

        successes = Enum.count(results, &match?({:ok, _}, &1))

        # Remove the staged command after queueing
        if successes > 0 do
          remove_staged_command(staged_command_id)
        end

        {:ok, successes}
    end
  end

  @doc """
  Queues all staged commands for a mission.
  """
  @spec queue_all(String.t(), keyword()) :: {:ok, non_neg_integer()}
  def queue_all(mission_id, opts \\ []) do
    staged_commands = list_staged(mission_id)

    total_queued =
      Enum.reduce(staged_commands, 0, fn staged, acc ->
        case queue_staged_command(staged.id, opts) do
          {:ok, count} -> acc + count
          _ -> acc
        end
      end)

    {:ok, total_queued}
  end

  # ============================================================================
  # PubSub
  # ============================================================================

  @doc """
  Subscribes to staging changes for a mission.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(mission_id) do
    Phoenix.PubSub.subscribe(@pubsub, staging_topic(mission_id))
  end

  @doc """
  Unsubscribes from staging changes for a mission.
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(mission_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, staging_topic(mission_id))
  end

  defp staging_topic(mission_id) do
    "staging:#{mission_id}"
  end

  defp broadcast_staging_change(mission_id, action, staged_command_id) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      staging_topic(mission_id),
      {:staging_changed, action, staged_command_id}
    )
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_organization_id(mission_id) do
    from(m in Cadence.Missions.Mission,
      where: m.id == ^mission_id,
      select: m.organization_id
    )
    |> Repo.one!()
  end
end
