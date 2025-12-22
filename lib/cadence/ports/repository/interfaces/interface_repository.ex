defmodule Cadence.Ports.Repository.Interfaces.InterfaceRepository do
  @moduledoc """
  Port (behavior) defining the contract for interface persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Data Plane Considerations

  This repository is designed to support future Data Plane / Control Plane
  architecture. Key operations:
  - `list_for_mission/2` - Load all interfaces for a mission (for supervisor init)
  - `find_with_protocols/1` - Load interface with embedded protocols (for DP)
  - CRUD operations emit events via application services (not here)

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Interfaces.EctoInterfaceRepository` - Production
  - `Cadence.Test.Adapters.InMemoryInterfaceRepository` - In-memory for tests
  """

  alias Cadence.Domain.Interfaces.Entities.Interface

  @type id :: String.t()
  @type mission_id :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  # ============================================================================
  # Interface CRUD Operations
  # ============================================================================

  @doc """
  Finds an interface by ID.

  Returns `{:ok, interface}` if found, `{:error, :not_found}` otherwise.
  Protocols are NOT loaded by default - use `find_with_protocols/1` for that.
  """
  @callback find(id()) :: {:ok, Interface.t()} | {:error, :not_found}

  @doc """
  Finds an interface by ID with protocols preloaded.

  This is the preferred method for loading interfaces that will be used
  by GenServers, as it includes all protocol chain configuration.
  """
  @callback find_with_protocols(id()) :: {:ok, Interface.t()} | {:error, :not_found}

  @doc """
  Finds an interface by name within a mission.
  """
  @callback find_by_name(mission_id(), name :: String.t()) ::
              {:ok, Interface.t()} | {:error, :not_found}

  @doc """
  Persists an interface (insert or update).

  If the interface has no ID, it will be inserted.
  If it has an ID, it will be updated.
  Protocols are saved as part of the interface.
  """
  @callback save(Interface.t()) :: {:ok, Interface.t()} | {:error, error()}

  @doc """
  Deletes an interface by ID.

  Also deletes associated protocols and target_interface associations.
  """
  @callback delete(id()) :: {:ok, Interface.t()} | {:error, :not_found}

  # ============================================================================
  # Listing Operations
  # ============================================================================

  @doc """
  Lists interfaces for a mission with optional filtering.

  ## Options

  - `:connection_type` - Filter by connection type
  - `:preload_protocols` - Whether to preload protocols (default: false)
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset

  Note: For Data Plane initialization, use `preload_protocols: true` to avoid N+1 queries.
  """
  @callback list_for_mission(mission_id(), opts()) :: [Interface.t()]

  @doc """
  Lists all interfaces matching the given options.

  ## Options

  Same as `list_for_mission/2` plus:
  - `:mission_id` - Filter by mission
  """
  @callback list(opts()) :: [Interface.t()]

  # ============================================================================
  # Protocol Operations
  # ============================================================================

  @doc """
  Saves protocols for an interface.

  This replaces all existing protocols with the new list.
  The protocols should be ordered by their `order` field.
  """
  @callback save_protocols(id(), [map()]) :: {:ok, Interface.t()} | {:error, term()}

  @doc """
  Deletes all protocols for an interface.
  """
  @callback delete_protocols(id()) :: :ok

  # ============================================================================
  # Counting Operations
  # ============================================================================

  @doc """
  Counts the number of interfaces in a mission.
  """
  @callback count_for_mission(mission_id()) :: non_neg_integer()

  # ============================================================================
  # Implementation Helper
  # ============================================================================

  @doc """
  Returns the configured interface repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :interface_repository,
      Cadence.Adapters.Persistence.Ecto.Interfaces.EctoInterfaceRepository
    )
  end
end
