defmodule Cadence.Alarms.AlarmRule do
  @moduledoc """
  Configurable rules that determine when and how alarms are generated.

  Rules can be scoped at three levels (most specific wins):
  1. Target-specific (organization + mission + target)
  2. Mission-wide (organization + mission)
  3. Organization default (organization only)

  ## Event Types

  - `"telemetry_limit"` - Triggered by TelemetryLimitEvent (limit violations)
  - Future: `"command_failure"`, `"staleness"`, etc.

  ## Conditions

  The `conditions` field is a map that defines what events match this rule:

      # Match any RED limit violation
      %{"limit_state" => ["red"]}

      # Match specific items
      %{
        "limit_state" => ["red", "yellow"],
        "item_name" => ["HEALTH.cpu_temp", "POWER.battery_voltage"]
      }

      # Match items by pattern
      %{
        "limit_state" => ["red"],
        "item_name_pattern" => "POWER.*"
      }

  ## Message Templates

  Message templates support variable interpolation:

      "{{item_name}} is {{limit_state}} (value: {{value}})"

  Available variables depend on event type. For telemetry_limit:
  - `{{item_name}}` - Fully qualified item name
  - `{{limit_state}}` - Current state (yellow, red, blue)
  - `{{value}}` - Current telemetry value
  - `{{previous_state}}` - State before transition
  - `{{target_id}}` - Target identifier

  ## Example

      %AlarmRule{
        name: "Battery Critical",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["red"],
          "item_name_pattern" => "POWER.battery_*"
        },
        severity: :critical,
        message_template: "CRITICAL: {{item_name}} at {{value}}V",
        notification_channels: ["webhook:pagerduty"]
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Organizations.Organization
  alias Cadence.Missions.Mission
  alias Cadence.Targets.Target
  alias Cadence.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @severity_values [:info, :warning, :critical]
  @event_types ["telemetry_limit"]

  schema "alarm_rules" do
    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :target, Target

    # Rule identification
    field :name, :string
    field :description, :string

    # What triggers this rule
    field :event_type, :string
    field :conditions, :map, default: %{}

    # What alarm to generate
    field :severity, Ecto.Enum, values: @severity_values, default: :warning
    field :message_template, :string

    # Behavior modifiers
    field :auto_acknowledge, :boolean, default: false
    field :auto_shelve_duration_minutes, :integer
    field :cooldown_seconds, :integer

    # Notification routing
    field :notification_channels, {:array, :string}, default: []

    # Enable/disable with audit trail
    field :enabled, :boolean, default: true
    field :disabled_at, :utc_datetime
    belongs_to :disabled_by, User, foreign_key: :disabled_by_id
    field :disabled_reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new alarm rule.
  """
  def changeset(alarm_rule, attrs) do
    alarm_rule
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :target_id,
      :name,
      :description,
      :event_type,
      :conditions,
      :severity,
      :message_template,
      :auto_acknowledge,
      :auto_shelve_duration_minutes,
      :cooldown_seconds,
      :notification_channels,
      :enabled
    ])
    |> validate_required([:organization_id, :name, :event_type])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_conditions()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:target_id)
  end

  @doc """
  Changeset for enabling/disabling a rule.
  """
  def enable_changeset(alarm_rule, attrs) do
    alarm_rule
    |> cast(attrs, [:enabled, :disabled_at, :disabled_by_id, :disabled_reason])
    |> validate_required([:enabled])
    |> maybe_clear_disabled_fields()
  end

  @doc """
  Returns the list of valid severity values.
  """
  def valid_severities, do: @severity_values

  @doc """
  Returns the list of valid event types.
  """
  def valid_event_types, do: @event_types

  @doc """
  Calculates the specificity of a rule for ordering.

  Higher specificity = more specific rule.
  - Target-specific: 3
  - Mission-specific: 2
  - Org-wide: 1
  """
  @spec specificity(%__MODULE__{}) :: 1 | 2 | 3
  def specificity(%__MODULE__{target_id: target_id, mission_id: mission_id}) do
    cond do
      not is_nil(target_id) -> 3
      not is_nil(mission_id) -> 2
      true -> 1
    end
  end

  # Private functions

  defp validate_conditions(changeset) do
    case get_change(changeset, :conditions) do
      nil ->
        changeset

      conditions when is_map(conditions) ->
        if valid_conditions?(conditions) do
          changeset
        else
          add_error(changeset, :conditions, "contains invalid condition keys or values")
        end

      _ ->
        add_error(changeset, :conditions, "must be a map")
    end
  end

  defp valid_conditions?(conditions) when is_map(conditions) do
    valid_keys = MapSet.new(["limit_state", "item_name", "item_name_pattern", "target_id"])

    conditions
    |> Map.keys()
    |> Enum.all?(fn key -> MapSet.member?(valid_keys, key) end)
  end

  defp valid_conditions?(_), do: false

  defp maybe_clear_disabled_fields(changeset) do
    case get_change(changeset, :enabled) do
      true ->
        changeset
        |> put_change(:disabled_at, nil)
        |> put_change(:disabled_by_id, nil)
        |> put_change(:disabled_reason, nil)

      _ ->
        changeset
    end
  end
end
