defmodule Cadence.Domain.Automations.Entities.Automation do
  @moduledoc """
  Domain entity representing an automation rule.

  Automations trigger procedures or actions in response to events like
  alarm state changes, telemetry limit violations, or procedure completions.

  This is a pure domain entity with no Ecto dependencies.
  """

  alias Cadence.Time, as: CadenceTime

  @type trigger_type ::
          :alarm_fired
          | :alarm_cleared
          | :alarm_acknowledged
          | :telemetry_limit
          | :procedure_started
          | :procedure_completed
          | :procedure_failed
          | :procedure_cancelled
          | :procedure_paused
          | :procedure_step_started
          | :procedure_step_completed

  @type action_type ::
          :execute_procedure
          | :acknowledge_alarm
          | :shelve_alarm
          | :send_notification

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t(),
          description: String.t() | nil,
          enabled: boolean(),
          trigger_type: trigger_type(),
          trigger_conditions: map(),
          action_type: action_type(),
          action_config: map(),
          cooldown_seconds: non_neg_integer(),
          max_executions_per_hour: pos_integer() | nil,
          last_triggered_at: DateTime.t() | nil,
          trigger_count: non_neg_integer(),
          organization_id: String.t(),
          mission_id: String.t() | nil,
          target_id: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:name, :trigger_type, :action_type, :organization_id]
  defstruct [
    :id,
    :name,
    :description,
    :trigger_type,
    :action_type,
    :last_triggered_at,
    :max_executions_per_hour,
    :organization_id,
    :mission_id,
    :target_id,
    :created_at,
    :updated_at,
    enabled: true,
    trigger_conditions: %{},
    action_config: %{},
    cooldown_seconds: 0,
    trigger_count: 0
  ]

  @trigger_types ~w(alarm_fired alarm_cleared alarm_acknowledged telemetry_limit procedure_started procedure_completed procedure_failed procedure_cancelled procedure_paused procedure_step_started procedure_step_completed)
  @action_types ~w(execute_procedure acknowledge_alarm shelve_alarm send_notification)

  @doc """
  Creates a new automation entity.

  ## Parameters

  - `attrs` - Map with required keys: `:name`, `:trigger_type`, `:action_type`, `:organization_id`

  ## Returns

  - `{:ok, automation}` - Valid automation created
  - `{:error, reason}` - Validation error
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) do
    with {:ok, name} <- validate_required(attrs, :name),
         {:ok, trigger_type} <- validate_trigger_type(attrs),
         {:ok, action_type} <- validate_action_type(attrs),
         {:ok, organization_id} <- validate_required(attrs, :organization_id),
         {:ok, action_config} <- validate_action_config(action_type, attrs) do
      {:ok,
       %__MODULE__{
         id: Map.get(attrs, :id),
         name: name,
         description: Map.get(attrs, :description),
         enabled: Map.get(attrs, :enabled, true),
         trigger_type: trigger_type,
         trigger_conditions: Map.get(attrs, :trigger_conditions, %{}),
         action_type: action_type,
         action_config: action_config,
         cooldown_seconds: Map.get(attrs, :cooldown_seconds, 0),
         max_executions_per_hour: Map.get(attrs, :max_executions_per_hour),
         last_triggered_at: Map.get(attrs, :last_triggered_at),
         trigger_count: Map.get(attrs, :trigger_count, 0),
         organization_id: organization_id,
         mission_id: Map.get(attrs, :mission_id),
         target_id: Map.get(attrs, :target_id),
         created_at: Map.get(attrs, :created_at),
         updated_at: Map.get(attrs, :updated_at)
       }}
    end
  end

  @doc """
  Enables the automation.
  """
  @spec enable(t()) :: {:ok, t()}
  def enable(%__MODULE__{} = automation) do
    {:ok, %{automation | enabled: true}}
  end

  @doc """
  Disables the automation.
  """
  @spec disable(t()) :: {:ok, t()}
  def disable(%__MODULE__{} = automation) do
    {:ok, %{automation | enabled: false}}
  end

  @doc """
  Records that the automation was triggered.

  Increments trigger_count and sets last_triggered_at.
  """
  @spec record_trigger(t()) :: {:ok, t()}
  def record_trigger(%__MODULE__{} = automation) do
    {:ok,
     %{
       automation
       | last_triggered_at: CadenceTime.now(),
         trigger_count: automation.trigger_count + 1
     }}
  end

  @doc """
  Updates the automation with new attributes.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = automation, attrs) do
    {:ok, automation}
    |> maybe_update_name(attrs)
    |> maybe_update_description(attrs)
    |> maybe_update_enabled(attrs)
    |> maybe_update_trigger_type(attrs)
    |> maybe_update_trigger_conditions(attrs)
    |> maybe_update_action_type(attrs)
    |> maybe_update_action_config(attrs)
    |> maybe_update_cooldown(attrs)
    |> maybe_update_max_executions(attrs)
    |> maybe_update_mission(attrs)
    |> maybe_update_target(attrs)
  end

  @doc """
  Checks if the automation is in cooldown period.
  """
  @spec in_cooldown?(t()) :: boolean()
  def in_cooldown?(%__MODULE__{cooldown_seconds: nil}), do: false
  def in_cooldown?(%__MODULE__{cooldown_seconds: 0}), do: false
  def in_cooldown?(%__MODULE__{last_triggered_at: nil}), do: false

  def in_cooldown?(%__MODULE__{cooldown_seconds: seconds, last_triggered_at: last}) do
    cooldown_end = DateTime.add(last, seconds, :second)
    DateTime.compare(CadenceTime.now(), cooldown_end) == :lt
  end

  @doc """
  Checks if an event matches this automation's trigger conditions.
  """
  @spec matches_conditions?(t(), map()) :: boolean()
  def matches_conditions?(%__MODULE__{trigger_conditions: nil}, _event), do: true

  def matches_conditions?(%__MODULE__{trigger_conditions: conditions}, _event)
      when conditions == %{},
      do: true

  def matches_conditions?(%__MODULE__{trigger_conditions: conditions}, event) do
    Enum.all?(conditions, fn {key, value} ->
      matches_condition?(key, value, event)
    end)
  end

  @doc """
  Returns the list of valid trigger types.
  """
  @spec trigger_types() :: [String.t()]
  def trigger_types, do: @trigger_types

  @doc """
  Returns the list of valid action types.
  """
  @spec action_types() :: [String.t()]
  def action_types, do: @action_types

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs, key) do
    case Map.get(attrs, key) do
      nil -> {:error, {:required, key}}
      "" -> {:error, {:required, key}}
      value -> {:ok, value}
    end
  end

  defp validate_trigger_type(attrs) do
    case Map.get(attrs, :trigger_type) do
      nil -> {:error, {:required, :trigger_type}}
      type when is_atom(type) -> {:ok, type}
      type when type in @trigger_types -> {:ok, String.to_existing_atom(type)}
      _ -> {:error, {:invalid, :trigger_type}}
    end
  end

  defp validate_action_type(attrs) do
    case Map.get(attrs, :action_type) do
      nil -> {:error, {:required, :action_type}}
      type when is_atom(type) -> {:ok, type}
      type when type in @action_types -> {:ok, String.to_existing_atom(type)}
      _ -> {:error, {:invalid, :action_type}}
    end
  end

  defp validate_action_config(:execute_procedure, attrs) do
    config = Map.get(attrs, :action_config, %{})

    if Map.has_key?(config, "procedure_id") or Map.has_key?(config, :procedure_id) do
      {:ok, config}
    else
      {:error, {:missing_config, :procedure_id}}
    end
  end

  defp validate_action_config(_action_type, attrs) do
    {:ok, Map.get(attrs, :action_config, %{})}
  end

  defp maybe_update_name({:ok, automation}, %{name: name}) when is_binary(name) and name != "" do
    {:ok, %{automation | name: name}}
  end

  defp maybe_update_name(result, _), do: result

  defp maybe_update_description({:ok, automation}, %{description: desc}) do
    {:ok, %{automation | description: desc}}
  end

  defp maybe_update_description(result, _), do: result

  defp maybe_update_enabled({:ok, automation}, %{enabled: enabled}) when is_boolean(enabled) do
    {:ok, %{automation | enabled: enabled}}
  end

  defp maybe_update_enabled(result, _), do: result

  defp maybe_update_trigger_type({:ok, automation}, %{trigger_type: type})
       when type in @trigger_types do
    {:ok, %{automation | trigger_type: String.to_existing_atom(type)}}
  end

  defp maybe_update_trigger_type({:ok, automation}, %{trigger_type: type}) when is_atom(type) do
    {:ok, %{automation | trigger_type: type}}
  end

  defp maybe_update_trigger_type(result, _), do: result

  defp maybe_update_trigger_conditions({:ok, automation}, %{trigger_conditions: conditions})
       when is_map(conditions) do
    {:ok, %{automation | trigger_conditions: conditions}}
  end

  defp maybe_update_trigger_conditions(result, _), do: result

  defp maybe_update_action_type({:ok, automation}, %{action_type: type})
       when type in @action_types do
    {:ok, %{automation | action_type: String.to_existing_atom(type)}}
  end

  defp maybe_update_action_type({:ok, automation}, %{action_type: type}) when is_atom(type) do
    {:ok, %{automation | action_type: type}}
  end

  defp maybe_update_action_type(result, _), do: result

  defp maybe_update_action_config({:ok, automation}, %{action_config: config})
       when is_map(config) do
    {:ok, %{automation | action_config: config}}
  end

  defp maybe_update_action_config(result, _), do: result

  defp maybe_update_cooldown({:ok, automation}, %{cooldown_seconds: seconds})
       when is_integer(seconds) and seconds >= 0 do
    {:ok, %{automation | cooldown_seconds: seconds}}
  end

  defp maybe_update_cooldown(result, _), do: result

  defp maybe_update_max_executions({:ok, automation}, %{max_executions_per_hour: max})
       when is_nil(max) or (is_integer(max) and max > 0) do
    {:ok, %{automation | max_executions_per_hour: max}}
  end

  defp maybe_update_max_executions(result, _), do: result

  defp maybe_update_mission({:ok, automation}, %{mission_id: mission_id}) do
    {:ok, %{automation | mission_id: mission_id}}
  end

  defp maybe_update_mission(result, _), do: result

  defp maybe_update_target({:ok, automation}, %{target_id: target_id}) do
    {:ok, %{automation | target_id: target_id}}
  end

  defp maybe_update_target(result, _), do: result

  # Condition matching logic
  defp matches_condition?("severity_in", severities, event) when is_list(severities) do
    event_severity = Map.get(event, :severity) || Map.get(event, "severity")
    to_string(event_severity) in Enum.map(severities, &to_string/1)
  end

  defp matches_condition?("item_pattern", pattern, event) do
    item_name = Map.get(event, :item_name) || Map.get(event, "item_name")
    item_name && String.match?(item_name, ~r/#{pattern}/)
  end

  defp matches_condition?("alarm_rule_id", rule_id, event) do
    event_rule_id = Map.get(event, :alarm_rule_id) || Map.get(event, "alarm_rule_id")
    to_string(event_rule_id) == to_string(rule_id)
  end

  defp matches_condition?("target_id", target_id, event) do
    event_target_id = Map.get(event, :target_id) || Map.get(event, "target_id")
    to_string(event_target_id) == to_string(target_id)
  end

  defp matches_condition?("state_in", states, event) when is_list(states) do
    event_state = Map.get(event, :new_state) || Map.get(event, "new_state")
    to_string(event_state) in Enum.map(states, &to_string/1)
  end

  defp matches_condition?("previous_state_in", states, event) when is_list(states) do
    previous_state = Map.get(event, :previous_state) || Map.get(event, "previous_state")
    to_string(previous_state) in Enum.map(states, &to_string/1)
  end

  defp matches_condition?("procedure_id", procedure_id, event) do
    event_proc_id = Map.get(event, :procedure_id) || Map.get(event, "procedure_id")
    to_string(event_proc_id) == to_string(procedure_id)
  end

  defp matches_condition?("procedure_name_pattern", pattern, event) do
    proc_name = Map.get(event, :procedure_name) || Map.get(event, "procedure_name")
    proc_name && String.match?(proc_name, ~r/#{pattern}/)
  end

  defp matches_condition?(_key, _value, _event), do: true
end
