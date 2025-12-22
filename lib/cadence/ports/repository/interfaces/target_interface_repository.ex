defmodule Cadence.Ports.Repository.Interfaces.TargetInterfaceRepository do
  @moduledoc """
  Port (behavior) defining the contract for target-interface routing persistence.

  This behavior manages the routing associations between targets and interfaces:
  - Which interfaces serve which targets
  - Direction of data flow (read, write, read_write)

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Interfaces.EctoTargetInterfaceRepository` - Production
  - `Cadence.Test.Adapters.InMemoryTargetInterfaceRepository` - In-memory for tests
  """

  alias Cadence.Domain.Interfaces.Entities.TargetInterface

  @type id :: String.t()
  @type target_id :: String.t()
  @type interface_id :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | :already_exists | term()

  # ============================================================================
  # TargetInterface CRUD Operations
  # ============================================================================

  @doc """
  Finds a target-interface routing by ID.
  """
  @callback find(id()) :: {:ok, TargetInterface.t()} | {:error, :not_found}

  @doc """
  Finds a specific routing by target and interface IDs.
  """
  @callback find_by_target_and_interface(target_id(), interface_id()) ::
              {:ok, TargetInterface.t()} | {:error, :not_found}

  @doc """
  Persists a target-interface routing (insert or update).
  """
  @callback save(TargetInterface.t()) :: {:ok, TargetInterface.t()} | {:error, error()}

  @doc """
  Deletes a target-interface routing by ID.
  """
  @callback delete(id()) :: {:ok, TargetInterface.t()} | {:error, :not_found}

  @doc """
  Deletes the routing between a specific target and interface.
  """
  @callback delete_by_target_and_interface(target_id(), interface_id()) :: :ok

  # ============================================================================
  # Listing Operations
  # ============================================================================

  @doc """
  Lists all routings for a specific interface.
  """
  @callback list_for_interface(interface_id()) :: [TargetInterface.t()]

  @doc """
  Lists all routings for a specific target.
  """
  @callback list_for_target(target_id()) :: [TargetInterface.t()]

  @doc """
  Returns the list of target IDs routed through an interface.

  This is a convenience method used for denormalizing target_ids
  into the Interface entity.
  """
  @callback get_target_ids_for_interface(interface_id()) :: [String.t()]

  @doc """
  Returns the list of interface IDs that serve a target.
  """
  @callback get_interface_ids_for_target(target_id()) :: [String.t()]

  # ============================================================================
  # Batch Operations
  # ============================================================================

  @doc """
  Replaces all routings for an interface with a new set.

  This deletes existing routings and creates new ones.
  """
  @callback replace_for_interface(interface_id(), [TargetInterface.t()]) ::
              {:ok, [TargetInterface.t()]} | {:error, term()}

  @doc """
  Deletes all routings for an interface.
  """
  @callback delete_all_for_interface(interface_id()) :: :ok

  @doc """
  Deletes all routings for a target.
  """
  @callback delete_all_for_target(target_id()) :: :ok

  # ============================================================================
  # Implementation Helper
  # ============================================================================

  @doc """
  Returns the configured target-interface repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :target_interface_repository,
      Cadence.Adapters.Persistence.Ecto.Interfaces.EctoTargetInterfaceRepository
    )
  end
end
