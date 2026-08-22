defmodule Cadence.AlarmsBuilders do
  @moduledoc """
  Builders for Alarms structs without database interaction.

  Use these builders for pure unit tests that don't need persistence.
  For tests that need database records, use `Cadence.AlarmsFixtures` instead.

  ## Design Philosophy

  Builders create plain structs with sensible defaults. They:
  - Never touch the database
  - Generate unique IDs automatically
  - Allow full override of any field
  - Support both keyword lists and maps as input

  ## Examples

      # Simple alarm struct
      alarm = build_alarm()

      # Alarm with custom severity
      alarm = build_alarm(severity: :critical, limit_state: :red)

      # Build a limit event for testing
      event = build_limit_event(new_state: :red, item_name: "HEALTH.cpu_temp")
  """

  alias Cadence.Alarms.{Alarm, AlarmRule}
  alias Cadence.Telemetry.Events.TelemetryLimitEvent

  # ============================================================================
  # Alarm Builders
  # ============================================================================

  @doc """
  Builds an Alarm struct with defaults.

  ## Examples

      alarm = build_alarm()
      alarm = build_alarm(severity: :critical, status: :acknowledged)
  """
  def build_alarm(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      mission_id: Ecto.UUID.generate(),
      target_id: nil,
      alarm_rule_id: nil,
      alarm_type: "telemetry_limit",
      severity: :warning,
      status: :active,
      source_type: "telemetry_item",
      source_id: "HEALTH.cpu_temp_#{System.unique_integer([:positive])}",
      source_origin: :rule,
      source_definition_set_id: nil,
      limit_state: :yellow,
      current_value: 85.5,
      message: "Test alarm message",
      acknowledged_by_id: nil,
      acknowledged_at: nil,
      acknowledgment_note: nil,
      shelved_by_id: nil,
      shelved_at: nil,
      shelved_until: nil,
      shelve_reason: nil,
      triggered_at: DateTime.utc_now(),
      cleared_at: nil,
      last_value_at: nil,
      metadata: %{},
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct!(Alarm, Map.merge(defaults, to_map(overrides)))
  end

  @doc """
  Builds an active alarm (default state).
  """
  def build_active_alarm(overrides \\ %{}) do
    build_alarm(Map.merge(%{status: :active}, to_map(overrides)))
  end

  @doc """
  Builds an acknowledged alarm.
  """
  def build_acknowledged_alarm(overrides \\ %{}) do
    build_alarm(
      Map.merge(
        %{
          status: :acknowledged,
          acknowledged_by_id: Ecto.UUID.generate(),
          acknowledged_at: DateTime.utc_now(),
          acknowledgment_note: "Acknowledged for testing"
        },
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a shelved alarm.
  """
  def build_shelved_alarm(overrides \\ %{}) do
    now = DateTime.utc_now()

    build_alarm(
      Map.merge(
        %{
          status: :shelved,
          shelved_by_id: Ecto.UUID.generate(),
          shelved_at: now,
          shelved_until: DateTime.add(now, 1800, :second),
          shelve_reason: "Shelved for testing"
        },
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a shelved alarm with expired shelve period.
  """
  def build_expired_shelved_alarm(overrides \\ %{}) do
    now = DateTime.utc_now()

    build_alarm(
      Map.merge(
        %{
          status: :shelved,
          shelved_by_id: Ecto.UUID.generate(),
          shelved_at: DateTime.add(now, -3600, :second),
          shelved_until: DateTime.add(now, -60, :second),
          shelve_reason: "Shelved for testing"
        },
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a cleared alarm.
  """
  def build_cleared_alarm(overrides \\ %{}) do
    now = DateTime.utc_now()

    build_alarm(
      Map.merge(
        %{
          status: :cleared,
          triggered_at: DateTime.add(now, -3600, :second),
          cleared_at: now
        },
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a critical alarm.
  """
  def build_critical_alarm(overrides \\ %{}) do
    build_alarm(
      Map.merge(
        %{
          severity: :critical,
          limit_state: :red,
          current_value: 105.2,
          message: "CRITICAL: Temperature exceeded red threshold"
        },
        to_map(overrides)
      )
    )
  end

  # ============================================================================
  # Alarm Rule Builders
  # ============================================================================

  @doc """
  Builds an AlarmRule struct with defaults.

  ## Examples

      rule = build_alarm_rule()
      rule = build_alarm_rule(severity: :critical, conditions: %{"limit_state" => ["red"]})
  """
  def build_alarm_rule(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      mission_id: nil,
      target_id: nil,
      name: "Test Alarm Rule #{System.unique_integer([:positive])}",
      description: "A test alarm rule",
      event_type: "telemetry_limit",
      conditions: %{"limit_state" => ["red", "yellow"]},
      severity: :warning,
      message_template: "{{item_name}} is {{limit_state}} (value: {{value}})",
      auto_acknowledge: false,
      auto_shelve_duration_minutes: nil,
      cooldown_seconds: nil,
      notification_channels: [],
      enabled: true,
      disabled_at: nil,
      disabled_by_id: nil,
      disabled_reason: nil,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct!(AlarmRule, Map.merge(defaults, to_map(overrides)))
  end

  @doc """
  Builds a critical alarm rule.
  """
  def build_critical_alarm_rule(overrides \\ %{}) do
    build_alarm_rule(
      Map.merge(
        %{
          severity: :critical,
          conditions: %{"limit_state" => ["red"]}
        },
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a disabled alarm rule.
  """
  def build_disabled_alarm_rule(overrides \\ %{}) do
    build_alarm_rule(
      Map.merge(
        %{
          enabled: false,
          disabled_at: DateTime.utc_now(),
          disabled_by_id: Ecto.UUID.generate(),
          disabled_reason: "Disabled for testing"
        },
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds an alarm rule with notification channels.
  """
  def build_alarm_rule_with_notifications(overrides \\ %{}) do
    build_alarm_rule(
      Map.merge(
        %{notification_channels: ["webhook:ops", "email:oncall"]},
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds an alarm rule with auto-acknowledge enabled.
  """
  def build_auto_acknowledge_rule(overrides \\ %{}) do
    build_alarm_rule(
      Map.merge(
        %{auto_acknowledge: true},
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds an alarm rule with auto-shelve enabled.
  """
  def build_auto_shelve_rule(duration_minutes \\ 30, overrides \\ %{}) do
    build_alarm_rule(
      Map.merge(
        %{auto_shelve_duration_minutes: duration_minutes},
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a mission-specific alarm rule.
  """
  def build_mission_rule(mission_id, overrides \\ %{}) do
    build_alarm_rule(
      Map.merge(
        %{mission_id: mission_id},
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a target-specific alarm rule.
  """
  def build_target_rule(mission_id, target_id, overrides \\ %{}) do
    build_alarm_rule(
      Map.merge(
        %{mission_id: mission_id, target_id: target_id},
        to_map(overrides)
      )
    )
  end

  # ============================================================================
  # TelemetryLimitEvent Builders
  # ============================================================================

  @doc """
  Builds a TelemetryLimitEvent struct for testing.

  ## Examples

      event = build_limit_event()
      event = build_limit_event(new_state: :red, item_name: "POWER.voltage")
  """
  def build_limit_event(overrides \\ %{}) do
    overrides = to_map(overrides)

    TelemetryLimitEvent.new(%{
      id: overrides[:id],
      mission_id: overrides[:mission_id] || Ecto.UUID.generate(),
      target_id: overrides[:target_id] || "SAT-1",
      item_name: overrides[:item_name] || "HEALTH.cpu_temp",
      previous_state: overrides[:previous_state] || :green,
      new_state: overrides[:new_state] || :red,
      value: overrides[:value] || 100.0,
      limit_set: overrides[:limit_set] || "NOMINAL",
      timestamp: overrides[:timestamp] || DateTime.utc_now()
    })
  end

  @doc """
  Builds a violation event (green -> red/yellow).
  """
  def build_violation_event(new_state \\ :red, overrides \\ %{}) do
    build_limit_event(
      Map.merge(
        %{previous_state: :green, new_state: new_state},
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a recovery event (red/yellow -> green).
  """
  def build_recovery_event(previous_state \\ :red, overrides \\ %{}) do
    build_limit_event(
      Map.merge(
        %{previous_state: previous_state, new_state: :green, value: 75.0},
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds an escalation event (yellow -> red).
  """
  def build_escalation_event(overrides \\ %{}) do
    build_limit_event(
      Map.merge(
        %{previous_state: :yellow, new_state: :red, value: 105.0},
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a de-escalation event (red -> yellow).
  """
  def build_deescalation_event(overrides \\ %{}) do
    build_limit_event(
      Map.merge(
        %{previous_state: :red, new_state: :yellow, value: 85.0},
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a stale event (any -> blue).
  """
  def build_stale_event(previous_state \\ :green, overrides \\ %{}) do
    build_limit_event(
      Map.merge(
        %{previous_state: previous_state, new_state: :blue, value: nil},
        to_map(overrides)
      )
    )
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp to_map(kw) when is_list(kw), do: Map.new(kw)
  defp to_map(map) when is_map(map), do: map
end
