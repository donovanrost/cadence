defmodule Cadence.Adapters.Persistence.Ecto.Interfaces.EctoTargetInterfaceRepository do
  @moduledoc """
  Ecto-based implementation of the TargetInterfaceRepository port.

  This adapter manages the routing associations between targets and interfaces,
  providing persistence using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :target_interface_repository, Cadence.Adapters.Persistence.Ecto.Interfaces.EctoTargetInterfaceRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Interfaces.TargetInterfaceRepository.impl()
      routings = repo.list_for_interface(interface_id)
  """

  @behaviour Cadence.Ports.Repository.Interfaces.TargetInterfaceRepository

  import Ecto.Query

  alias Cadence.Domain.Interfaces.Entities.TargetInterface, as: TargetInterfaceEntity
  alias Cadence.Interfaces.TargetInterface, as: TargetInterfaceSchema
  alias Cadence.Repo

  # ===========================================================================
  # TargetInterface CRUD Operations
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(TargetInterfaceSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def find_by_target_and_interface(target_id, interface_id) do
    query =
      from t in TargetInterfaceSchema,
        where: t.target_id == ^target_id,
        where: t.interface_id == ^interface_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def save(%TargetInterfaceEntity{id: nil} = entity) do
    attrs = entity_to_schema_attrs(entity)

    %TargetInterfaceSchema{}
    |> TargetInterfaceSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%TargetInterfaceEntity{id: id} = entity) do
    case Repo.get(TargetInterfaceSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> TargetInterfaceSchema.changeset(entity_to_schema_attrs(entity))
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def delete(id) do
    case Repo.get(TargetInterfaceSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, schema_to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @impl true
  def delete_by_target_and_interface(target_id, interface_id) do
    query =
      from t in TargetInterfaceSchema,
        where: t.target_id == ^target_id,
        where: t.interface_id == ^interface_id

    Repo.delete_all(query)
    :ok
  end

  # ===========================================================================
  # Listing Operations
  # ===========================================================================

  @impl true
  def list_for_interface(interface_id) do
    query =
      from t in TargetInterfaceSchema,
        where: t.interface_id == ^interface_id

    query
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def list_for_target(target_id) do
    query =
      from t in TargetInterfaceSchema,
        where: t.target_id == ^target_id

    query
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def get_target_ids_for_interface(interface_id) do
    query =
      from t in TargetInterfaceSchema,
        join: target in assoc(t, :target),
        where: t.interface_id == ^interface_id,
        select: target.identifier

    Repo.all(query)
  end

  @impl true
  def get_interface_ids_for_target(target_id) do
    query =
      from t in TargetInterfaceSchema,
        where: t.target_id == ^target_id,
        select: t.interface_id

    Repo.all(query)
  end

  # ===========================================================================
  # Batch Operations
  # ===========================================================================

  @impl true
  def replace_for_interface(interface_id, routings) do
    Repo.transact(fn ->
      # Delete existing
      delete_all_for_interface(interface_id)

      # Insert new
      results =
        Enum.map(routings, fn routing ->
          attrs =
            routing
            |> entity_to_schema_attrs()
            |> Map.put(:interface_id, interface_id)

          %TargetInterfaceSchema{}
          |> TargetInterfaceSchema.changeset(attrs)
          |> Repo.insert()
        end)

      errors = Enum.filter(results, &match?({:error, _}, &1))

      if Enum.empty?(errors) do
        {:ok, Enum.map(results, fn {:ok, schema} -> schema_to_entity(schema) end)}
      else
        {:error, hd(errors)}
      end
    end)
  end

  @impl true
  def delete_all_for_interface(interface_id) do
    query = from t in TargetInterfaceSchema, where: t.interface_id == ^interface_id
    Repo.delete_all(query)
    :ok
  end

  @impl true
  def delete_all_for_target(target_id) do
    query = from t in TargetInterfaceSchema, where: t.target_id == ^target_id
    Repo.delete_all(query)
    :ok
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec schema_to_entity(TargetInterfaceSchema.t()) :: TargetInterfaceEntity.t()
  def schema_to_entity(%TargetInterfaceSchema{} = schema) do
    TargetInterfaceEntity.from_persistence(%{
      id: schema.id,
      target_id: schema.target_id,
      interface_id: schema.interface_id,
      direction: schema.direction,
      scid: schema.scid,
      tc_stream_id: schema.tc_stream_id,
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    })
  end

  @doc """
  Converts a domain entity to schema attributes for persistence.
  """
  @spec entity_to_schema_attrs(TargetInterfaceEntity.t()) :: map()
  def entity_to_schema_attrs(%TargetInterfaceEntity{} = entity) do
    %{
      target_id: entity.target_id,
      interface_id: entity.interface_id,
      direction: Atom.to_string(entity.direction),
      scid: entity.scid,
      tc_stream_id: entity.tc_stream_id
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp handle_result({:ok, schema}), do: {:ok, schema_to_entity(schema)}
  defp handle_result({:error, changeset}), do: {:error, extract_errors(changeset)}

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    {:validation, errors}
  end
end
