defmodule Cadence.Application.Automations.AutomationOperations do
  @moduledoc """
  Use case module for automation CRUD and state operations.

  This module provides operations for creating, updating, deleting,
  enabling/disabling automations, and recording trigger events.

  All operations:
  1. Validate using schema/changeset logic
  2. Persist via repository
  3. Optionally broadcast for cache updates

  ## Usage

      # Create an automation
      {:ok, automation} = AutomationOperations.create(attrs)

      # Enable an automation
      {:ok, automation} = AutomationOperations.enable(automation)

      # Record a trigger
      {:ok, automation} = AutomationOperations.record_trigger(automation)
  """

  alias Cadence.Automations.Automation
  alias Cadence.Application.Automations.AutomationQueries

  @type automation_id :: String.t()
  @type organization_id :: String.t()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :automation_repository,
      Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationRepository
    )
  end

  # Get configured event publisher
  defp event_publisher do
    Application.get_env(
      :cadence,
      :event_publisher,
      Cadence.Adapters.Messaging.PhoenixEventPublisher
    )
  end

  @doc """
  Creates a new automation.

  ## Parameters

  - `attrs` - Map containing automation attributes:
    - `:name` (required)
    - `:organization_id` (required)
    - `:trigger_type` (required)
    - `:procedure_id` (required)
    - `:mission_id` (optional)
    - `:trigger_conditions` (optional)
    - `:enabled` (optional, default: true)
    - `:cooldown_seconds` (optional)
    - `:max_executions_per_hour` (optional)

  ## Returns

  - `{:ok, automation}` - Successfully created
  - `{:error, changeset}` - Validation failed
  """
  @spec create(map()) :: {:ok, Automation.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    automation = struct(Automation, attrs)

    case repo().save(automation) do
      {:ok, saved} ->
        broadcast_change(saved, :created)
        {:ok, saved}

      error ->
        error
    end
  end

  @doc """
  Updates an existing automation.

  ## Parameters

  - `automation` - The automation to update
  - `attrs` - Map of attributes to update

  ## Returns

  - `{:ok, automation}` - Successfully updated
  - `{:error, changeset}` - Validation failed
  """
  @spec update(Automation.t(), map()) :: {:ok, Automation.t()} | {:error, Ecto.Changeset.t()}
  def update(%Automation{} = automation, attrs) do
    updated = struct(automation, attrs)

    case repo().save(updated) do
      {:ok, saved} ->
        broadcast_change(saved, :updated)
        {:ok, saved}

      error ->
        error
    end
  end

  @doc """
  Deletes an automation.

  ## Returns

  - `{:ok, automation}` - Successfully deleted
  - `{:error, reason}` - Deletion failed
  """
  @spec delete(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def delete(%Automation{} = automation) do
    case repo().delete(automation) do
      {:ok, deleted} ->
        broadcast_change(deleted, :deleted)
        {:ok, deleted}

      error ->
        error
    end
  end

  @doc """
  Enables an automation.

  ## Returns

  - `{:ok, automation}` - Successfully enabled
  - `{:error, changeset}` - Update failed
  """
  @spec enable(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def enable(%Automation{} = automation) do
    case repo().enable(automation) do
      {:ok, enabled} ->
        broadcast_change(enabled, :enabled)
        {:ok, enabled}

      error ->
        error
    end
  end

  @doc """
  Disables an automation.

  ## Returns

  - `{:ok, automation}` - Successfully disabled
  - `{:error, changeset}` - Update failed
  """
  @spec disable(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def disable(%Automation{} = automation) do
    case repo().disable(automation) do
      {:ok, disabled} ->
        broadcast_change(disabled, :disabled)
        {:ok, disabled}

      error ->
        error
    end
  end

  @doc """
  Records that an automation was triggered.

  Updates last_triggered_at and increments trigger_count.

  ## Returns

  - `{:ok, automation}` - Successfully recorded
  - `{:error, changeset}` - Update failed
  """
  @spec record_trigger(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def record_trigger(%Automation{} = automation) do
    repo().record_trigger(automation)
  end

  @doc """
  Checks if an automation can be triggered based on its rate limits.

  Returns:
  - `{:ok, :allowed}` if the trigger is allowed
  - `{:error, :cooldown}` if still in cooldown period
  - `{:error, :rate_limited}` if max executions per hour exceeded
  """
  @spec check_rate_limits(Automation.t()) :: {:ok, :allowed} | {:error, :cooldown | :rate_limited}
  def check_rate_limits(%Automation{} = automation) do
    cond do
      in_cooldown?(automation) ->
        {:error, :cooldown}

      rate_limited?(automation) ->
        {:error, :rate_limited}

      true ->
        {:ok, :allowed}
    end
  end

  @doc """
  Checks if an event matches an automation's trigger conditions.

  Returns `true` if all conditions match, `false` otherwise.
  """
  @spec matches_conditions?(Automation.t(), map()) :: boolean()
  def matches_conditions?(%Automation{trigger_conditions: nil}, _event), do: true

  def matches_conditions?(%Automation{trigger_conditions: conditions}, _event)
      when conditions == %{},
      do: true

  def matches_conditions?(%Automation{trigger_conditions: conditions}, event) do
    Enum.all?(conditions, fn {key, value} ->
      matches_condition?(key, value, event)
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp in_cooldown?(%Automation{cooldown_seconds: nil}), do: false
  defp in_cooldown?(%Automation{cooldown_seconds: 0}), do: false
  defp in_cooldown?(%Automation{last_triggered_at: nil}), do: false

  defp in_cooldown?(%Automation{cooldown_seconds: seconds, last_triggered_at: last}) do
    cooldown_end = DateTime.add(last, seconds, :second)
    DateTime.compare(DateTime.utc_now(), cooldown_end) == :lt
  end

  defp rate_limited?(%Automation{max_executions_per_hour: nil}), do: false

  defp rate_limited?(%Automation{id: id, max_executions_per_hour: max}) do
    # Delegate to Automations context for execution counting until
    # we create a dedicated AutomationExecutionRepository
    Cadence.Automations.count_recent_executions(id) >= max
  end

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

  defp broadcast_change(%Automation{organization_id: org_id} = automation, event_type) do
    topic = "organization:#{org_id}:automations"

    event_publisher().publish(topic, %{
      type: :automation_changed,
      event: event_type,
      automation_id: automation.id,
      name: automation.name,
      enabled: automation.enabled
    })
  rescue
    # Don't fail operations if broadcasting fails
    _ -> :ok
  end
end
