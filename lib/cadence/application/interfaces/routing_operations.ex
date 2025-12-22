defmodule Cadence.Application.Interfaces.RoutingOperations do
  @moduledoc """
  Use case module for target-interface routing operations.

  Provides operations for managing which interfaces serve which targets
  and the direction of data flow.

  ## Event Emission (Data Plane Compatibility)

  All write operations emit PubSub events:
  - `:routing_created` - When a new routing is created
  - `:routing_updated` - When routing direction changes
  - `:routing_deleted` - When a routing is removed

  ## Usage

      # Create a routing association
      {:ok, routing} = RoutingOperations.create(%{
        target_id: "sat-001",
        interface_id: "tcp-int-1",
        direction: :read
      })

      # Update routing direction
      {:ok, routing} = RoutingOperations.update_direction(routing_id, :read_write)
  """

  alias Cadence.Domain.Interfaces.Entities.TargetInterface

  @type routing_id :: String.t()
  @type target_id :: String.t()
  @type interface_id :: String.t()
  @type attrs :: map()

  # Get configured repository
  defp repo do
    Cadence.Ports.Repository.Interfaces.TargetInterfaceRepository.impl()
  end

  # ===========================================================================
  # Routing CRUD Operations
  # ===========================================================================

  @doc """
  Creates a new target-interface routing.

  ## Attributes

  Required:
  - `:target_id` - ID of the target
  - `:interface_id` - ID of the interface
  - `:direction` - Data direction (:read, :write, :read_write)
  """
  @spec create(attrs()) :: {:ok, TargetInterface.t()} | {:error, term()}
  def create(attrs) do
    with {:ok, routing} <- TargetInterface.new(attrs),
         {:ok, saved} <- repo().save(routing) do
      broadcast_routing_change(:routing_created, saved)
      {:ok, saved}
    end
  end

  @doc """
  Updates the direction of a routing.
  """
  @spec update_direction(routing_id(), atom()) :: {:ok, TargetInterface.t()} | {:error, term()}
  def update_direction(routing_id, new_direction) do
    with {:ok, routing} <- repo().find(routing_id),
         {:ok, updated} <- TargetInterface.update_direction(routing, new_direction),
         {:ok, saved} <- repo().save(updated) do
      broadcast_routing_change(:routing_updated, saved)
      {:ok, saved}
    end
  end

  @doc """
  Deletes a routing by ID.
  """
  @spec delete(routing_id()) :: {:ok, TargetInterface.t()} | {:error, term()}
  def delete(routing_id) do
    with {:ok, routing} <- repo().find(routing_id),
         {:ok, deleted} <- repo().delete(routing_id) do
      broadcast_routing_change(:routing_deleted, routing)
      {:ok, deleted}
    end
  end

  @doc """
  Deletes a routing by target and interface IDs.
  """
  @spec delete_by_target_and_interface(target_id(), interface_id()) :: :ok
  def delete_by_target_and_interface(target_id, interface_id) do
    case repo().find_by_target_and_interface(target_id, interface_id) do
      {:ok, routing} ->
        :ok = repo().delete_by_target_and_interface(target_id, interface_id)
        broadcast_routing_change(:routing_deleted, routing)
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  # ===========================================================================
  # Listing Operations
  # ===========================================================================

  @doc """
  Lists all routings for an interface.
  """
  @spec list_for_interface(interface_id()) :: [TargetInterface.t()]
  def list_for_interface(interface_id) do
    repo().list_for_interface(interface_id)
  end

  @doc """
  Lists all routings for a target.
  """
  @spec list_for_target(target_id()) :: [TargetInterface.t()]
  def list_for_target(target_id) do
    repo().list_for_target(target_id)
  end

  @doc """
  Finds a routing by target and interface IDs.
  """
  @spec find_by_target_and_interface(target_id(), interface_id()) ::
          {:ok, TargetInterface.t()} | {:error, :not_found}
  def find_by_target_and_interface(target_id, interface_id) do
    repo().find_by_target_and_interface(target_id, interface_id)
  end

  # ===========================================================================
  # Batch Operations
  # ===========================================================================

  @doc """
  Replaces all routings for an interface with a new set.

  This is useful when setting up interface routing from scratch.
  """
  @spec replace_for_interface(interface_id(), [TargetInterface.t()]) ::
          {:ok, [TargetInterface.t()]} | {:error, term()}
  def replace_for_interface(interface_id, routings) do
    case repo().replace_for_interface(interface_id, routings) do
      {:ok, saved} ->
        Enum.each(saved, &broadcast_routing_change(:routing_created, &1))
        {:ok, saved}

      error ->
        error
    end
  end

  @doc """
  Deletes all routings for an interface.
  """
  @spec delete_all_for_interface(interface_id()) :: :ok
  def delete_all_for_interface(interface_id) do
    routings = repo().list_for_interface(interface_id)
    :ok = repo().delete_all_for_interface(interface_id)
    Enum.each(routings, &broadcast_routing_change(:routing_deleted, &1))
    :ok
  end

  @doc """
  Deletes all routings for a target.
  """
  @spec delete_all_for_target(target_id()) :: :ok
  def delete_all_for_target(target_id) do
    routings = repo().list_for_target(target_id)
    :ok = repo().delete_all_for_target(target_id)
    Enum.each(routings, &broadcast_routing_change(:routing_deleted, &1))
    :ok
  end

  # ===========================================================================
  # Event Emission
  # ===========================================================================

  @doc """
  Broadcasts a routing change event.
  """
  @spec broadcast_routing_change(atom(), TargetInterface.t()) :: :ok
  def broadcast_routing_change(event_type, %TargetInterface{interface_id: interface_id} = routing) do
    topic = "interface:#{interface_id}:routing"

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {event_type, routing}
    )

    :ok
  end
end
