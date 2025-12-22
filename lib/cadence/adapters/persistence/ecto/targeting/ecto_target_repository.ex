defmodule Cadence.Adapters.Persistence.Ecto.Targeting.EctoTargetRepository do
  @moduledoc """
  Ecto-based implementation of the TargetRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for targets using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :target_repository, Cadence.Adapters.Persistence.Ecto.Targeting.EctoTargetRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Targeting.TargetRepository.impl()
      {:ok, target} = repo.find(id, mission_id)
  """

  @behaviour Cadence.Ports.Repository.Targeting.TargetRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Targets.Target, as: TargetSchema
  alias Cadence.Domain.Targeting.Entities.Target, as: TargetEntity

  # ===========================================================================
  # TargetRepository Implementation
  # ===========================================================================

  @impl true
  def find(id, mission_id) do
    query =
      from t in TargetSchema,
        where: t.id == ^id and t.mission_id == ^mission_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def find_unscoped(id) do
    case Repo.get(TargetSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def find_by_identifier(mission_id, identifier) do
    query =
      from t in TargetSchema,
        where: t.mission_id == ^mission_id and t.identifier == ^identifier

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def save(%TargetEntity{id: nil} = entity) do
    attrs = to_schema_attrs(entity)

    %TargetSchema{}
    |> TargetSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%TargetEntity{id: id} = entity) do
    case Repo.get(TargetSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> update_changeset(entity)
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def delete(id) do
    case Repo.get(TargetSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @impl true
  def list(mission_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    type = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    preloads = Keyword.get(opts, :preload, [])

    query =
      from t in TargetSchema,
        where: t.mission_id == ^mission_id,
        order_by: [asc: t.name],
        limit: ^limit,
        offset: ^offset

    query = apply_filters(query, status: status, type: type)
    query = if Enum.any?(preloads), do: from(t in query, preload: ^preloads), else: query

    query
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def list_by_definition_set(definition_set_id) do
    from(t in TargetSchema,
      where: t.definition_set_id == ^definition_set_id,
      order_by: [asc: t.name]
    )
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def update_circuit_breaker(id, changes) do
    case Repo.get(TargetSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        attrs = %{
          circuit_breaker_status: Map.get(changes, :status, schema.circuit_breaker_status),
          circuit_breaker_failures: Map.get(changes, :failures, schema.circuit_breaker_failures),
          circuit_breaker_opened_at: Map.get(changes, :opened_at, schema.circuit_breaker_opened_at)
        }

        schema
        |> TargetSchema.circuit_breaker_changeset(attrs)
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def get_definition_set_id(mission_id, identifier) do
    query =
      from t in TargetSchema,
        where: t.mission_id == ^mission_id and t.identifier == ^identifier,
        select: t.definition_set_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      definition_set_id -> {:ok, definition_set_id}
    end
  end

  @impl true
  def get_definition_set_id_by_target_id(id) do
    query =
      from t in TargetSchema,
        where: t.id == ^id,
        select: t.definition_set_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      definition_set_id -> {:ok, definition_set_id}
    end
  end

  @impl true
  def find_with_definition_set(id) do
    query =
      from t in TargetSchema,
        where: t.id == ^id,
        preload: [:definition_set]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec to_entity(TargetSchema.t()) :: TargetEntity.t()
  def to_entity(%TargetSchema{} = schema) do
    %TargetEntity{
      id: schema.id,
      mission_id: schema.mission_id,
      definition_set_id: schema.definition_set_id,
      bucket_id: schema.bucket_id,
      name: schema.name,
      identifier: schema.identifier,
      type: normalize_type(schema.type),
      status: normalize_status(schema.status),
      config: schema.config || %{},
      metadata: schema.metadata || %{},
      active_limit_set: schema.active_limit_set || "NOMINAL",
      circuit_breaker_status: normalize_circuit_breaker_status(schema.circuit_breaker_status),
      circuit_breaker_failures: schema.circuit_breaker_failures || 0,
      circuit_breaker_opened_at: schema.circuit_breaker_opened_at,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for insertion.
  """
  @spec to_schema_attrs(TargetEntity.t()) :: map()
  def to_schema_attrs(%TargetEntity{} = entity) do
    %{
      mission_id: entity.mission_id,
      definition_set_id: entity.definition_set_id,
      bucket_id: entity.bucket_id,
      name: entity.name,
      identifier: entity.identifier,
      type: Atom.to_string(entity.type),
      status: Atom.to_string(entity.status),
      config: entity.config,
      metadata: entity.metadata,
      active_limit_set: entity.active_limit_set,
      circuit_breaker_status: Atom.to_string(entity.circuit_breaker_status),
      circuit_breaker_failures: entity.circuit_breaker_failures,
      circuit_breaker_opened_at: entity.circuit_breaker_opened_at
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp update_changeset(schema, entity) do
    import Ecto.Changeset

    attrs = %{
      name: entity.name,
      status: Atom.to_string(entity.status),
      config: entity.config,
      metadata: entity.metadata,
      active_limit_set: entity.active_limit_set,
      definition_set_id: entity.definition_set_id,
      bucket_id: entity.bucket_id,
      circuit_breaker_status: Atom.to_string(entity.circuit_breaker_status),
      circuit_breaker_failures: entity.circuit_breaker_failures,
      circuit_breaker_opened_at: entity.circuit_breaker_opened_at
    }

    schema
    |> cast(attrs, Map.keys(attrs))
  end

  defp handle_result({:ok, schema}), do: {:ok, to_entity(schema)}
  defp handle_result({:error, changeset}), do: {:error, extract_errors(changeset)}

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, nil}, q -> q
      {:status, statuses}, q when is_list(statuses) -> from(t in q, where: t.status in ^statuses)
      {:status, status}, q -> from(t in q, where: t.status == ^status)
      {:type, nil}, q -> q
      {:type, types}, q when is_list(types) -> from(t in q, where: t.type in ^types)
      {:type, type}, q -> from(t in q, where: t.type == ^type)
    end)
  end

  defp normalize_type("spacecraft"), do: :spacecraft
  defp normalize_type("ground_station"), do: :ground_station
  defp normalize_type("simulator"), do: :simulator
  defp normalize_type("relay"), do: :relay
  defp normalize_type(type) when is_atom(type), do: type
  defp normalize_type(_), do: :spacecraft

  defp normalize_status("offline"), do: :offline
  defp normalize_status("online"), do: :online
  defp normalize_status("standby"), do: :standby
  defp normalize_status("fault"), do: :fault
  defp normalize_status(status) when is_atom(status), do: status
  defp normalize_status(_), do: :offline

  defp normalize_circuit_breaker_status("closed"), do: :closed
  defp normalize_circuit_breaker_status("open"), do: :open
  defp normalize_circuit_breaker_status("half_open"), do: :half_open
  defp normalize_circuit_breaker_status(status) when is_atom(status), do: status
  defp normalize_circuit_breaker_status(_), do: :closed
end
