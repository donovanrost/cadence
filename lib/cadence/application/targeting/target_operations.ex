defmodule Cadence.Application.Targeting.TargetOperations do
  @moduledoc """
  Use case module for target write operations.

  This module provides operations for creating, updating, and managing
  targets including circuit breaker state changes.

  All operations:
  1. Validate using domain entity logic
  2. Persist the change via repository
  3. Broadcast for cache/UI updates

  ## Usage

      # Create a target
      {:ok, target} = TargetOperations.create(%{
        mission_id: mission_id,
        definition_set_id: ds_id,
        name: "SAT-1",
        identifier: "SAT_001",
        type: :spacecraft
      })

      # Open circuit breaker
      {:ok, target} = TargetOperations.open_circuit_breaker(target_id)

      # Update target
      {:ok, target} = TargetOperations.update(target, %{status: :online})
  """

  alias Cadence.Domain.Targeting.Entities.Target

  @type id :: String.t()
  @type attrs :: map()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :target_repository,
      Cadence.Adapters.Persistence.Ecto.Targeting.EctoTargetRepository
    )
  end

  # ===========================================================================
  # CRUD Operations
  # ===========================================================================

  @doc """
  Creates a new target.

  ## Required Attributes

  - `:mission_id` - The mission this target belongs to
  - `:definition_set_id` - The C&T database definition set
  - `:name` - Human-readable name
  - `:identifier` - Unique identifier within mission (e.g., "SAT_001")
  - `:type` - Target type (:spacecraft, :ground_station, :simulator, :relay)

  ## Optional Attributes

  - `:status` - Initial status (default: :offline)
  - `:config` - Configuration map
  - `:metadata` - Metadata map
  - `:active_limit_set` - Active limit set name (default: "NOMINAL")
  - `:bucket_id` - Associated bucket for hierarchical grouping

  ## Returns

  - `{:ok, target}` - Successfully created
  - `{:error, reason}` - Validation or persistence error
  """
  @spec create(attrs()) :: {:ok, Target.t()} | {:error, term()}
  def create(attrs) do
    with {:ok, target} <- Target.new(attrs),
         {:ok, saved} <- repo().save(target) do
      broadcast_change(saved, :created)
      {:ok, saved}
    end
  end

  @doc """
  Updates an existing target.

  ## Allowed Attributes

  - `:name` - Human-readable name
  - `:status` - Target status
  - `:config` - Configuration map
  - `:metadata` - Metadata map
  - `:active_limit_set` - Active limit set name
  - `:definition_set_id` - Definition set ID
  - `:bucket_id` - Bucket ID

  ## Returns

  - `{:ok, target}` - Successfully updated
  - `{:error, reason}` - Validation or persistence error
  """
  @spec update(Target.t(), attrs()) :: {:ok, Target.t()} | {:error, term()}
  def update(%Target{} = target, attrs) do
    with {:ok, updated} <- Target.update(target, attrs),
         {:ok, saved} <- repo().save(updated) do
      broadcast_change(saved, :updated)
      {:ok, saved}
    end
  end

  @doc """
  Deletes a target.

  ## Returns

  - `{:ok, target}` - Successfully deleted
  - `{:error, :not_found}` - Target not found
  """
  @spec delete(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def delete(%Target{id: id} = _target) do
    with {:ok, deleted} <- repo().delete(id) do
      broadcast_change(deleted, :deleted)
      {:ok, deleted}
    end
  end

  # ===========================================================================
  # Circuit Breaker Operations
  # ===========================================================================

  @doc """
  Opens the circuit breaker for a target.

  When open, commands should not be sent to this target.
  Called when command failures exceed the threshold.

  ## Returns

  - `{:ok, target}` - Circuit breaker opened
  - `{:error, :not_found}` - Target not found
  """
  @spec open_circuit_breaker(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def open_circuit_breaker(%Target{} = target) do
    with {:ok, updated} <- Target.open_circuit_breaker(target),
         {:ok, saved} <- repo().save(updated) do
      broadcast_change(saved, :circuit_breaker_opened)
      {:ok, saved}
    end
  end

  @doc """
  Closes the circuit breaker for a target.

  Called when the target has recovered and can accept commands again.
  Resets the failure count.

  ## Returns

  - `{:ok, target}` - Circuit breaker closed
  - `{:error, :not_found}` - Target not found
  """
  @spec close_circuit_breaker(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def close_circuit_breaker(%Target{} = target) do
    with {:ok, updated} <- Target.close_circuit_breaker(target),
         {:ok, saved} <- repo().save(updated) do
      broadcast_change(saved, :circuit_breaker_closed)
      {:ok, saved}
    end
  end

  @doc """
  Increments the failure count for circuit breaker logic.

  The caller should check if the failure threshold is exceeded
  and call `open_circuit_breaker/1` if needed.

  ## Returns

  - `{:ok, target}` - Failure count incremented
  - `{:error, :not_found}` - Target not found
  """
  @spec increment_failures(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def increment_failures(%Target{} = target) do
    with {:ok, updated} <- Target.increment_failures(target) do
      repo().save(updated)
    end
  end

  # ===========================================================================
  # Status Operations
  # ===========================================================================

  @doc """
  Sets the target to online status.
  """
  @spec go_online(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def go_online(%Target{} = target) do
    with {:ok, updated} <- Target.go_online(target),
         {:ok, saved} <- repo().save(updated) do
      broadcast_change(saved, :online)
      {:ok, saved}
    end
  end

  @doc """
  Sets the target to offline status.
  """
  @spec go_offline(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def go_offline(%Target{} = target) do
    with {:ok, updated} <- Target.go_offline(target),
         {:ok, saved} <- repo().save(updated) do
      broadcast_change(saved, :offline)
      {:ok, saved}
    end
  end

  # ===========================================================================
  # Definition Set Operations
  # ===========================================================================

  @doc """
  Assigns a definition set to a target.
  """
  @spec assign_definition_set(Target.t(), id()) :: {:ok, Target.t()} | {:error, term()}
  def assign_definition_set(%Target{} = target, definition_set_id) do
    update(target, %{definition_set_id: definition_set_id})
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp broadcast_change(target, event_type) do
    # Broadcast to existing UI listeners
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "targets:#{target.mission_id}",
      {:target_changed, event_type, target}
    )

    # Broadcast to cache listeners (MetaCommandCache, PacketIdentifier)
    cache_topic = "mission:#{target.mission_id}:targets"
    cache_event = cache_event_for(event_type, target)

    Phoenix.PubSub.broadcast(Cadence.PubSub, cache_topic, cache_event)
  end

  defp cache_event_for(:created, target), do: {:target_created, target}
  defp cache_event_for(:deleted, target), do: {:target_deleted, target}
  defp cache_event_for(_event_type, target), do: {:target_updated, target}
end
