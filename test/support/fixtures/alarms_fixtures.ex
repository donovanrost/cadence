defmodule Cadence.AlarmsFixtures do
  @moduledoc """
  Test helpers for creating Alarm entities.
  """

  alias Cadence.Repo
  alias Cadence.Alarms.{Alarm, AlarmRule}

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.AccountsFixtures

  # ============================================================================
  # Alarm Rules
  # ============================================================================

  @doc """
  Creates an alarm rule fixture.

  ## Options

  - `:organization` - Organization to use (will create one if not provided)
  - `:mission` - Mission to scope to (optional)
  - `:target` - Target to scope to (optional)
  - `:name` - Rule name (default: "Test Alarm Rule")
  - `:event_type` - Event type (default: "telemetry_limit")
  - `:severity` - Alarm severity (default: :warning)
  - `:conditions` - Match conditions (default: %{"limit_state" => ["red", "yellow"]})

  ## Examples

      # Create a basic rule
      rule = alarm_rule_fixture()

      # Create a critical rule for a specific mission
      rule = alarm_rule_fixture(mission: mission, severity: :critical)

      # Create a rule with specific conditions
      rule = alarm_rule_fixture(conditions: %{"limit_state" => ["red"]})
  """
  def alarm_rule_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    org = attrs[:organization] || organization_fixture()

    mission_id =
      case attrs[:mission] do
        nil -> nil
        %{id: id} -> id
      end

    target_id =
      case attrs[:target] do
        nil -> nil
        %{id: id} -> id
      end

    attrs =
      attrs
      |> Map.drop([:organization, :mission, :target])
      |> Enum.into(%{
        organization_id: org.id,
        mission_id: mission_id,
        target_id: target_id,
        name: "Test Alarm Rule #{System.unique_integer([:positive])}",
        event_type: "telemetry_limit",
        severity: :warning,
        conditions: %{"limit_state" => ["red", "yellow"]},
        message_template: "{{item_name}} is {{limit_state}} (value: {{value}})",
        enabled: true
      })

    %AlarmRule{}
    |> AlarmRule.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Creates a critical alarm rule fixture.
  """
  def critical_alarm_rule_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    alarm_rule_fixture(
      Map.merge(attrs, %{
        severity: :critical,
        conditions: %{"limit_state" => ["red"]}
      })
    )
  end

  @doc """
  Creates a disabled alarm rule fixture.
  """
  def disabled_alarm_rule_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    alarm_rule_fixture(
      Map.merge(attrs, %{
        enabled: false,
        disabled_at: DateTime.utc_now(),
        disabled_reason: "Disabled for testing"
      })
    )
  end

  @doc """
  Creates an alarm rule with notification channels.
  """
  def alarm_rule_with_notifications_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    alarm_rule_fixture(
      Map.merge(attrs, %{
        notification_channels: ["webhook:ops", "email:oncall"]
      })
    )
  end

  # ============================================================================
  # Alarms
  # ============================================================================

  @doc """
  Creates an alarm fixture.

  ## Options

  - `:organization` - Organization to use (will create one if not provided)
  - `:mission` - Mission to use (will create one if not provided)
  - `:target` - Target for the alarm (optional)
  - `:alarm_rule` - Associated alarm rule (optional)
  - `:alarm_type` - Type of alarm (default: "telemetry_limit")
  - `:severity` - Severity level (default: :warning)
  - `:status` - Alarm status (default: :active)
  - `:source_type` - Source type (default: "telemetry_item")
  - `:source_id` - Source identifier (default: "HEALTH.cpu_temp")

  ## Examples

      # Create a basic alarm
      alarm = alarm_fixture()

      # Create a critical alarm
      alarm = alarm_fixture(severity: :critical, limit_state: :red)

      # Create an acknowledged alarm
      alarm = acknowledged_alarm_fixture()
  """
  def alarm_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    org = attrs[:organization] || organization_fixture()
    mission = attrs[:mission] || mission_fixture(organization: org)

    target_id =
      case attrs[:target] do
        nil -> nil
        %{id: id} -> id
      end

    alarm_rule_id =
      case attrs[:alarm_rule] do
        nil -> nil
        %{id: id} -> id
      end

    attrs =
      attrs
      |> Map.drop([:organization, :mission, :target, :alarm_rule])
      |> Enum.into(%{
        organization_id: org.id,
        mission_id: mission.id,
        target_id: target_id,
        alarm_rule_id: alarm_rule_id,
        alarm_type: "telemetry_limit",
        severity: :warning,
        status: :active,
        source_type: "telemetry_item",
        source_id: "HEALTH.cpu_temp_#{System.unique_integer([:positive])}",
        limit_state: :yellow,
        current_value: 85.5,
        message: "HEALTH.cpu_temp exceeded warning threshold",
        triggered_at: DateTime.utc_now()
      })

    %Alarm{}
    |> Alarm.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Creates a critical alarm fixture.
  """
  def critical_alarm_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    alarm_fixture(
      Map.merge(attrs, %{
        severity: :critical,
        limit_state: :red,
        current_value: 105.2,
        message: "CRITICAL: Temperature exceeded red threshold"
      })
    )
  end

  @doc """
  Creates an acknowledged alarm fixture.
  """
  def acknowledged_alarm_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    alarm = alarm_fixture(attrs)

    alarm
    |> Alarm.acknowledge_changeset(%{
      acknowledged_by_id: attrs[:acknowledged_by_id] || create_user_id(alarm.organization_id),
      acknowledged_at: DateTime.utc_now(),
      acknowledgment_note: attrs[:acknowledgment_note] || "Acknowledged for testing"
    })
    |> Repo.update!()
  end

  @doc """
  Creates a shelved alarm fixture.
  """
  def shelved_alarm_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    alarm = alarm_fixture(attrs)
    duration_minutes = attrs[:duration_minutes] || 30

    alarm
    |> Alarm.shelve_changeset(%{
      shelved_by_id: attrs[:shelved_by_id] || create_user_id(alarm.organization_id),
      shelved_at: DateTime.utc_now(),
      shelved_until: DateTime.add(DateTime.utc_now(), duration_minutes * 60, :second),
      shelve_reason: attrs[:shelve_reason] || "Shelved for testing"
    })
    |> Repo.update!()
  end

  @doc """
  Creates a cleared alarm fixture.
  """
  def cleared_alarm_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    alarm = alarm_fixture(attrs)

    alarm
    |> Alarm.clear_changeset(%{cleared_at: DateTime.utc_now()})
    |> Repo.update!()
  end

  @doc """
  Creates an alarm with expired shelve period.
  """
  def expired_shelved_alarm_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    alarm = alarm_fixture(attrs)

    alarm
    |> Alarm.shelve_changeset(%{
      shelved_by_id: attrs[:shelved_by_id] || create_user_id(alarm.organization_id),
      shelved_at: DateTime.add(DateTime.utc_now(), -3600, :second),
      shelved_until: DateTime.add(DateTime.utc_now(), -60, :second),
      shelve_reason: "Shelved for testing"
    })
    |> Repo.update!()
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp ensure_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp ensure_map(attrs) when is_map(attrs), do: attrs

  # Creates a user for acknowledgment/shelving if none provided
  defp create_user_id(organization_id) do
    org = Repo.get!(Cadence.Organizations.Organization, organization_id)
    user = user_fixture(organization: org)
    user.id
  end
end
