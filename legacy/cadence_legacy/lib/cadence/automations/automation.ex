defmodule Cadence.Automations.Automation do
  @moduledoc """
  Schema for automation rules that trigger procedures in response to events.

  Automations support multiple trigger types:
  - `alarm_fired` - When an alarm transitions to active state
  - `alarm_cleared` - When an alarm is cleared
  - `alarm_acknowledged` - When an alarm is acknowledged by a user
  - `telemetry_limit` - When a telemetry value crosses a limit threshold
  - `procedure_started` - When a procedure execution starts
  - `procedure_completed` - When a procedure execution completes successfully
  - `procedure_failed` - When a procedure execution fails
  - `procedure_cancelled` - When a procedure execution is cancelled
  - `procedure_paused` - When a procedure execution is paused
  - `procedure_step_started` - When a step within a procedure starts
  - `procedure_step_completed` - When a step within a procedure completes

  Each automation has conditions that filter which events trigger it, and
  an action configuration that specifies what to do when triggered.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @trigger_types ~w(alarm_fired alarm_cleared alarm_acknowledged telemetry_limit procedure_started procedure_completed procedure_failed procedure_cancelled procedure_paused procedure_step_started procedure_step_completed)
  @action_types ~w(execute_procedure acknowledge_alarm shelve_alarm send_notification)

  schema "automations" do
    field :name, :string
    field :description, :string
    field :enabled, :boolean, default: true

    # Trigger configuration
    field :trigger_type, :string
    field :trigger_conditions, :map, default: %{}

    # Action configuration
    field :action_type, :string
    field :action_config, :map, default: %{}

    # Rate limiting
    field :cooldown_seconds, :integer, default: 0
    field :max_executions_per_hour, :integer

    # Tracking
    field :last_triggered_at, :utc_datetime
    field :trigger_count, :integer, default: 0

    # Relationships
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :target, Cadence.Targets.Target

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(automation, attrs) do
    automation
    |> cast(attrs, [
      :name,
      :description,
      :enabled,
      :trigger_type,
      :trigger_conditions,
      :action_type,
      :action_config,
      :cooldown_seconds,
      :max_executions_per_hour,
      :organization_id,
      :mission_id,
      :target_id
    ])
    |> validate_required([:name, :trigger_type, :action_type, :organization_id])
    |> validate_inclusion(:trigger_type, @trigger_types)
    |> validate_inclusion(:action_type, @action_types)
    |> validate_number(:cooldown_seconds, greater_than_or_equal_to: 0)
    |> validate_number(:max_executions_per_hour, greater_than: 0)
    |> validate_trigger_conditions()
    |> validate_action_config()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:target_id)
  end

  @doc false
  def trigger_changeset(automation, attrs) do
    automation
    |> cast(attrs, [:last_triggered_at, :trigger_count])
  end

  defp validate_trigger_conditions(changeset) do
    trigger_type = get_field(changeset, :trigger_type)
    conditions = get_field(changeset, :trigger_conditions) || %{}

    case validate_conditions_for_type(trigger_type, conditions) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :trigger_conditions, message)
    end
  end

  defp validate_conditions_for_type("alarm_fired", conditions) do
    validate_alarm_conditions(conditions)
  end

  defp validate_conditions_for_type("alarm_cleared", conditions) do
    validate_alarm_conditions(conditions)
  end

  defp validate_conditions_for_type("alarm_acknowledged", conditions) do
    validate_alarm_conditions(conditions)
  end

  defp validate_conditions_for_type("telemetry_limit", conditions) do
    validate_limit_conditions(conditions)
  end

  defp validate_conditions_for_type("procedure_started", conditions) do
    validate_procedure_conditions(conditions)
  end

  defp validate_conditions_for_type("procedure_completed", conditions) do
    validate_procedure_conditions(conditions)
  end

  defp validate_conditions_for_type("procedure_failed", conditions) do
    validate_procedure_conditions(conditions)
  end

  defp validate_conditions_for_type("procedure_cancelled", conditions) do
    validate_procedure_conditions(conditions)
  end

  defp validate_conditions_for_type("procedure_paused", conditions) do
    validate_procedure_conditions(conditions)
  end

  defp validate_conditions_for_type("procedure_step_started", conditions) do
    validate_step_conditions(conditions)
  end

  defp validate_conditions_for_type("procedure_step_completed", conditions) do
    validate_step_conditions(conditions)
  end

  defp validate_conditions_for_type(nil, _), do: :ok
  defp validate_conditions_for_type(_, _), do: :ok

  defp validate_alarm_conditions(conditions) do
    valid_keys = ~w(severity_in item_pattern alarm_rule_id target_id)

    case Map.keys(conditions) -- valid_keys do
      [] -> :ok
      unknown -> {:error, "unknown condition keys: #{Enum.join(unknown, ", ")}"}
    end
  end

  defp validate_limit_conditions(conditions) do
    valid_keys = ~w(item_pattern state_in previous_state_in target_id)

    case Map.keys(conditions) -- valid_keys do
      [] -> :ok
      unknown -> {:error, "unknown condition keys: #{Enum.join(unknown, ", ")}"}
    end
  end

  defp validate_procedure_conditions(conditions) do
    valid_keys = ~w(procedure_id procedure_name_pattern target_id triggered_by)

    case Map.keys(conditions) -- valid_keys do
      [] -> :ok
      unknown -> {:error, "unknown condition keys: #{Enum.join(unknown, ", ")}"}
    end
  end

  defp validate_step_conditions(conditions) do
    valid_keys = ~w(procedure_id procedure_name_pattern target_id step_type step_index)

    case Map.keys(conditions) -- valid_keys do
      [] -> :ok
      unknown -> {:error, "unknown condition keys: #{Enum.join(unknown, ", ")}"}
    end
  end

  defp validate_action_config(changeset) do
    action_type = get_field(changeset, :action_type)
    config = get_field(changeset, :action_config) || %{}

    case validate_config_for_action(action_type, config) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :action_config, message)
    end
  end

  defp validate_config_for_action("execute_procedure", config) do
    if Map.has_key?(config, "procedure_id") do
      :ok
    else
      {:error, "execute_procedure requires procedure_id"}
    end
  end

  defp validate_config_for_action("acknowledge_alarm", _config), do: :ok
  defp validate_config_for_action("shelve_alarm", _config), do: :ok
  defp validate_config_for_action("send_notification", _config), do: :ok
  defp validate_config_for_action(nil, _), do: :ok
  defp validate_config_for_action(_, _), do: :ok

  def trigger_types, do: @trigger_types
  def action_types, do: @action_types
end
