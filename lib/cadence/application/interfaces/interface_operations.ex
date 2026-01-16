defmodule Cadence.Application.Interfaces.InterfaceOperations do
  @moduledoc """
  Use case module for interface write operations.

  Provides operations for creating, updating, and managing interfaces.

  ## Event Emission (Data Plane Compatibility)

  All write operations emit PubSub events for Data Plane consumption:
  - `:interface_created` - When a new interface is created
  - `:interface_updated` - When interface configuration changes
  - `:interface_deleted` - When an interface is deleted

  These events enable future push-based Data Plane updates without requiring
  the Data Plane to poll the database for configuration changes.

  ## Usage

      # Create an interface
      {:ok, interface} = InterfaceOperations.create(%{
        mission_id: "mission-123",
        name: "SPACECRAFT_TLM",
        connection_type: :tcp_client,
        host: "192.168.1.100",
        port: 8080
      })

      # Update an interface
      {:ok, interface} = InterfaceOperations.update(interface_id, %{port: 9090})

  """

  alias Cadence.Application.Interfaces.InterfaceQueries
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Ports.Repository.Interfaces.InterfaceRepository

  @type interface_id :: String.t()
  @type mission_id :: String.t()
  @type attrs :: map()

  # Get configured repository
  defp repo do
    InterfaceRepository.impl()
  end

  # ===========================================================================
  # Interface CRUD Operations
  # ===========================================================================

  @doc """
  Creates a new interface.

  ## Attributes

  Required:
  - `:mission_id` - ID of the parent mission
  - `:name` - Interface display name (unique within mission)
  - `:connection_type` - Type of connection (:tcp_client, :tcp_server, etc.)

  Conditionally Required (based on connection_type):
  - `:host` and `:port` - Required for client types
  - `:bind_port` - Required for server types

  Optional:
  - `:bind_address` - Address to bind for servers (default: "0.0.0.0")
  - `:auto_reconnect` - Whether to auto-reconnect (default: true)
  - `:reconnect_delay_ms` - Delay between reconnect attempts (default: 5000)
  - `:config` - Additional configuration map
  """
  @spec create(attrs()) :: {:ok, Interface.t()} | {:error, term()}
  def create(attrs) do
    with {:ok, interface} <- Interface.new(attrs),
         {:ok, saved} <- repo().save(interface) do
      broadcast_config_change(:interface_created, saved)
      {:ok, saved}
    end
  end

  @doc """
  Updates an existing interface.

  Emits `:interface_updated` event on success.
  """
  @spec update(interface_id(), attrs()) :: {:ok, Interface.t()} | {:error, term()}
  def update(interface_id, attrs) do
    with {:ok, interface} <- InterfaceQueries.find(interface_id),
         {:ok, updated} <- Interface.update(interface, attrs),
         {:ok, saved} <- repo().save(updated) do
      broadcast_config_change(:interface_updated, saved)
      {:ok, saved}
    end
  end

  @doc """
  Deletes an interface.

  Emits `:interface_deleted` event on success.
  """
  @spec delete(interface_id()) :: {:ok, Interface.t()} | {:error, term()}
  def delete(interface_id) do
    with {:ok, interface} <- InterfaceQueries.find(interface_id),
         {:ok, deleted} <- repo().delete(interface_id) do
      broadcast_config_change(:interface_deleted, interface)
      {:ok, deleted}
    end
  end

  # ===========================================================================
  # Target Routing Operations
  # ===========================================================================

  @doc """
  Adds a target to the interface's routing.

  Emits `:interface_updated` event on success.
  """
  @spec add_target(interface_id(), String.t()) :: {:ok, Interface.t()} | {:error, term()}
  def add_target(interface_id, target_id) do
    with {:ok, interface} <- InterfaceQueries.find(interface_id),
         {:ok, updated} <- Interface.add_target(interface, target_id),
         {:ok, saved} <- repo().save(updated) do
      broadcast_config_change(:interface_updated, saved)
      {:ok, saved}
    end
  end

  @doc """
  Removes a target from the interface's routing.

  Emits `:interface_updated` event on success.
  """
  @spec remove_target(interface_id(), String.t()) :: {:ok, Interface.t()} | {:error, term()}
  def remove_target(interface_id, target_id) do
    with {:ok, interface} <- InterfaceQueries.find(interface_id),
         {:ok, updated} <- Interface.remove_target(interface, target_id),
         {:ok, saved} <- repo().save(updated) do
      broadcast_config_change(:interface_updated, saved)
      {:ok, saved}
    end
  end

  # ===========================================================================
  # Event Emission (Data Plane Compatibility)
  # ===========================================================================

  @doc """
  Broadcasts a configuration change event.

  These events are used for:
  1. Hot-reloading interface GenServers when config changes
  2. Future Data Plane push-based updates
  3. Dashboard real-time updates

  ## Topic Format

  Events are broadcast to `mission:{mission_id}:interface_config`
  """
  @spec broadcast_config_change(atom(), Interface.t()) :: :ok
  def broadcast_config_change(event_type, %Interface{mission_id: mission_id} = interface) do
    topic = "mission:#{mission_id}:interface_config"

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {event_type, interface}
    )

    :ok
  end
end
