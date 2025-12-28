defmodule Cadence.Adapters.Persistence.Ecto.Alerting.EctoAlarmRepository do
  @moduledoc """
  Ecto-based implementation of the AlarmRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for alarms using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :alarm_repository, Cadence.Adapters.Persistence.Ecto.Alerting.EctoAlarmRepository

  Then accessed via:

      repo = Application.get_env(:cadence, :alarm_repository)
      {:ok, alarm} = repo.find(id)
  """

  @behaviour Cadence.Ports.Repository.Alerting.AlarmRepository

  import Ecto.Query

  alias Cadence.Alarms.Alarm, as: AlarmSchema
  alias Cadence.Domain.Alerting.Entities.Alarm, as: AlarmEntity
  alias Cadence.Repo

  # ===========================================================================
  # AlarmRepository Implementation
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(AlarmSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def find_active_by_source(mission_id, target_id, source_type, source_id) do
    # Return not found early if required fields are nil
    if is_nil(mission_id) or is_nil(source_type) or is_nil(source_id) do
      {:error, :not_found}
    else
      query =
        from a in AlarmSchema,
          where: a.mission_id == ^mission_id,
          where: a.source_type == ^source_type,
          where: a.source_id == ^source_id,
          where: a.status in [:active, :acknowledged, :shelved]

      query =
        if target_id do
          from a in query, where: a.target_id == ^target_id
        else
          from a in query, where: is_nil(a.target_id)
        end

      case Repo.one(query) do
        nil -> {:error, :not_found}
        schema -> {:ok, to_entity(schema)}
      end
    end
  end

  @impl true
  def save(%AlarmEntity{id: nil} = entity) do
    # Insert new alarm
    attrs = to_schema_attrs(entity)

    %AlarmSchema{}
    |> AlarmSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%AlarmEntity{id: id} = entity) do
    # Update existing alarm
    case Repo.get(AlarmSchema, id) do
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
  def list(mission_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    target_id = Keyword.get(opts, :target_id)
    severity = Keyword.get(opts, :severity)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from a in AlarmSchema,
        where: a.mission_id == ^mission_id,
        order_by: [desc: a.triggered_at],
        limit: ^limit,
        offset: ^offset

    query = apply_filters(query, status: status, target_id: target_id, severity: severity)

    query
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def list_active(mission_id, opts \\ []) do
    list(mission_id, Keyword.put(opts, :status, [:active, :acknowledged, :shelved]))
  end

  @impl true
  def count_by_status(mission_id) do
    query =
      from a in AlarmSchema,
        where: a.mission_id == ^mission_id,
        group_by: a.status,
        select: {a.status, count(a.id)}

    query
    |> Repo.all()
    |> Enum.into(%{})
  end

  @impl true
  def list_expired_shelved do
    now = DateTime.utc_now()

    from(a in AlarmSchema,
      where: a.status == :shelved,
      where: a.shelved_until < ^now
    )
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def delete(id) do
    case Repo.get(AlarmSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec to_entity(AlarmSchema.t()) :: AlarmEntity.t()
  def to_entity(%AlarmSchema{} = schema) do
    %AlarmEntity{
      id: schema.id,
      organization_id: schema.organization_id,
      mission_id: schema.mission_id,
      target_id: schema.target_id,
      alarm_rule_id: schema.alarm_rule_id,
      alarm_type: schema.alarm_type,
      severity: schema.severity,
      status: schema.status,
      source_type: schema.source_type,
      source_id: schema.source_id,
      source_origin: schema.source_origin,
      limit_state: schema.limit_state,
      current_value: schema.current_value,
      message: schema.message,
      acknowledged_by_id: schema.acknowledged_by_id,
      acknowledged_at: schema.acknowledged_at,
      acknowledgment_note: schema.acknowledgment_note,
      shelved_by_id: schema.shelved_by_id,
      shelved_at: schema.shelved_at,
      shelved_until: schema.shelved_until,
      shelve_reason: schema.shelve_reason,
      triggered_at: schema.triggered_at,
      cleared_at: schema.cleared_at,
      last_value_at: schema.last_value_at,
      metadata: schema.metadata || %{}
    }
  end

  @doc """
  Converts a domain entity to schema attributes for insertion.
  """
  @spec to_schema_attrs(AlarmEntity.t()) :: map()
  def to_schema_attrs(%AlarmEntity{} = entity) do
    %{
      organization_id: entity.organization_id,
      mission_id: entity.mission_id,
      target_id: entity.target_id,
      alarm_rule_id: entity.alarm_rule_id,
      alarm_type: entity.alarm_type,
      severity: entity.severity,
      status: entity.status,
      source_type: entity.source_type,
      source_id: entity.source_id,
      source_origin: entity.source_origin,
      limit_state: entity.limit_state,
      current_value: entity.current_value,
      message: entity.message,
      triggered_at: entity.triggered_at,
      metadata: entity.metadata
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp update_changeset(schema, entity) do
    import Ecto.Changeset

    attrs = %{
      status: entity.status,
      severity: entity.severity,
      current_value: entity.current_value,
      limit_state: entity.limit_state,
      message: entity.message,
      acknowledged_by_id: entity.acknowledged_by_id,
      acknowledged_at: entity.acknowledged_at,
      acknowledgment_note: entity.acknowledgment_note,
      shelved_by_id: entity.shelved_by_id,
      shelved_at: entity.shelved_at,
      shelved_until: entity.shelved_until,
      shelve_reason: entity.shelve_reason,
      cleared_at: entity.cleared_at,
      last_value_at: entity.last_value_at,
      metadata: entity.metadata
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
      {:status, statuses}, q when is_list(statuses) -> from(a in q, where: a.status in ^statuses)
      {:status, status}, q -> from(a in q, where: a.status == ^status)
      {:target_id, nil}, q -> q
      {:target_id, target_id}, q -> from(a in q, where: a.target_id == ^target_id)
      {:severity, nil}, q -> q
      {:severity, severity}, q -> from(a in q, where: a.severity == ^severity)
    end)
  end
end
