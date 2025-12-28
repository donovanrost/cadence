defmodule Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationExecutionRepository do
  @moduledoc """
  Ecto-based implementation of the AutomationExecutionRepository port.

  This adapter provides persistence for automation execution tracking using PostgreSQL.
  """

  @behaviour Cadence.Ports.Repository.Automations.AutomationExecutionRepository

  import Ecto.Query

  alias Cadence.Automations.AutomationExecution, as: ExecutionSchema
  alias Cadence.Domain.Automations.Entities.AutomationExecution, as: ExecutionEntity
  alias Cadence.Repo

  # ===========================================================================
  # AutomationExecutionRepository Implementation
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(ExecutionSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def find_with_automation(id) do
    case Repo.get(ExecutionSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema = Repo.preload(schema, [:automation])
        {:ok, to_entity(schema)}
    end
  end

  @impl true
  def list(opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    automation_id = Keyword.get(opts, :automation_id)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    ExecutionSchema
    |> maybe_filter(:organization_id, organization_id)
    |> maybe_filter(:mission_id, mission_id)
    |> maybe_filter(:automation_id, automation_id)
    |> maybe_filter(:status, status)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def count_recent(automation_id, since) do
    ExecutionSchema
    |> where([e], e.automation_id == ^automation_id)
    |> where([e], e.inserted_at >= ^since)
    |> select([e], count(e.id))
    |> Repo.one()
  end

  @impl true
  def save(%ExecutionEntity{id: nil} = entity) do
    attrs = to_schema_attrs(entity)

    %ExecutionSchema{}
    |> ExecutionSchema.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, schema} ->
        {:ok, to_entity(schema)}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :idempotency_key) do
          {:error, :duplicate}
        else
          {:error, extract_errors(changeset)}
        end
    end
  end

  def save(%ExecutionEntity{id: id} = entity) do
    case Repo.get(ExecutionSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> ExecutionSchema.status_changeset(to_status_attrs(entity))
        |> Repo.update()
        |> handle_result()
    end
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec to_entity(ExecutionSchema.t()) :: ExecutionEntity.t()
  def to_entity(%ExecutionSchema{} = schema) do
    %ExecutionEntity{
      id: schema.id,
      status: schema.status,
      trigger_event: schema.trigger_event,
      action_result: schema.action_result,
      error_message: schema.error_message,
      started_at: schema.started_at,
      completed_at: schema.completed_at,
      idempotency_key: schema.idempotency_key,
      automation_id: schema.automation_id,
      organization_id: schema.organization_id,
      mission_id: schema.mission_id,
      procedure_execution_id: schema.procedure_execution_id,
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for initial persistence.
  """
  @spec to_schema_attrs(ExecutionEntity.t()) :: map()
  def to_schema_attrs(%ExecutionEntity{} = entity) do
    %{
      status: entity.status,
      trigger_event: entity.trigger_event,
      action_result: entity.action_result,
      error_message: entity.error_message,
      started_at: entity.started_at,
      completed_at: entity.completed_at,
      idempotency_key: entity.idempotency_key,
      automation_id: entity.automation_id,
      organization_id: entity.organization_id,
      mission_id: entity.mission_id,
      procedure_execution_id: entity.procedure_execution_id
    }
  end

  @doc """
  Converts entity to status update attributes.
  """
  @spec to_status_attrs(ExecutionEntity.t()) :: map()
  def to_status_attrs(%ExecutionEntity{} = entity) do
    %{
      status: entity.status,
      action_result: entity.action_result,
      error_message: entity.error_message,
      started_at: entity.started_at,
      completed_at: entity.completed_at,
      procedure_execution_id: entity.procedure_execution_id
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

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
