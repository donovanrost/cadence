defmodule Cadence.Automations do
  @moduledoc """
  The Automations context.

  Manages automation rules that trigger procedures in response to events
  like alarm state changes, telemetry limit violations, or procedure completions.
  """

  import Ecto.Query
  alias Cadence.Repo
  alias Cadence.Automations.{Automation, AutomationExecution}

  # ============================================================================
  # Automations
  # ============================================================================

  @doc """
  Lists automations for an organization, optionally filtered by mission.
  """
  def list_automations(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    enabled_only = Keyword.get(opts, :enabled_only, false)
    trigger_type = Keyword.get(opts, :trigger_type)

    Automation
    |> where([a], a.organization_id == ^organization_id)
    |> maybe_filter_by_mission(mission_id)
    |> maybe_filter_enabled(enabled_only)
    |> maybe_filter_trigger_type(trigger_type)
    |> order_by([a], asc: a.name)
    |> Repo.all()
  end

  defp maybe_filter_by_mission(query, nil), do: query

  defp maybe_filter_by_mission(query, mission_id) do
    where(query, [a], a.mission_id == ^mission_id or is_nil(a.mission_id))
  end

  defp maybe_filter_enabled(query, false), do: query
  defp maybe_filter_enabled(query, true), do: where(query, [a], a.enabled == true)

  defp maybe_filter_trigger_type(query, nil), do: query

  defp maybe_filter_trigger_type(query, trigger_type) do
    where(query, [a], a.trigger_type == ^trigger_type)
  end

  @doc """
  Gets a single automation.
  """
  def get_automation(id), do: Repo.get(Automation, id)

  @doc """
  Gets a single automation, raises if not found.
  """
  def get_automation!(id), do: Repo.get!(Automation, id)

  @doc """
  Creates an automation.
  """
  def create_automation(attrs) do
    %Automation{}
    |> Automation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an automation.
  """
  def update_automation(%Automation{} = automation, attrs) do
    automation
    |> Automation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an automation.
  """
  def delete_automation(%Automation{} = automation) do
    Repo.delete(automation)
  end

  @doc """
  Enables an automation.
  """
  def enable_automation(%Automation{} = automation) do
    update_automation(automation, %{enabled: true})
  end

  @doc """
  Disables an automation.
  """
  def disable_automation(%Automation{} = automation) do
    update_automation(automation, %{enabled: false})
  end

  @doc """
  Records that an automation was triggered.
  Updates the trigger tracking fields.
  """
  def record_trigger(%Automation{} = automation) do
    automation
    |> Automation.trigger_changeset(%{
      last_triggered_at: DateTime.utc_now(),
      trigger_count: (automation.trigger_count || 0) + 1
    })
    |> Repo.update()
  end

  # ============================================================================
  # Executions
  # ============================================================================

  @doc """
  Lists automation executions, optionally filtered.
  """
  def list_executions(opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    automation_id = Keyword.get(opts, :automation_id)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    AutomationExecution
    |> maybe_filter(:organization_id, organization_id)
    |> maybe_filter(:mission_id, mission_id)
    |> maybe_filter(:automation_id, automation_id)
    |> maybe_filter(:status, status)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

  @doc """
  Gets an execution by ID.
  """
  def get_execution(id), do: Repo.get(AutomationExecution, id)

  @doc """
  Gets an execution by ID with preloads.
  """
  def get_execution!(id) do
    AutomationExecution
    |> Repo.get!(id)
    |> Repo.preload([:automation])
  end

  @doc """
  Creates an execution record.

  If the execution has an idempotency_key that already exists, returns
  `{:error, :duplicate}` to signal that this is a duplicate event.
  """
  def create_execution(attrs) do
    %AutomationExecution{}
    |> AutomationExecution.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, execution} ->
        {:ok, execution}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        # Check if this is a duplicate idempotency key error
        if Keyword.has_key?(errors, :idempotency_key) do
          {:error, :duplicate}
        else
          {:error, changeset}
        end
    end
  end

  @doc """
  Updates an execution's status.
  """
  def update_execution_status(%AutomationExecution{} = execution, attrs) do
    execution
    |> AutomationExecution.status_changeset(attrs)
    |> Repo.update()
  end

  # ============================================================================
  # Rate Limiting
  # ============================================================================

  @doc """
  Checks if an automation can be triggered based on its rate limits.

  Returns:
  - `{:ok, :allowed}` if the trigger is allowed
  - `{:error, :cooldown}` if still in cooldown period
  - `{:error, :rate_limited}` if max executions per hour exceeded
  """
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

  defp in_cooldown?(%Automation{cooldown_seconds: nil}), do: false
  defp in_cooldown?(%Automation{cooldown_seconds: 0}), do: false
  defp in_cooldown?(%Automation{last_triggered_at: nil}), do: false

  defp in_cooldown?(%Automation{cooldown_seconds: seconds, last_triggered_at: last}) do
    cooldown_end = DateTime.add(last, seconds, :second)
    DateTime.compare(DateTime.utc_now(), cooldown_end) == :lt
  end

  defp rate_limited?(%Automation{max_executions_per_hour: nil}), do: false

  defp rate_limited?(%Automation{id: id, max_executions_per_hour: max}) do
    one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)

    count =
      AutomationExecution
      |> where([e], e.automation_id == ^id)
      |> where([e], e.inserted_at >= ^one_hour_ago)
      |> select([e], count(e.id))
      |> Repo.one()

    count >= max
  end

  # ============================================================================
  # Condition Matching
  # ============================================================================

  @doc """
  Checks if an event matches an automation's trigger conditions.

  Returns `true` if all conditions match, `false` otherwise.
  """
  def matches_conditions?(%Automation{trigger_conditions: nil}, _event), do: true

  def matches_conditions?(%Automation{trigger_conditions: conditions}, _event)
      when conditions == %{},
      do: true

  def matches_conditions?(%Automation{trigger_conditions: conditions}, event) do
    Enum.all?(conditions, fn {key, value} ->
      matches_condition?(key, value, event)
    end)
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
end
