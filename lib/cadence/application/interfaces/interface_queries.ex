defmodule Cadence.Application.Interfaces.InterfaceQueries do
  @moduledoc """
  Query service for interface-related read operations.

  Provides operations for finding and listing interfaces.

  ## Usage

      # Find an interface by ID
      {:ok, interface} = InterfaceQueries.find(interface_id)

      # Find with protocols for runtime use
      {:ok, interface} = InterfaceQueries.find_with_protocols(interface_id)

      # List interfaces for a mission
      interfaces = InterfaceQueries.list_for_mission(mission_id)
  """

  alias Cadence.Domain.Interfaces.Entities.Interface

  @type interface_id :: String.t()
  @type mission_id :: String.t()
  @type opts :: keyword()

  # Get configured repositories
  defp interface_repo do
    Cadence.Ports.Repository.Interfaces.InterfaceRepository.impl()
  end

  defp target_interface_repo do
    Cadence.Ports.Repository.Interfaces.TargetInterfaceRepository.impl()
  end

  # ===========================================================================
  # Finding Interfaces
  # ===========================================================================

  @doc """
  Finds an interface by ID.

  Returns `{:ok, interface}` if found, `{:error, :not_found}` otherwise.
  Protocols are NOT loaded - use `find_with_protocols/1` for that.
  """
  @spec find(interface_id()) :: {:ok, Interface.t()} | {:error, :not_found}
  def find(interface_id), do: interface_repo().find(interface_id)

  @doc """
  Finds an interface by ID, raising if not found.
  """
  @spec find!(interface_id()) :: Interface.t()
  def find!(interface_id) do
    case find(interface_id) do
      {:ok, interface} -> interface
      {:error, :not_found} -> raise ArgumentError, "Interface not found: #{interface_id}"
    end
  end

  @doc """
  Finds an interface by ID with protocols preloaded.

  This is the preferred method for loading interfaces that will be used
  by GenServers, as it includes all protocol chain configuration.
  """
  @spec find_with_protocols(interface_id()) :: {:ok, Interface.t()} | {:error, :not_found}
  def find_with_protocols(interface_id) do
    interface_repo().find_with_protocols(interface_id)
  end

  @doc """
  Finds an interface by name within a mission.
  """
  @spec find_by_name(mission_id(), String.t()) :: {:ok, Interface.t()} | {:error, :not_found}
  def find_by_name(mission_id, name) do
    interface_repo().find_by_name(mission_id, name)
  end

  # ===========================================================================
  # Listing Interfaces
  # ===========================================================================

  @doc """
  Lists interfaces for a mission with optional filtering.

  ## Options

  - `:connection_type` - Filter by connection type (:tcp_client, :tcp_server, etc.)
  - `:preload_protocols` - Whether to preload protocols (default: false)
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset

  ## Data Plane Usage

  For initializing interface supervisors, use `preload_protocols: true`:

      interfaces = InterfaceQueries.list_for_mission(mission_id, preload_protocols: true)
  """
  @spec list_for_mission(mission_id(), opts()) :: [Interface.t()]
  def list_for_mission(mission_id, opts \\ []) do
    interface_repo().list_for_mission(mission_id, opts)
  end

  @doc """
  Lists all interfaces with optional filtering.

  ## Options

  Same as `list_for_mission/2` plus:
  - `:mission_id` - Filter by mission
  """
  @spec list(opts()) :: [Interface.t()]
  def list(opts \\ []), do: interface_repo().list(opts)

  # ===========================================================================
  # Counting
  # ===========================================================================

  @doc """
  Counts the number of interfaces in a mission.
  """
  @spec count_for_mission(mission_id()) :: non_neg_integer()
  def count_for_mission(mission_id), do: interface_repo().count_for_mission(mission_id)

  # ===========================================================================
  # Target Routing Queries
  # ===========================================================================

  @doc """
  Returns the list of target IDs routed through an interface.
  """
  @spec get_target_ids(interface_id()) :: [String.t()]
  def get_target_ids(interface_id) do
    target_interface_repo().get_target_ids_for_interface(interface_id)
  end

  @doc """
  Returns the list of interface IDs that serve a target.
  """
  @spec get_interface_ids_for_target(String.t()) :: [String.t()]
  def get_interface_ids_for_target(target_id) do
    target_interface_repo().get_interface_ids_for_target(target_id)
  end
end
