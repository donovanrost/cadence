defmodule Cadence.Alarms do
  @moduledoc """
  Context facade for managing alarms and alarm rules.

  This module provides the public API for:
  - Creating and managing alarm rules
  - Querying active and historical alarms
  - Acknowledging, shelving, and clearing alarms
  - Recording alarm events for audit trail

  ## Architecture

  This facade delegates to focused use case modules:
  - `AlarmQueries` - Read operations for alarms
  - `AlarmOperations` - State transitions (acknowledge, shelve, clear)
  - `TriggerAlarm` - Alarm creation and deduplication
  - `ManageAlarmRules` - Rule CRUD and matching
  """

  alias Cadence.Alarms.{Alarm, AlarmRule}

  alias Cadence.Application.Alerting.{
    AlarmOperations,
    AlarmQueries,
    ManageAlarmRules,
    TriggerAlarm
  }

  alias Cadence.Runtime.Alarms.AlarmManager

  # ============================================================================
  # Alarm Rules - Delegate to ManageAlarmRules
  # ============================================================================

  @doc """
  Lists all alarm rules for an organization.

  ## Options

  - `:mission_id` - Filter to rules for a specific mission (includes org-wide rules)
  - `:target_id` - Filter to rules for a specific target
  - `:event_type` - Filter by event type
  - `:enabled` - Filter by enabled status (default: all)
  """
  @spec list_rules(String.t(), keyword()) :: [AlarmRule.t()]
  defdelegate list_rules(organization_id, opts \\ []), to: ManageAlarmRules, as: :list

  @doc """
  Gets a single alarm rule by ID.
  """
  @spec get_rule(String.t()) :: AlarmRule.t() | nil
  defdelegate get_rule(id), to: ManageAlarmRules, as: :get

  @doc """
  Gets a single alarm rule by ID, raising if not found.
  """
  @spec get_rule!(String.t()) :: AlarmRule.t()
  defdelegate get_rule!(id), to: ManageAlarmRules, as: :get!

  @doc """
  Creates a new alarm rule.
  """
  @spec create_rule(map()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_rule(attrs), to: ManageAlarmRules, as: :create

  @doc """
  Updates an alarm rule.
  """
  @spec update_rule(AlarmRule.t(), map()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_rule(rule, attrs), to: ManageAlarmRules, as: :update

  @doc """
  Enables an alarm rule.
  """
  @spec enable_rule(AlarmRule.t()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  defdelegate enable_rule(rule), to: ManageAlarmRules, as: :enable

  @doc """
  Disables an alarm rule with optional reason.
  """
  @spec disable_rule(AlarmRule.t(), String.t() | nil, String.t() | nil) ::
          {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  defdelegate disable_rule(rule, user_id \\ nil, reason \\ nil),
    to: ManageAlarmRules,
    as: :disable

  @doc """
  Deletes an alarm rule.
  """
  @spec delete_rule(AlarmRule.t()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_rule(rule), to: ManageAlarmRules, as: :delete

  @doc """
  Finds matching rules for a given event.

  Returns rules in specificity order (most specific first).
  """
  @spec find_matching_rules(String.t(), String.t(), String.t() | nil, String.t()) ::
          [AlarmRule.t()]
  defdelegate find_matching_rules(organization_id, mission_id, target_id, event_type),
    to: ManageAlarmRules,
    as: :find_matching

  # ============================================================================
  # Alarm Queries - Delegate to AlarmQueries
  # ============================================================================

  @doc """
  Lists alarms for a mission.

  ## Options

  - `:status` - Filter by status (or list of statuses)
  - `:severity` - Filter by severity (or list of severities)
  - `:target_id` - Filter by target
  - `:source_id` - Filter by source (e.g., telemetry item name)
  - `:limit` - Maximum number of results
  - `:offset` - Offset for pagination
  """
  @spec list_alarms(String.t(), keyword()) :: [Alarm.t()]
  def list_alarms(mission_id, opts \\ []) do
    # AlarmQueries returns domain entities, but facade returns schemas for compatibility
    # For now, use the adapter directly for backward compatibility
    repo().list(mission_id, opts) |> Enum.map(&entity_to_schema/1)
  end

  @doc """
  Lists active alarms for a mission (status in [:active, :acknowledged, :shelved]).
  """
  @spec list_active_alarms(String.t(), keyword()) :: [Alarm.t()]
  def list_active_alarms(mission_id, opts \\ []) do
    repo().list_active(mission_id, opts) |> Enum.map(&entity_to_schema/1)
  end

  @doc """
  Lists historical (cleared) alarms for a mission.

  ## Options

  - `:time_range` - Filter by time range: `:"1h"`, `:"6h"`, `:"24h"`, `:"7d"`, `:all`
  - `:target_id` - Filter by target UUID
  - `:severity` - Filter by severity (atom or list of atoms)
  - `:limit` - Maximum number of results (default: 100)
  """
  @spec list_historical_alarms(String.t(), keyword()) :: [Alarm.t()]
  def list_historical_alarms(mission_id, opts \\ []) do
    AlarmQueries.list_historical(mission_id, opts) |> Enum.map(&entity_to_schema/1)
  end

  @doc """
  Counts alarms by status for a mission.
  """
  @spec count_alarms_by_status(String.t()) :: map()
  defdelegate count_alarms_by_status(mission_id), to: AlarmQueries, as: :count_by_status

  @doc """
  Gets a single alarm by ID.
  """
  @spec get_alarm(String.t()) :: Alarm.t() | nil
  def get_alarm(id) do
    case AlarmQueries.find(id) do
      {:ok, entity} -> entity_to_schema(entity)
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets a single alarm by ID, raising if not found.
  """
  @spec get_alarm!(String.t()) :: Alarm.t()
  def get_alarm!(id) do
    case AlarmQueries.find(id) do
      {:ok, entity} -> entity_to_schema(entity)
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Alarm
    end
  end

  @doc """
  Finds an existing active alarm for the given source.

  Used for deduplication - only one active alarm per source.
  """
  @spec find_active_alarm(String.t(), String.t() | nil, String.t(), String.t()) :: Alarm.t() | nil
  def find_active_alarm(mission_id, target_id, source_type, source_id) do
    case AlarmQueries.find_active_by_source(mission_id, target_id, source_type, source_id) do
      {:ok, entity} -> entity_to_schema(entity)
      {:error, :not_found} -> nil
    end
  end

  # ============================================================================
  # Alarm Creation - Delegate to TriggerAlarm
  # ============================================================================

  @doc """
  Creates a new alarm and records the triggered event.
  """
  @spec create_alarm(map()) :: {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def create_alarm(attrs) do
    case TriggerAlarm.from_telemetry(attrs) do
      {:ok, entity, _status} -> {:ok, entity_to_schema(entity)}
      {:error, reason} -> {:error, domain_error_to_changeset(reason)}
    end
  end

  @doc """
  Finds an existing active alarm or creates a new one atomically.

  Returns:
  - `{:ok, alarm, :created}` - A new alarm was created
  - `{:ok, alarm, :existing}` - An existing active alarm was found
  - `{:error, changeset}` - Validation or other error
  """
  @spec find_or_create_alarm(map()) ::
          {:ok, Alarm.t(), :created | :existing} | {:error, Ecto.Changeset.t()}
  def find_or_create_alarm(attrs) do
    case TriggerAlarm.from_telemetry(attrs) do
      {:ok, entity, status} -> {:ok, entity_to_schema(entity), status}
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Alarm Operations - Delegate to AlarmOperations via AlarmManager
  # ============================================================================

  @doc """
  Acknowledges an alarm.

  Routes through AlarmManager when the mission is active, ensuring cache consistency.
  """
  @spec acknowledge_alarm(Alarm.t(), String.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def acknowledge_alarm(alarm, user_id, note \\ nil)

  def acknowledge_alarm(%Cadence.Domain.Alerting.Entities.Alarm{} = entity, user_id, note) do
    acknowledge_alarm(entity_to_schema(entity), user_id, note)
  end

  def acknowledge_alarm(%Alarm{mission_id: mission_id} = alarm, user_id, note) do
    case AlarmManager.whereis(mission_id) do
      nil ->
        # Mission not running, use AlarmOperations directly
        case AlarmOperations.acknowledge(alarm.id, user_id, note) do
          {:ok, entity} -> {:ok, entity_to_schema(entity)}
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        # Route through AlarmManager for cache consistency
        AlarmManager.acknowledge_alarm(mission_id, alarm.id, user_id, note)
    end
  end

  @doc false
  # Internal function called by AlarmManager
  @spec do_acknowledge_alarm(Alarm.t(), String.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def do_acknowledge_alarm(%Alarm{} = alarm, user_id, note) do
    case AlarmOperations.acknowledge(alarm.id, user_id, note) do
      {:ok, entity} -> {:ok, entity_to_schema(entity)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Shelves an alarm for a specified duration.

  Routes through AlarmManager when the mission is active, ensuring cache consistency.
  """
  @spec shelve_alarm(Alarm.t(), String.t(), integer(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def shelve_alarm(alarm, user_id, duration_minutes, reason \\ nil)

  def shelve_alarm(
        %Cadence.Domain.Alerting.Entities.Alarm{} = entity,
        user_id,
        duration_minutes,
        reason
      ) do
    shelve_alarm(entity_to_schema(entity), user_id, duration_minutes, reason)
  end

  def shelve_alarm(
        %Alarm{mission_id: mission_id} = alarm,
        user_id,
        duration_minutes,
        reason
      ) do
    case AlarmManager.whereis(mission_id) do
      nil ->
        case AlarmOperations.shelve(alarm.id, user_id, duration_minutes, reason) do
          {:ok, entity} -> {:ok, entity_to_schema(entity)}
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        AlarmManager.shelve_alarm(mission_id, alarm.id, user_id, duration_minutes, reason)
    end
  end

  @doc false
  # Internal function called by AlarmManager
  @spec do_shelve_alarm(Alarm.t(), String.t(), integer(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def do_shelve_alarm(%Alarm{} = alarm, user_id, duration_minutes, reason) do
    case AlarmOperations.shelve(alarm.id, user_id, duration_minutes, reason) do
      {:ok, entity} -> {:ok, entity_to_schema(entity)}
      {:error, r} -> {:error, r}
    end
  end

  @doc """
  Unshelves an alarm, returning it to active/acknowledged state.

  Routes through AlarmManager when the mission is active, ensuring cache consistency.
  """
  @spec unshelve_alarm(Alarm.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def unshelve_alarm(alarm, user_id \\ nil)

  def unshelve_alarm(%Cadence.Domain.Alerting.Entities.Alarm{} = entity, user_id) do
    unshelve_alarm(entity_to_schema(entity), user_id)
  end

  def unshelve_alarm(%Alarm{mission_id: mission_id} = alarm, user_id) do
    case AlarmManager.whereis(mission_id) do
      nil ->
        case AlarmOperations.unshelve(alarm.id, user_id) do
          {:ok, entity} -> {:ok, entity_to_schema(entity)}
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        AlarmManager.unshelve_alarm(mission_id, alarm.id, user_id)
    end
  end

  @doc false
  # Internal function called by AlarmManager
  @spec do_unshelve_alarm(Alarm.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def do_unshelve_alarm(%Alarm{} = alarm, user_id) do
    case AlarmOperations.unshelve(alarm.id, user_id) do
      {:ok, entity} -> {:ok, entity_to_schema(entity)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Clears an alarm (condition resolved).

  Routes through AlarmManager when the mission is active, ensuring cache consistency.
  """
  @spec clear_alarm(Alarm.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def clear_alarm(alarm, user_id \\ nil)

  def clear_alarm(%Cadence.Domain.Alerting.Entities.Alarm{} = entity, user_id) do
    clear_alarm(entity_to_schema(entity), user_id)
  end

  def clear_alarm(%Alarm{mission_id: mission_id} = alarm, user_id) do
    case AlarmManager.whereis(mission_id) do
      nil ->
        case AlarmOperations.clear(alarm.id, user_id) do
          {:ok, entity} -> {:ok, entity_to_schema(entity)}
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        AlarmManager.clear_alarm(mission_id, alarm.id, user_id)
    end
  end

  @doc false
  # Internal function called by AlarmManager
  @spec do_clear_alarm(Alarm.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def do_clear_alarm(%Alarm{} = alarm, user_id) do
    case AlarmOperations.clear(alarm.id, user_id) do
      {:ok, entity} -> {:ok, entity_to_schema(entity)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates an alarm's value and optionally escalates/deescalates severity.

  Routes through AlarmManager when the mission is active, ensuring cache consistency.
  """
  @spec update_alarm_value(Alarm.t(), float(), atom(), atom(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def update_alarm_value(alarm, value, limit_state, new_severity, message \\ nil)

  def update_alarm_value(
        %Cadence.Domain.Alerting.Entities.Alarm{} = entity,
        value,
        limit_state,
        new_severity,
        message
      ) do
    update_alarm_value(entity_to_schema(entity), value, limit_state, new_severity, message)
  end

  def update_alarm_value(
        %Alarm{mission_id: mission_id} = alarm,
        value,
        limit_state,
        new_severity,
        message
      ) do
    case AlarmManager.whereis(mission_id) do
      nil ->
        opts = [severity: new_severity, limit_state: limit_state, message: message]

        case AlarmOperations.update_value(alarm.id, value, opts) do
          {:ok, entity} -> {:ok, entity_to_schema(entity)}
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        AlarmManager.update_alarm_value(
          mission_id,
          alarm.id,
          value,
          limit_state,
          new_severity,
          message
        )
    end
  end

  @doc false
  # Internal function called by AlarmManager
  @spec do_update_alarm_value(Alarm.t(), float(), atom(), atom(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def do_update_alarm_value(%Alarm{} = alarm, value, limit_state, new_severity, message) do
    opts = [severity: new_severity, limit_state: limit_state, message: message]

    case AlarmOperations.update_value(alarm.id, value, opts) do
      {:ok, entity} -> {:ok, entity_to_schema(entity)}
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Shelve Expiration
  # ============================================================================

  @doc """
  Finds all alarms with expired shelve periods.
  """
  @spec find_expired_shelved_alarms() :: [Alarm.t()]
  def find_expired_shelved_alarms do
    repo().list_expired_shelved() |> Enum.map(&entity_to_schema/1)
  end

  @doc """
  Unshelves all alarms with expired shelve periods.

  Returns the count of alarms unshelved.
  """
  @spec unshelve_expired_alarms() :: {:ok, integer()}
  defdelegate unshelve_expired_alarms(), to: AlarmOperations, as: :unshelve_expired

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp repo do
    Application.get_env(
      :cadence,
      :alarm_repository,
      Cadence.Adapters.Persistence.Ecto.Alerting.EctoAlarmRepository
    )
  end

  # Convert domain entity to Ecto schema for backward compatibility
  # This allows existing code that expects Ecto schemas to continue working
  defp entity_to_schema(%Cadence.Domain.Alerting.Entities.Alarm{} = entity) do
    %Alarm{
      id: entity.id,
      organization_id: entity.organization_id,
      mission_id: entity.mission_id,
      target_id: entity.target_id,
      alarm_rule_id: entity.alarm_rule_id,
      alarm_type: entity.alarm_type,
      severity: entity.severity,
      status: entity.status,
      source_type: entity.source_type,
      source_id: entity.source_id,
      message: entity.message,
      current_value: entity.current_value,
      limit_state: entity.limit_state,
      triggered_at: entity.triggered_at,
      acknowledged_at: entity.acknowledged_at,
      acknowledged_by_id: entity.acknowledged_by_id,
      acknowledgment_note: entity.acknowledgment_note,
      shelved_at: entity.shelved_at,
      shelved_by_id: entity.shelved_by_id,
      shelved_until: entity.shelved_until,
      shelve_reason: entity.shelve_reason,
      cleared_at: entity.cleared_at,
      last_value_at: entity.last_value_at,
      metadata: entity.metadata
    }
  end

  # Convert domain validation errors to Ecto.Changeset for backward compatibility
  defp domain_error_to_changeset({:missing_required, fields}) do
    changeset = Ecto.Changeset.change(%Alarm{})

    Enum.reduce(fields, changeset, fn field, cs ->
      Ecto.Changeset.add_error(cs, field, "can't be blank")
    end)
  end

  defp domain_error_to_changeset({:validation, errors}) when is_map(errors) do
    changeset = Ecto.Changeset.change(%Alarm{})

    Enum.reduce(errors, changeset, fn {field, messages}, cs ->
      Enum.reduce(List.wrap(messages), cs, fn msg, cs_inner ->
        Ecto.Changeset.add_error(cs_inner, field, msg)
      end)
    end)
  end

  defp domain_error_to_changeset(%Ecto.Changeset{} = changeset), do: changeset

  defp domain_error_to_changeset(error) do
    Ecto.Changeset.change(%Alarm{})
    |> Ecto.Changeset.add_error(:base, "#{inspect(error)}")
  end
end
