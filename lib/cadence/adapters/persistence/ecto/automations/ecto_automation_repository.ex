defmodule Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationRepository do
  @moduledoc """
  Ecto-based implementation of the AutomationRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for automations using PostgreSQL.
  """

  @behaviour Cadence.Ports.Repository.Automations.AutomationRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Automations.Automation, as: AutomationSchema
  alias Cadence.Domain.Automations.Entities.Automation, as: AutomationEntity

  # ===========================================================================
  # AutomationRepository Implementation
  # ===========================================================================

  @impl true
  def find(id, organization_id) do
    query =
      from a in AutomationSchema,
        where: a.id == ^id and a.organization_id == ^organization_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def find_unscoped(id) do
    case Repo.get(AutomationSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def list(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    enabled_only = Keyword.get(opts, :enabled_only, false)
    trigger_type = Keyword.get(opts, :trigger_type)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from a in AutomationSchema,
        where: a.organization_id == ^organization_id,
        order_by: [asc: a.name]

    query =
      apply_filters(query,
        mission_id: mission_id,
        enabled_only: enabled_only,
        trigger_type: trigger_type
      )

    query = if limit, do: from(a in query, limit: ^limit, offset: ^offset), else: query

    query
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def list_enabled_for_mission(organization_id, mission_id) do
    from(a in AutomationSchema,
      where: a.organization_id == ^organization_id,
      where: a.mission_id == ^mission_id or is_nil(a.mission_id),
      where: a.enabled == true,
      order_by: [asc: a.name]
    )
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def save(%AutomationEntity{id: nil} = entity) do
    attrs = to_schema_attrs(entity)

    %AutomationSchema{}
    |> AutomationSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%AutomationEntity{id: id} = entity) do
    case Repo.get(AutomationSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> AutomationSchema.changeset(to_schema_attrs(entity))
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def delete(%AutomationEntity{id: nil}) do
    {:error, :not_persisted}
  end

  def delete(%AutomationEntity{id: id}) do
    case Repo.get(AutomationSchema, id) do
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
  def record_trigger(%AutomationEntity{id: nil}) do
    {:error, :not_persisted}
  end

  def record_trigger(%AutomationEntity{id: id} = entity) do
    case Repo.get(AutomationSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> AutomationSchema.trigger_changeset(%{
          last_triggered_at: DateTime.utc_now(),
          trigger_count: entity.trigger_count + 1
        })
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def enable(%AutomationEntity{id: nil}) do
    {:error, :not_persisted}
  end

  def enable(%AutomationEntity{id: id}) do
    case Repo.get(AutomationSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> AutomationSchema.changeset(%{enabled: true})
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def disable(%AutomationEntity{id: nil}) do
    {:error, :not_persisted}
  end

  def disable(%AutomationEntity{id: id}) do
    case Repo.get(AutomationSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> AutomationSchema.changeset(%{enabled: false})
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
  @spec to_entity(AutomationSchema.t()) :: AutomationEntity.t()
  def to_entity(%AutomationSchema{} = schema) do
    %AutomationEntity{
      id: schema.id,
      name: schema.name,
      description: schema.description,
      enabled: schema.enabled,
      trigger_type: safe_to_atom(schema.trigger_type),
      trigger_conditions: schema.trigger_conditions || %{},
      action_type: safe_to_atom(schema.action_type),
      action_config: schema.action_config || %{},
      cooldown_seconds: schema.cooldown_seconds || 0,
      max_executions_per_hour: schema.max_executions_per_hour,
      last_triggered_at: schema.last_triggered_at,
      trigger_count: schema.trigger_count || 0,
      organization_id: schema.organization_id,
      mission_id: schema.mission_id,
      target_id: schema.target_id,
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for persistence.
  """
  @spec to_schema_attrs(AutomationEntity.t()) :: map()
  def to_schema_attrs(%AutomationEntity{} = entity) do
    %{
      name: entity.name,
      description: entity.description,
      enabled: entity.enabled,
      trigger_type: to_string(entity.trigger_type),
      trigger_conditions: entity.trigger_conditions,
      action_type: to_string(entity.action_type),
      action_config: entity.action_config,
      cooldown_seconds: entity.cooldown_seconds,
      max_executions_per_hour: entity.max_executions_per_hour,
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
        from(a in q, where: a.mission_id == ^mission_id or is_nil(a.mission_id))

      {:enabled_only, false}, q ->
        q

      {:enabled_only, true}, q ->
        from(a in q, where: a.enabled == true)

      {:trigger_type, nil}, q ->
        q

      {:trigger_type, trigger_type}, q ->
        from(a in q, where: a.trigger_type == ^trigger_type)
    end)
  end

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

  defp safe_to_atom(nil), do: nil
  defp safe_to_atom(value) when is_atom(value), do: value
  defp safe_to_atom(value) when is_binary(value), do: String.to_existing_atom(value)
end
