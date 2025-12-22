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
      {:ok, interface} = repo.find_with_protocols(id)
  """

  @behaviour Cadence.Ports.Repository.Interfaces.InterfaceRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Interfaces.InterfaceSchema
  alias Cadence.Interfaces.InterfaceProtocol, as: ProtocolSchema
  alias Cadence.Interfaces.TargetInterface, as: TargetInterfaceSchema
  alias Cadence.Domain.Interfaces.Entities.Interface, as: InterfaceEntity
  alias Cadence.Domain.Interfaces.Entities.InterfaceProtocol, as: ProtocolEntity

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
  def find_with_protocols(id) do
    query =
      from i in InterfaceSchema,
        where: i.id == ^id,
        preload: [protocols: ^from(p in ProtocolSchema, order_by: p.order)]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity_with_protocols(schema)}
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

    Repo.transact(fn ->
      with {:ok, schema} <- insert_interface(attrs),
           {:ok, _protocols} <- save_protocol_list(schema.id, entity.protocols) do
        # Reload with protocols
        case find_with_protocols(schema.id) do
          {:ok, full_entity} -> {:ok, full_entity}
          error -> error
        end
      end
    end)
  end

  def save(%InterfaceEntity{id: id} = entity) do
    case Repo.get(InterfaceSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        Repo.transact(fn ->
          with {:ok, updated} <- update_interface(schema, entity),
               :ok <- delete_protocols(id),
               {:ok, _protocols} <- save_protocol_list(id, entity.protocols) do
            {:ok, schema_to_entity_with_loaded_protocols(updated)}
          end
        end)
    end
  end

  @impl true
  def delete(id) do
    case Repo.get(InterfaceSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        # Delete protocols and target associations first
        delete_protocols(id)
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
    preload_protocols = Keyword.get(opts, :preload_protocols, false)
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

    query =
      if preload_protocols do
        from i in query,
          preload: [protocols: ^from(p in ProtocolSchema, order_by: p.order)]
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn schema ->
      if preload_protocols do
        schema_to_entity_with_protocols(schema)
      else
        schema_to_entity(schema)
      end
    end)
  end

  @impl true
  def list(opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    preload_protocols = Keyword.get(opts, :preload_protocols, false)
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

    query =
      if preload_protocols do
        from i in query,
          preload: [protocols: ^from(p in ProtocolSchema, order_by: p.order)]
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn schema ->
      if preload_protocols do
        schema_to_entity_with_protocols(schema)
      else
        schema_to_entity(schema)
      end
    end)
  end

  # ===========================================================================
  # Protocol Operations
  # ===========================================================================

  @impl true
  def save_protocols(interface_id, protocol_attrs_list) do
    Repo.transact(fn ->
      with :ok <- delete_protocols(interface_id),
           {:ok, _} <- save_protocol_list(interface_id, protocol_attrs_list) do
        find_with_protocols(interface_id)
      end
    end)
  end

  @impl true
  def delete_protocols(interface_id) do
    query = from p in ProtocolSchema, where: p.interface_id == ^interface_id
    Repo.delete_all(query)
    :ok
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
  Converts an Ecto schema to a domain entity (without protocols).
  """
  @spec schema_to_entity(InterfaceSchema.t()) :: InterfaceEntity.t()
  def schema_to_entity(%InterfaceSchema{} = schema) do
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
      protocols: [],
      target_ids: [],
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    })
  end

  @doc """
  Converts an Ecto schema with preloaded protocols to a domain entity.
  """
  @spec schema_to_entity_with_protocols(InterfaceSchema.t()) :: InterfaceEntity.t()
  def schema_to_entity_with_protocols(%InterfaceSchema{protocols: protocols} = schema)
      when is_list(protocols) do
    protocol_entities =
      protocols
      |> Enum.sort_by(& &1.order)
      |> Enum.map(&protocol_schema_to_entity/1)

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
      protocols: protocol_entities,
      target_ids: target_ids,
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    })
  end

  def schema_to_entity_with_protocols(schema) do
    # Protocols not loaded, return without them
    schema_to_entity(schema)
  end

  @doc """
  Converts a protocol schema to a domain entity.
  """
  @spec protocol_schema_to_entity(ProtocolSchema.t()) :: ProtocolEntity.t()
  def protocol_schema_to_entity(%ProtocolSchema{} = schema) do
    ProtocolEntity.from_persistence(%{
      id: schema.id,
      interface_id: schema.interface_id,
      protocol_type: schema.protocol_type,
      protocol_direction: schema.protocol_direction,
      config: schema.protocol_config || %{},
      order: schema.order,
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

  defp save_protocol_list(_interface_id, []), do: {:ok, []}

  defp save_protocol_list(interface_id, protocols) when is_list(protocols) do
    results =
      protocols
      |> Enum.with_index()
      |> Enum.map(fn {protocol, idx} ->
        attrs = protocol_to_attrs(protocol, interface_id, idx)

        %ProtocolSchema{}
        |> ProtocolSchema.changeset(attrs)
        |> Repo.insert()
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      {:ok, Enum.map(results, fn {:ok, p} -> p end)}
    else
      {:error, hd(errors)}
    end
  end

  defp protocol_to_attrs(%ProtocolEntity{} = entity, interface_id, order) do
    %{
      interface_id: interface_id,
      protocol_type: Atom.to_string(entity.protocol_type),
      protocol_direction: Atom.to_string(entity.protocol_direction),
      protocol_config: entity.config,
      order: order
    }
  end

  defp protocol_to_attrs(attrs, interface_id, order) when is_map(attrs) do
    %{
      interface_id: interface_id,
      protocol_type: to_string(attrs[:protocol_type] || attrs["protocol_type"]),
      protocol_direction:
        to_string(attrs[:protocol_direction] || attrs["protocol_direction"] || "read_write"),
      protocol_config: attrs[:config] || attrs["config"] || attrs[:protocol_config] || %{},
      order: order
    }
  end

  defp schema_to_entity_with_loaded_protocols(schema) do
    loaded =
      Repo.preload(schema, protocols: from(p in ProtocolSchema, order_by: p.order))

    schema_to_entity_with_protocols(loaded)
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
