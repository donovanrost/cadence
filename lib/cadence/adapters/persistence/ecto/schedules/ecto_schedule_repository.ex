defmodule Cadence.Adapters.Persistence.Ecto.Schedules.EctoScheduleRepository do
  @moduledoc """
  Ecto-based implementation of the ScheduleRepository port.

  This adapter provides persistence for schedules using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :schedule_repository, Cadence.Adapters.Persistence.Ecto.Schedules.EctoScheduleRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Schedules.ScheduleRepository.impl()
      {:ok, schedule} = repo.find(id, organization_id)
  """

  @behaviour Cadence.Ports.Repository.Schedules.ScheduleRepository

  import Ecto.Query

  alias Cadence.Domain.Schedules.Entities.Schedule, as: ScheduleEntity
  alias Cadence.Repo
  alias Cadence.Schedules.Schedule, as: ScheduleSchema

  # ===========================================================================
  # ScheduleRepository Implementation
  # ===========================================================================

  @impl true
  def find(id, organization_id) do
    query =
      from s in ScheduleSchema,
        where: s.id == ^id and s.organization_id == ^organization_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def find_unscoped(id) do
    case Repo.get(ScheduleSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def list(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    procedure_id = Keyword.get(opts, :procedure_id)
    enabled_only = Keyword.get(opts, :enabled_only, false)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from s in ScheduleSchema,
        where: s.organization_id == ^organization_id,
        order_by: [asc: s.name]

    query =
      apply_filters(query,
        mission_id: mission_id,
        procedure_id: procedure_id,
        enabled_only: enabled_only
      )

    query = if limit, do: from(s in query, limit: ^limit, offset: ^offset), else: query

    query
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def list_enabled_cron do
    ScheduleSchema
    |> where([s], s.enabled == true)
    |> where([s], s.schedule_type == :cron)
    |> where([s], not is_nil(s.cron_expression))
    |> Repo.all()
    |> Enum.map(&schedule_to_cron_job/1)
  end

  @impl true
  def list_due_once do
    now = DateTime.utc_now()

    ScheduleSchema
    |> where([s], s.enabled == true)
    |> where([s], s.schedule_type == :once)
    |> where([s], s.scheduled_at <= ^now)
    |> where([s], is_nil(s.last_run_at))
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def save(%ScheduleEntity{id: nil} = entity) do
    attrs = to_schema_attrs(entity)

    %ScheduleSchema{}
    |> ScheduleSchema.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, schema} -> {:ok, to_entity(schema)}
      {:error, changeset} -> {:error, extract_errors(changeset)}
    end
  end

  def save(%ScheduleEntity{} = entity) do
    attrs = to_schema_attrs(entity)

    case Repo.get(ScheduleSchema, entity.id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> ScheduleSchema.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, to_entity(updated)}
          {:error, changeset} -> {:error, extract_errors(changeset)}
        end
    end
  end

  @impl true
  def delete(%ScheduleEntity{id: id}) do
    case Repo.get(ScheduleSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, to_entity(deleted)}
          {:error, changeset} -> {:error, extract_errors(changeset)}
        end
    end
  end

  @impl true
  def record_run(%ScheduleEntity{id: id}, next_run_at \\ nil) do
    case Repo.get(ScheduleSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> ScheduleSchema.run_changeset(%{
          last_run_at: DateTime.utc_now(),
          next_run_at: next_run_at,
          run_count: (schema.run_count || 0) + 1
        })
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, to_entity(updated)}
          {:error, changeset} -> {:error, extract_errors(changeset)}
        end
    end
  end

  @impl true
  def enable(%ScheduleEntity{id: id}) do
    case Repo.get(ScheduleSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> ScheduleSchema.changeset(%{enabled: true})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, to_entity(updated)}
          {:error, changeset} -> {:error, extract_errors(changeset)}
        end
    end
  end

  @impl true
  def disable(%ScheduleEntity{id: id}) do
    case Repo.get(ScheduleSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> ScheduleSchema.changeset(%{enabled: false})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, to_entity(updated)}
          {:error, changeset} -> {:error, extract_errors(changeset)}
        end
    end
  end

  # ===========================================================================
  # Entity Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec to_entity(ScheduleSchema.t()) :: ScheduleEntity.t()
  def to_entity(%ScheduleSchema{} = schema) do
    %ScheduleEntity{
      id: schema.id,
      name: schema.name,
      description: schema.description,
      enabled: schema.enabled,
      schedule_type: schema.schedule_type,
      cron_expression: schema.cron_expression,
      scheduled_at: schema.scheduled_at,
      timezone: schema.timezone || "UTC",
      parameters: schema.parameters || %{},
      last_run_at: schema.last_run_at,
      next_run_at: schema.next_run_at,
      run_count: schema.run_count || 0,
      procedure_id: schema.procedure_id,
      organization_id: schema.organization_id,
      mission_id: schema.mission_id,
      target_id: schema.target_id,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for Ecto changeset.
  """
  @spec to_schema_attrs(ScheduleEntity.t()) :: map()
  def to_schema_attrs(%ScheduleEntity{} = entity) do
    %{
      name: entity.name,
      description: entity.description,
      enabled: entity.enabled,
      schedule_type: entity.schedule_type,
      cron_expression: entity.cron_expression,
      scheduled_at: entity.scheduled_at,
      timezone: entity.timezone,
      parameters: entity.parameters,
      procedure_id: entity.procedure_id,
      organization_id: entity.organization_id,
      mission_id: entity.mission_id,
      target_id: entity.target_id
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:mission_id, nil}, q ->
        q

      {:mission_id, mission_id}, q ->
        from(s in q, where: s.mission_id == ^mission_id or is_nil(s.mission_id))

      {:procedure_id, nil}, q ->
        q

      {:procedure_id, procedure_id}, q ->
        from(s in q, where: s.procedure_id == ^procedure_id)

      {:enabled_only, false}, q ->
        q

      {:enabled_only, true}, q ->
        from(s in q, where: s.enabled == true)
    end)
  end

  defp schedule_to_cron_job(%ScheduleSchema{} = schema) do
    {schema.cron_expression,
     {Cadence.Schedules.Workers.ExecuteScheduleWorker,
      [schedule_id: schema.id, name: "schedule:#{schema.id}"]}}
  end

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    {:validation,
     Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
       Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
         opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
       end)
     end)}
  end
end
