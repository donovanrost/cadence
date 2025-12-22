defmodule Cadence.Adapters.Persistence.Ecto.DashboardLayouts.EctoDashboardLayoutRepository do
  @moduledoc """
  Ecto-based implementation of the DashboardLayoutRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for dashboard layouts using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :dashboard_layout_repository,
        Cadence.Adapters.Persistence.Ecto.DashboardLayouts.EctoDashboardLayoutRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.DashboardLayouts.DashboardLayoutRepository.impl()
      {:ok, layout} = repo.find(id)
  """

  @behaviour Cadence.Ports.Repository.DashboardLayouts.DashboardLayoutRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.DashboardLayouts.DashboardLayout, as: DashboardLayoutSchema
  alias Cadence.Domain.DashboardLayouts.Entities.DashboardLayout, as: DashboardLayoutEntity

  # ===========================================================================
  # DashboardLayoutRepository Implementation
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(DashboardLayoutSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def find_for_user(id, user_id) do
    query =
      from l in DashboardLayoutSchema,
        where: l.id == ^id and l.user_id == ^user_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def find_user_layout(user_id, mission_id) do
    query =
      from l in DashboardLayoutSchema,
        where: l.user_id == ^user_id and l.mission_id == ^mission_id,
        order_by: [desc: l.is_default, desc: l.updated_at],
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def find_user_default(user_id) do
    query =
      from l in DashboardLayoutSchema,
        where: l.user_id == ^user_id and is_nil(l.mission_id) and l.is_default == true,
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def list_for_user(user_id, mission_id) do
    query =
      from l in DashboardLayoutSchema,
        where: l.user_id == ^user_id and l.mission_id == ^mission_id,
        order_by: [desc: l.is_default, asc: l.name]

    query
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def save(%DashboardLayoutEntity{id: nil} = entity) do
    attrs = to_schema_attrs(entity)

    %DashboardLayoutSchema{}
    |> DashboardLayoutSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%DashboardLayoutEntity{id: id} = entity) do
    case Repo.get(DashboardLayoutSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> DashboardLayoutSchema.changeset(to_schema_attrs(entity))
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def delete(id) do
    case Repo.get(DashboardLayoutSchema, id) do
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
  def unset_other_defaults(user_id, mission_id, exclude_id) do
    query =
      from l in DashboardLayoutSchema,
        where:
          l.user_id == ^user_id and
            l.mission_id == ^mission_id and
            l.id != ^exclude_id

    {count, _} = Repo.update_all(query, set: [is_default: false])
    {:ok, count}
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec to_entity(DashboardLayoutSchema.t()) :: DashboardLayoutEntity.t()
  def to_entity(%DashboardLayoutSchema{} = schema) do
    %DashboardLayoutEntity{
      id: schema.id,
      name: schema.name,
      user_id: schema.user_id,
      mission_id: schema.mission_id,
      is_default: schema.is_default || false,
      frame_layout: schema.frame_layout,
      widgets: schema.widgets || [],
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for persistence.
  """
  @spec to_schema_attrs(DashboardLayoutEntity.t()) :: map()
  def to_schema_attrs(%DashboardLayoutEntity{} = entity) do
    %{
      name: entity.name,
      user_id: entity.user_id,
      mission_id: entity.mission_id,
      is_default: entity.is_default,
      frame_layout: entity.frame_layout,
      widgets: entity.widgets
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp handle_result({:ok, schema}), do: {:ok, to_entity(schema)}
  defp handle_result({:error, changeset}), do: {:error, extract_errors(changeset)}

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    {:validation,
     Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
       Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
         opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
       end)
     end)}
  end
end
