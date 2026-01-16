defmodule Cadence.Adapters.Persistence.Ecto.Interfaces.EctoInterfaceRepository do
  @moduledoc """
  Ecto-based implementation of the InterfaceRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for interfaces using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :interface_repository, Cadence.Adapters.Persistence.Ecto.Interfaces.EctoInterfaceRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Interfaces.InterfaceRepository.impl()
      {:ok, interface} = repo.find(id)
  """

  @behaviour Cadence.Ports.Repository.Interfaces.InterfaceRepository

  import Ecto.Query

  alias Cadence.Domain.Interfaces.Entities.Interface, as: InterfaceEntity
  alias Cadence.Interfaces.InterfaceSchema
  alias Cadence.Interfaces.TargetInterface, as: TargetInterfaceSchema
  alias Cadence.Repo

  # ===========================================================================
  # Interface CRUD Operations
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(InterfaceSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def find_by_name(mission_id, name) do
    query =
      from i in InterfaceSchema,
        where: i.mission_id == ^mission_id,
        where: i.name == ^name

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def save(%InterfaceEntity{id: nil} = entity) do
    attrs = entity_to_schema_attrs(entity)

    with {:ok, schema} <- insert_interface(attrs) do
      {:ok, schema_to_entity(schema)}
    end
  end

  def save(%InterfaceEntity{id: id} = entity) do
    case Repo.get(InterfaceSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        with {:ok, updated} <- update_interface(schema, entity) do
          {:ok, schema_to_entity(updated)}
        end
    end
  end

  @impl true
  def delete(id) do
    case Repo.get(InterfaceSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        delete_target_associations(id)

        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, schema_to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  # ===========================================================================
  # Listing Operations
  # ===========================================================================

  @impl true
  def list_for_mission(mission_id, opts \\ []) do
    connection_type = Keyword.get(opts, :connection_type)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from i in InterfaceSchema,
        where: i.mission_id == ^mission_id,
        order_by: [asc: i.name],
        limit: ^limit,
        offset: ^offset

    query = apply_connection_type_filter(query, connection_type)

    query
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def list(opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    connection_type = Keyword.get(opts, :connection_type)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from i in InterfaceSchema,
        order_by: [asc: i.name],
        limit: ^limit,
        offset: ^offset

    query = apply_mission_filter(query, mission_id)
    query = apply_connection_type_filter(query, connection_type)

    query
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  # ===========================================================================
  # Counting Operations
  # ===========================================================================

  @impl true
  def count_for_mission(mission_id) do
    query =
      from i in InterfaceSchema,
        where: i.mission_id == ^mission_id,
        select: count(i.id)

    Repo.one(query) || 0
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec schema_to_entity(InterfaceSchema.t()) :: InterfaceEntity.t()
  def schema_to_entity(%InterfaceSchema{} = schema) do
    target_ids = get_target_ids(schema.id)

    InterfaceEntity.from_persistence(%{
      id: schema.id,
      mission_id: schema.mission_id,
      name: schema.name,
      connection_type: schema.connection_type,
      host: schema.host,
      port: schema.port,
      bind_address: schema.bind_address,
      bind_port: schema.bind_port,
      auto_reconnect: schema.auto_reconnect,
      reconnect_delay_ms: schema.reconnect_delay_ms,
      config: schema.config || %{},
      metadata: schema.metadata || %{},
      target_ids: target_ids,
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    })
  end

  @doc """
  Converts a domain entity to schema attributes for persistence.
  """
  @spec entity_to_schema_attrs(InterfaceEntity.t()) :: map()
  def entity_to_schema_attrs(%InterfaceEntity{} = entity) do
    %{
      mission_id: entity.mission_id,
      name: entity.name,
      connection_type: Atom.to_string(entity.connection_type),
      host: entity.host,
      port: entity.port,
      bind_address: entity.bind_address,
      bind_port: entity.bind_port,
      auto_reconnect: entity.auto_reconnect,
      reconnect_delay_ms: entity.reconnect_delay_ms,
      config: entity.config,
      metadata: entity.metadata
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp insert_interface(attrs) do
    %InterfaceSchema{}
    |> InterfaceSchema.changeset(attrs)
    |> Repo.insert()
  end

  defp update_interface(schema, entity) do
    schema
    |> InterfaceSchema.update_changeset(entity_to_schema_attrs(entity))
    |> Repo.update()
  end

  defp delete_target_associations(interface_id) do
    query = from t in TargetInterfaceSchema, where: t.interface_id == ^interface_id
    Repo.delete_all(query)
    :ok
  end

  defp get_target_ids(interface_id) do
    query =
      from t in TargetInterfaceSchema,
        join: target in assoc(t, :target),
        where: t.interface_id == ^interface_id,
        select: target.identifier

    Repo.all(query)
  end

  defp apply_mission_filter(query, nil), do: query

  defp apply_mission_filter(query, mission_id) do
    from i in query, where: i.mission_id == ^mission_id
  end

  defp apply_connection_type_filter(query, nil), do: query

  defp apply_connection_type_filter(query, type) when is_atom(type) do
    type_string = Atom.to_string(type)
    from i in query, where: i.connection_type == ^type_string
  end

  defp apply_connection_type_filter(query, type) when is_binary(type) do
    from i in query, where: i.connection_type == ^type
  end
end
