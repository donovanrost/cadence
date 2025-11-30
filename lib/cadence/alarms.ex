defmodule Cadence.Alarms do
  @moduledoc """
  Context for managing alarms and alarm rules.

  This module provides the public API for:
  - Creating and managing alarm rules
  - Querying active and historical alarms
  - Acknowledging, shelving, and clearing alarms
  - Recording alarm events for audit trail
  """

  import Ecto.Query, warn: false

  alias Cadence.Repo
  alias Cadence.Alarms.{Alarm, AlarmEvent, AlarmRule}

  # ============================================================================
  # Alarm Rules
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
  def list_rules(organization_id, opts \\ []) do
    AlarmRule
    |> where([r], r.organization_id == ^organization_id)
    |> apply_rule_filters(opts)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single alarm rule by ID.
  """
  @spec get_rule(String.t()) :: AlarmRule.t() | nil
  def get_rule(id), do: Repo.get(AlarmRule, id)

  @doc """
  Gets a single alarm rule by ID, raising if not found.
  """
  @spec get_rule!(String.t()) :: AlarmRule.t()
  def get_rule!(id), do: Repo.get!(AlarmRule, id)

  @doc """
  Creates a new alarm rule.
  """
  @spec create_rule(map()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def create_rule(attrs) do
    %AlarmRule{}
    |> AlarmRule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an alarm rule.
  """
  @spec update_rule(AlarmRule.t(), map()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def update_rule(%AlarmRule{} = rule, attrs) do
    rule
    |> AlarmRule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Enables an alarm rule.
  """
  @spec enable_rule(AlarmRule.t()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def enable_rule(%AlarmRule{} = rule) do
    rule
    |> AlarmRule.enable_changeset(%{enabled: true})
    |> Repo.update()
  end

  @doc """
  Disables an alarm rule with optional reason.
  """
  @spec disable_rule(AlarmRule.t(), String.t() | nil, String.t() | nil) ::
          {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def disable_rule(%AlarmRule{} = rule, user_id \\ nil, reason \\ nil) do
    rule
    |> AlarmRule.enable_changeset(%{
      enabled: false,
      disabled_at: DateTime.utc_now(),
      disabled_by_id: user_id,
      disabled_reason: reason
    })
    |> Repo.update()
  end

  @doc """
  Deletes an alarm rule.
  """
  @spec delete_rule(AlarmRule.t()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def delete_rule(%AlarmRule{} = rule) do
    Repo.delete(rule)
  end

  @doc """
  Finds matching rules for a given event.

  Returns rules in specificity order (most specific first).
  """
  @spec find_matching_rules(String.t(), String.t(), String.t() | nil, String.t()) ::
          [AlarmRule.t()]
  def find_matching_rules(organization_id, mission_id, target_id, event_type) do
    AlarmRule
    |> where([r], r.organization_id == ^organization_id)
    |> where([r], r.event_type == ^event_type)
    |> where([r], r.enabled == true)
    |> where(
      [r],
      # Org-wide rules
      (is_nil(r.mission_id) and is_nil(r.target_id)) or
        # Mission-wide rules
        (r.mission_id == ^mission_id and is_nil(r.target_id)) or
        # Target-specific rules
        (r.mission_id == ^mission_id and r.target_id == ^target_id)
    )
    |> Repo.all()
    |> Enum.sort_by(&AlarmRule.specificity/1, :desc)
  end

  # ============================================================================
  # Alarms
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
    Alarm
    |> where([a], a.mission_id == ^mission_id)
    |> apply_alarm_filters(opts)
    |> order_by([a], desc: a.triggered_at)
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
    |> Repo.all()
  end

  @doc """
  Lists active alarms for a mission (status in [:active, :acknowledged, :shelved]).
  """
  @spec list_active_alarms(String.t(), keyword()) :: [Alarm.t()]
  def list_active_alarms(mission_id, opts \\ []) do
    list_alarms(mission_id, Keyword.put(opts, :status, [:active, :acknowledged, :shelved]))
  end

  @doc """
  Counts alarms by status for a mission.
  """
  @spec count_alarms_by_status(String.t()) :: map()
  def count_alarms_by_status(mission_id) do
    Alarm
    |> where([a], a.mission_id == ^mission_id)
    |> group_by([a], a.status)
    |> select([a], {a.status, count(a.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets a single alarm by ID.
  """
  @spec get_alarm(String.t()) :: Alarm.t() | nil
  def get_alarm(id), do: Repo.get(Alarm, id)

  @doc """
  Gets a single alarm by ID, raising if not found.
  """
  @spec get_alarm!(String.t()) :: Alarm.t()
  def get_alarm!(id), do: Repo.get!(Alarm, id)

  @doc """
  Finds an existing active alarm for the given source.

  Used for deduplication - only one active alarm per source.

  The target_id can be either a UUID or a string identifier.
  If it's a string identifier, we look up the target to get its UUID.
  """
  @spec find_active_alarm(String.t(), String.t() | nil, String.t(), String.t()) :: Alarm.t() | nil
  def find_active_alarm(mission_id, target_id, source_type, source_id) do
    resolved_target_id = resolve_target_id(mission_id, target_id)

    query =
      Alarm
      |> where([a], a.mission_id == ^mission_id)
      |> where([a], a.source_type == ^source_type)
      |> where([a], a.source_id == ^source_id)
      |> where([a], a.status in [:active, :acknowledged, :shelved])

    query =
      if resolved_target_id do
        where(query, [a], a.target_id == ^resolved_target_id)
      else
        where(query, [a], is_nil(a.target_id))
      end

    Repo.one(query)
  end

  # Resolves a target_id to a UUID.
  # If it's already a valid UUID, returns it as-is.
  # If it's a string identifier, looks up the target and returns its UUID.
  # Returns nil if not found or if target_id is nil.
  defp resolve_target_id(_mission_id, nil), do: nil

  defp resolve_target_id(mission_id, target_id) when is_binary(target_id) do
    case Ecto.UUID.cast(target_id) do
      {:ok, uuid} ->
        # It's already a valid UUID
        uuid

      :error ->
        # It's a string identifier, look up the target
        case Cadence.Targets.get_target_by_identifier(mission_id, target_id) do
          %{id: uuid} -> uuid
          nil -> nil
        end
    end
  end

  @doc """
  Creates a new alarm and records the triggered event.

  The target_id can be either a UUID or a string identifier.
  If it's a string identifier, we look up the target to get its UUID.
  """
  @spec create_alarm(map()) :: {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def create_alarm(attrs) do
    # Resolve target_id if it's a string identifier
    attrs = resolve_target_id_in_attrs(attrs)

    Repo.transaction(fn ->
      with {:ok, alarm} <- do_create_alarm(attrs),
           {:ok, _event} <- create_event(AlarmEvent.triggered(alarm, attrs[:current_value])) do
        alarm
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp do_create_alarm(attrs) do
    %Alarm{}
    |> Alarm.changeset(attrs)
    |> Repo.insert()
  end

  # Resolves target_id in attrs map if it's a string identifier
  defp resolve_target_id_in_attrs(attrs) do
    mission_id = attrs[:mission_id]
    target_id = attrs[:target_id]

    if mission_id && target_id do
      resolved = resolve_target_id(mission_id, target_id)
      Map.put(attrs, :target_id, resolved)
    else
      attrs
    end
  end

  @doc """
  Acknowledges an alarm.
  """
  @spec acknowledge_alarm(Alarm.t(), String.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def acknowledge_alarm(%Alarm{} = alarm, user_id, note \\ nil) do
    Repo.transaction(fn ->
      attrs = %{
        acknowledged_by_id: user_id,
        acknowledged_at: DateTime.utc_now(),
        acknowledgment_note: note
      }

      with {:ok, updated} <- do_acknowledge_alarm(alarm, attrs),
           {:ok, _event} <- create_event(AlarmEvent.acknowledged(updated, user_id, note)) do
        updated
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp do_acknowledge_alarm(alarm, attrs) do
    alarm
    |> Alarm.acknowledge_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Shelves an alarm for a specified duration.
  """
  @spec shelve_alarm(Alarm.t(), String.t(), integer(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def shelve_alarm(%Alarm{} = alarm, user_id, duration_minutes, reason \\ nil) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()
      shelved_until = DateTime.add(now, duration_minutes * 60, :second)

      attrs = %{
        shelved_by_id: user_id,
        shelved_at: now,
        shelved_until: shelved_until,
        shelve_reason: reason
      }

      with {:ok, updated} <- do_shelve_alarm(alarm, attrs),
           {:ok, _event} <- create_event(AlarmEvent.shelved(updated, user_id, reason)) do
        updated
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp do_shelve_alarm(alarm, attrs) do
    alarm
    |> Alarm.shelve_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Unshelves an alarm, returning it to active/acknowledged state.
  """
  @spec unshelve_alarm(Alarm.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def unshelve_alarm(%Alarm{} = alarm, user_id \\ nil) do
    Repo.transaction(fn ->
      previous_state = %{"status" => "shelved", "shelved_until" => alarm.shelved_until}
      previous_status = if alarm.acknowledged_at, do: :acknowledged, else: :active

      with {:ok, updated} <- do_unshelve_alarm(alarm, previous_status),
           {:ok, _event} <- create_event(AlarmEvent.unshelved(updated, previous_state, user_id)) do
        updated
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp do_unshelve_alarm(alarm, previous_status) do
    alarm
    |> Alarm.unshelve_changeset(previous_status)
    |> Repo.update()
  end

  @doc """
  Clears an alarm (condition resolved).
  """
  @spec clear_alarm(Alarm.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def clear_alarm(%Alarm{} = alarm, user_id \\ nil) do
    Repo.transaction(fn ->
      previous_state = %{
        "status" => to_string(alarm.status),
        "severity" => to_string(alarm.severity),
        "current_value" => alarm.current_value
      }

      with {:ok, updated} <- do_clear_alarm(alarm),
           {:ok, _event} <- create_event(AlarmEvent.cleared(updated, previous_state, user_id)) do
        updated
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp do_clear_alarm(alarm) do
    alarm
    |> Alarm.clear_changeset(%{cleared_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Updates an alarm's value and optionally escalates/deescalates severity.

  Used when a telemetry item is still in violation but the value changed.
  """
  @spec update_alarm_value(Alarm.t(), float(), atom(), atom(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def update_alarm_value(%Alarm{} = alarm, value, limit_state, new_severity, message \\ nil) do
    Repo.transaction(fn ->
      previous_state = %{
        "severity" => to_string(alarm.severity),
        "limit_state" => alarm.limit_state && to_string(alarm.limit_state),
        "current_value" => alarm.current_value
      }

      attrs = %{
        current_value: value,
        limit_state: limit_state,
        last_value_at: DateTime.utc_now(),
        severity: new_severity,
        message: message || alarm.message
      }

      with {:ok, updated} <- do_update_alarm_value(alarm, attrs),
           {:ok, _event} <- create_value_event(alarm, updated, previous_state, value) do
        updated
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp do_update_alarm_value(alarm, attrs) do
    alarm
    |> Alarm.update_value_changeset(attrs)
    |> Repo.update()
  end

  defp create_value_event(old_alarm, new_alarm, previous_state, value) do
    event_attrs =
      cond do
        severity_rank(new_alarm.severity) > severity_rank(old_alarm.severity) ->
          AlarmEvent.escalated(new_alarm, previous_state, value)

        severity_rank(new_alarm.severity) < severity_rank(old_alarm.severity) ->
          AlarmEvent.deescalated(new_alarm, previous_state, value)

        true ->
          AlarmEvent.value_updated(new_alarm, previous_state, value)
      end

    create_event(event_attrs)
  end

  defp severity_rank(:info), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(:critical), do: 2

  # ============================================================================
  # Alarm Events
  # ============================================================================

  @doc """
  Lists events for an alarm.
  """
  @spec list_alarm_events(String.t()) :: [AlarmEvent.t()]
  def list_alarm_events(alarm_id) do
    AlarmEvent
    |> where([e], e.alarm_id == ^alarm_id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a new alarm event.
  """
  @spec create_event(map()) :: {:ok, AlarmEvent.t()} | {:error, Ecto.Changeset.t()}
  def create_event(attrs) do
    %AlarmEvent{}
    |> AlarmEvent.changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # Shelve Expiration
  # ============================================================================

  @doc """
  Finds all alarms with expired shelve periods.
  """
  @spec find_expired_shelved_alarms() :: [Alarm.t()]
  def find_expired_shelved_alarms do
    now = DateTime.utc_now()

    Alarm
    |> where([a], a.status == :shelved)
    |> where([a], a.shelved_until < ^now)
    |> Repo.all()
  end

  @doc """
  Unshelves all alarms with expired shelve periods.

  Returns the count of alarms unshelved.
  """
  @spec unshelve_expired_alarms() :: {:ok, integer()}
  def unshelve_expired_alarms do
    alarms = find_expired_shelved_alarms()

    Enum.each(alarms, fn alarm ->
      unshelve_alarm(alarm, nil)
    end)

    {:ok, length(alarms)}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp apply_rule_filters(query, opts) do
    query
    |> maybe_filter_by_mission(opts[:mission_id])
    |> maybe_filter_by_target(opts[:target_id])
    |> maybe_filter_by_event_type(opts[:event_type])
    |> maybe_filter_by_enabled(opts[:enabled])
  end

  defp apply_alarm_filters(query, opts) do
    query
    |> maybe_filter_by_status(opts[:status])
    |> maybe_filter_by_severity(opts[:severity])
    |> maybe_filter_by_target(opts[:target_id])
    |> maybe_filter_by_source(opts[:source_id])
  end

  defp maybe_filter_by_mission(query, nil), do: query

  defp maybe_filter_by_mission(query, mission_id) do
    where(query, [r], is_nil(r.mission_id) or r.mission_id == ^mission_id)
  end

  defp maybe_filter_by_target(query, nil), do: query
  defp maybe_filter_by_target(query, target_id), do: where(query, [x], x.target_id == ^target_id)

  defp maybe_filter_by_event_type(query, nil), do: query

  defp maybe_filter_by_event_type(query, event_type),
    do: where(query, [r], r.event_type == ^event_type)

  defp maybe_filter_by_enabled(query, nil), do: query
  defp maybe_filter_by_enabled(query, enabled), do: where(query, [r], r.enabled == ^enabled)

  defp maybe_filter_by_status(query, nil), do: query

  defp maybe_filter_by_status(query, statuses) when is_list(statuses),
    do: where(query, [a], a.status in ^statuses)

  defp maybe_filter_by_status(query, status), do: where(query, [a], a.status == ^status)

  defp maybe_filter_by_severity(query, nil), do: query

  defp maybe_filter_by_severity(query, severities) when is_list(severities),
    do: where(query, [a], a.severity in ^severities)

  defp maybe_filter_by_severity(query, severity), do: where(query, [a], a.severity == ^severity)

  defp maybe_filter_by_source(query, nil), do: query
  defp maybe_filter_by_source(query, source_id), do: where(query, [a], a.source_id == ^source_id)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)
end
