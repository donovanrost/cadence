defmodule Cadence.Interfaces do
  @moduledoc """
  The Interfaces context - facade for interface-related operations.

  This module delegates to hexagonal architecture application services while
  maintaining backward compatibility with existing code that uses Ecto schemas.

  ## Architecture

  This context is built on hexagonal architecture with the following layers:

  - **Domain**: `Cadence.Domain.Interfaces.Entities.*` - Pure business entities
  - **Ports**: `Cadence.Ports.Repository.Interfaces.*` - Repository contracts
  - **Adapters**: `Cadence.Adapters.Persistence.Ecto.Interfaces.*` - Ecto implementations
  - **Application**: `Cadence.Application.Interfaces.*` - Use case orchestration

  ## For New Code

  Prefer using the application services directly:

      alias Cadence.Application.Interfaces.{InterfaceQueries, InterfaceOperations}

      # Create interface
      {:ok, interface} = InterfaceOperations.create(attrs)

  ## Data Plane Compatibility

  The hexagonal layer emits PubSub events on configuration changes,
  enabling future Data Plane / Control Plane architecture:

      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:\#{mission_id}:interface_config")

      def handle_info({:interface_updated, interface}, state) do
        # Reload interface GenServer with new config
      end

  ## Legacy Support

  Functions in this module maintain backward compatibility with existing code
  that works with Ecto schemas directly.
  """

  import Ecto.Query, warn: false
  # Application services for new hexagonal architecture
  alias Cadence.Application.Interfaces.InterfaceOperations
  alias Cadence.Application.Interfaces.InterfaceQueries
  alias Cadence.Application.Interfaces.RoutingOperations
  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity
  alias Cadence.Interfaces.InterfaceSchema
  alias Cadence.Interfaces.InterfaceVcid
  alias Cadence.Interfaces.TargetInterface
  alias Cadence.Missions.Mission
  alias Cadence.Repo

  ## Interface CRUD

  @doc """
  Returns the list of interfaces for a mission.
  """
  def list_interfaces(%Mission{id: mission_id}) do
    list_interfaces(mission_id)
  end

  def list_interfaces(%MissionEntity{id: mission_id}) do
    list_interfaces(mission_id)
  end

  def list_interfaces(mission_id) when is_binary(mission_id) do
    InterfaceSchema
    |> where([i], i.mission_id == ^mission_id)
    |> order_by([i], i.name)
    |> Repo.all()
  end

  @doc """
  Gets a single interface.

  Returns `nil` if the Interface does not exist.
  """
  def get_interface(id), do: Repo.get(InterfaceSchema, id)

  @doc """
  Gets a single interface.

  Raises `Ecto.NoResultsError` if the Interface does not exist.
  """
  def get_interface!(id), do: Repo.get!(InterfaceSchema, id)

  @doc """
  Gets an interface by name within a mission.

  Accepts either a `%Mission{}` struct or a mission ID string.
  """
  def get_interface_by_name(mission_or_id, name)

  def get_interface_by_name(%Mission{id: mission_id}, name) do
    InterfaceSchema
    |> where([i], i.mission_id == ^mission_id and i.name == ^name)
    |> Repo.one()
  end

  def get_interface_by_name(mission_id, name) when is_binary(mission_id) do
    InterfaceSchema
    |> where([i], i.mission_id == ^mission_id and i.name == ^name)
    |> Repo.one()
  end

  @doc """
  Creates an interface.
  """
  def create_interface(attrs \\ %{}) do
    %InterfaceSchema{}
    |> InterfaceSchema.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an interface.
  """
  def update_interface(%InterfaceSchema{} = interface, attrs) do
    interface
    |> InterfaceSchema.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an interface.
  """
  def delete_interface(%InterfaceSchema{} = interface) do
    Repo.delete(interface)
  end

  ## Status Management

  @doc """
  Marks an interface as connected.
  """
  def mark_connected(%InterfaceSchema{} = interface) do
    interface
    |> InterfaceSchema.mark_connected()
    |> Repo.update()
  end

  @doc """
  Marks an interface as disconnected.
  """
  def mark_disconnected(%InterfaceSchema{} = interface, reason \\ nil) do
    interface
    |> InterfaceSchema.mark_disconnected(reason)
    |> Repo.update()
  end

  @doc """
  Marks an interface as in error state.
  """
  def mark_error(%InterfaceSchema{} = interface, error) do
    interface
    |> InterfaceSchema.mark_error(error)
    |> Repo.update()
  end

  @doc """
  Updates interface status directly.
  """
  def update_status(%InterfaceSchema{} = interface, status, metadata \\ %{}) do
    interface
    |> InterfaceSchema.status_changeset(%{status: status, metadata: metadata})
    |> Repo.update()
  end

  ## Target-Interface Routing

  @doc """
  Associates a target with an interface for data routing.

  Direction can be:
  - "read" - telemetry flows from target through this interface
  - "write" - commands flow to target through this interface
  - "read_write" - bidirectional

  ## Examples

      iex> add_target_to_interface(target, interface, "read")
      {:ok, %TargetInterface{}}

      iex> add_target_to_interface(target, interface, "invalid")
      {:error, %Ecto.Changeset{}}
  """
  def add_target_to_interface(target, interface, direction) do
    %TargetInterface{}
    |> TargetInterface.changeset(%{
      target_id: target.id,
      interface_id: interface.id,
      direction: direction
    })
    |> Repo.insert()
  end

  @doc """
  Removes a target-interface association.
  """
  def remove_target_from_interface(target, interface) do
    TargetInterface
    |> where([ti], ti.target_id == ^target.id and ti.interface_id == ^interface.id)
    |> Repo.delete_all()
  end

  @doc """
  Lists all interfaces for a target.

  Options:
  - `:direction` - filter by direction ("read", "write", "read_write")
  - `:preload` - preload associations (default: true)

  ## Examples

      # Get all interfaces for a target
      list_interfaces_for_target(target)

      # Get only read interfaces (for telemetry)
      list_interfaces_for_target(target, direction: "read")

      # Get write interfaces (for commanding)
      list_interfaces_for_target(target, direction: "write")
  """
  def list_interfaces_for_target(target, opts \\ []) do
    direction = Keyword.get(opts, :direction)
    preload = Keyword.get(opts, :preload, true)

    query =
      from ti in TargetInterface,
        where: ti.target_id == ^target.id,
        join: i in InterfaceSchema,
        on: ti.interface_id == i.id,
        select: i

    query =
      if direction do
        # For read/write, also include read_write interfaces
        if direction in ["read", "write"] do
          from [ti, i] in query,
            where: ti.direction == ^direction or ti.direction == "read_write"
        else
          from [ti, i] in query, where: ti.direction == ^direction
        end
      else
        query
      end

    results = Repo.all(query)

    if preload do
      Repo.preload(results, [:mission])
    else
      results
    end
  end

  @doc """
  Lists all targets for an interface.

  Options:
  - `:direction` - filter by direction ("read", "write", "read_write")
  - `:preload` - preload associations (default: true)
  """
  def list_targets_for_interface(interface, opts \\ []) do
    direction = Keyword.get(opts, :direction)
    preload = Keyword.get(opts, :preload, true)

    query =
      from ti in TargetInterface,
        where: ti.interface_id == ^interface.id,
        join: t in Cadence.Targets.Target,
        on: ti.target_id == t.id,
        select: t

    query =
      if direction do
        if direction in ["read", "write"] do
          from [ti, t] in query,
            where: ti.direction == ^direction or ti.direction == "read_write"
        else
          from [ti, t] in query, where: ti.direction == ^direction
        end
      else
        query
      end

    results = Repo.all(query)

    if preload do
      Repo.preload(results, [:mission])
    else
      results
    end
  end

  @doc """
  Lists target-interface mappings for an interface with target preloaded.
  """
  def list_target_interfaces_for_interface(%InterfaceSchema{id: interface_id}) do
    list_target_interfaces_for_interface(interface_id)
  end

  def list_target_interfaces_for_interface(interface_id) when is_binary(interface_id) do
    TargetInterface
    |> where([ti], ti.interface_id == ^interface_id)
    |> join(:left, [ti], t in assoc(ti, :target))
    |> preload([_ti, t], target: t)
    |> order_by([_ti, t], asc: t.identifier)
    |> Repo.all()
  end

  @doc """
  Gets a target-interface mapping by ID with target preloaded.
  """
  def get_target_interface_by_id!(id) do
    TargetInterface
    |> Repo.get!(id)
    |> Repo.preload(:target)
  end

  @doc """
  Gets the target-interface association.

  Returns nil if no association exists.
  """
  def get_target_interface(target, interface) do
    TargetInterface
    |> where([ti], ti.target_id == ^target.id and ti.interface_id == ^interface.id)
    |> Repo.one()
  end

  @doc """
  Updates the direction of a target-interface association.
  """
  def update_target_interface_direction(target, interface, new_direction) do
    case get_target_interface(target, interface) do
      nil ->
        {:error, :not_found}

      target_interface ->
        target_interface
        |> TargetInterface.changeset(%{direction: new_direction})
        |> Repo.update()
    end
  end

  @doc """
  Updates the SCID for a target-interface mapping.
  """
  def update_target_interface_scid(%TargetInterface{} = target_interface, scid) do
    target_interface
    |> TargetInterface.changeset(%{scid: scid})
    |> Repo.update()
  end

  # ===========================================================================
  # VCID Mappings
  # ===========================================================================

  @doc """
  Lists VCID mappings for an interface.
  """
  def list_vcids_for_interface(%InterfaceSchema{id: interface_id}) do
    list_vcids_for_interface(interface_id)
  end

  def list_vcids_for_interface(interface_id) when is_binary(interface_id) do
    InterfaceVcid
    |> where([v], v.interface_id == ^interface_id)
    |> order_by([v], asc: v.vcid)
    |> preload([:target])
    |> Repo.all()
  end

  @doc """
  Gets a single VCID mapping by ID.
  """
  def get_interface_vcid!(id), do: Repo.get!(InterfaceVcid, id)

  @doc """
  Creates a VCID mapping for an interface.
  """
  def create_interface_vcid(%InterfaceSchema{id: interface_id}, attrs) do
    attrs = Map.put(attrs, "interface_id", interface_id)

    %InterfaceVcid{}
    |> InterfaceVcid.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a VCID mapping.
  """
  def update_interface_vcid(%InterfaceVcid{} = mapping, attrs) do
    mapping
    |> InterfaceVcid.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a VCID mapping.
  """
  def delete_interface_vcid(%InterfaceVcid{} = mapping) do
    Repo.delete(mapping)
  end

  # ===========================================================================
  # Domain Entity Access (New API - Returns Domain Entities)
  # ===========================================================================

  @doc """
  Finds an interface and returns a domain entity.

  Use this when you want to work with the hexagonal architecture.
  """
  @spec find_interface(String.t()) ::
          {:ok, Cadence.Domain.Interfaces.Entities.Interface.t()} | {:error, :not_found}
  def find_interface(id), do: InterfaceQueries.find(id)

  @doc """
  Lists interfaces for a mission as domain entities.
  """
  @spec list_interfaces_as_entities(String.t(), keyword()) ::
          [Cadence.Domain.Interfaces.Entities.Interface.t()]
  def list_interfaces_as_entities(mission_id, opts \\ []) do
    InterfaceQueries.list_for_mission(mission_id, opts)
  end

  @doc """
  Creates an interface using the hexagonal architecture.

  Returns a domain entity. Emits `:interface_created` event.
  """
  @spec create_interface_entity(map()) ::
          {:ok, Cadence.Domain.Interfaces.Entities.Interface.t()} | {:error, term()}
  def create_interface_entity(attrs), do: InterfaceOperations.create(attrs)

  @doc """
  Updates an interface using the hexagonal architecture.

  Returns a domain entity. Emits `:interface_updated` event.
  """
  @spec update_interface_entity(String.t(), map()) ::
          {:ok, Cadence.Domain.Interfaces.Entities.Interface.t()} | {:error, term()}
  def update_interface_entity(interface_id, attrs) do
    InterfaceOperations.update(interface_id, attrs)
  end

  @doc """
  Deletes an interface using the hexagonal architecture.

  Emits `:interface_deleted` event.
  """
  @spec delete_interface_entity(String.t()) ::
          {:ok, Cadence.Domain.Interfaces.Entities.Interface.t()} | {:error, term()}
  def delete_interface_entity(interface_id), do: InterfaceOperations.delete(interface_id)

  @doc """
  Creates a target-interface routing using the hexagonal architecture.

  Returns a domain entity. Emits `:routing_created` event.
  """
  @spec create_routing(map()) ::
          {:ok, Cadence.Domain.Interfaces.Entities.TargetInterface.t()} | {:error, term()}
  def create_routing(attrs), do: RoutingOperations.create(attrs)

  @doc """
  Lists routings for an interface as domain entities.
  """
  @spec list_routings_for_interface(String.t()) ::
          [Cadence.Domain.Interfaces.Entities.TargetInterface.t()]
  def list_routings_for_interface(interface_id) do
    RoutingOperations.list_for_interface(interface_id)
  end
end
