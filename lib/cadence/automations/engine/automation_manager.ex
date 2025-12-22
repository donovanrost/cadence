defmodule Cadence.Automations.Engine.AutomationManager do
  @moduledoc """
  Per-mission GenServer that processes events and triggers automations.

  Subscribes to multiple PubSub topics:
  - `mission:<mission_id>:alarms` - Alarm state changes
  - `mission:<mission_id>:events` - Telemetry limit events
  - `mission:<mission_id>:procedures` - Procedure completion events

  Maintains an ETS cache of active automations for fast trigger matching.
  """

  use GenServer
  require Logger

  alias Cadence.Automations
  alias Cadence.Domain.Automations.Entities.Automation
  alias Cadence.Automations.Engine.ActionExecutor
  alias Cadence.Procedures.Events.ProcedureExecutionEvent
  alias Cadence.Ports.Recordings.EventRecorder

  @ets_table :automations_cache

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    name = {:via, Registry, {Cadence.AutomationRegistry, mission_id}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Reloads the automation cache from the database.
  """
  def reload_cache(mission_id) do
    case whereis(mission_id) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :reload_cache)
    end
  end

  @doc """
  Gets the current automation cache for debugging.
  """
  def get_cache(mission_id) do
    case whereis(mission_id) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :get_cache)
    end
  end

  @doc """
  Manually triggers an automation for testing.
  """
  def trigger(mission_id, automation_id, event) do
    case whereis(mission_id) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:manual_trigger, automation_id, event})
    end
  end

  @doc """
  Returns the PID for a mission's automation manager, or nil if not started.
  """
  def whereis(mission_id) do
    case Registry.lookup(Cadence.AutomationRegistry, mission_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    organization_id = Keyword.fetch!(opts, :organization_id)

    # Create ETS table for this mission's automations
    table = :ets.new(@ets_table, [:set, :protected, {:read_concurrency, true}])

    state = %{
      mission_id: mission_id,
      organization_id: organization_id,
      table: table,
      cooldowns: %{}
    }

    # Load initial automations
    load_automations(state)

    # Subscribe to event topics
    subscribe_to_events(mission_id)

    Logger.info("AutomationManager started for mission #{mission_id}")

    {:ok, state}
  end

  @impl true
  def handle_call(:reload_cache, _from, state) do
    load_automations(state)
    {:reply, :ok, state}
  end

  def handle_call(:get_cache, _from, state) do
    automations = :ets.tab2list(state.table)
    {:reply, {:ok, automations}, state}
  end

  def handle_call({:manual_trigger, automation_id, event}, _from, state) do
    case :ets.lookup(state.table, automation_id) do
      [{^automation_id, automation}] ->
        result = execute_automation(automation, event, state)
        {:reply, result, state}

      [] ->
        {:reply, {:error, :automation_not_found}, state}
    end
  end

  @impl true
  def handle_info({:alarm_triggered, alarm}, state) do
    process_event("alarm_fired", alarm_to_event(alarm), state)
    {:noreply, state}
  end

  def handle_info({:alarm_cleared, alarm}, state) do
    process_event("alarm_cleared", alarm_to_event(alarm), state)
    {:noreply, state}
  end

  def handle_info({:alarm_acknowledged, alarm}, state) do
    process_event("alarm_acknowledged", alarm_to_event(alarm), state)
    {:noreply, state}
  end

  def handle_info({:limit_event, event}, state) do
    process_event("telemetry_limit", limit_event_to_map(event), state)
    {:noreply, state}
  end

  # Handle formal procedure execution events
  def handle_info(
        {:procedure_event, %ProcedureExecutionEvent{event_type: :completed} = event},
        state
      ) do
    process_event("procedure_completed", procedure_event_to_map(event), state)
    {:noreply, state}
  end

  def handle_info(
        {:procedure_event, %ProcedureExecutionEvent{event_type: :failed} = event},
        state
      ) do
    process_event("procedure_failed", procedure_event_to_map(event), state)
    {:noreply, state}
  end

  def handle_info(
        {:procedure_event, %ProcedureExecutionEvent{event_type: :started} = event},
        state
      ) do
    process_event("procedure_started", procedure_event_to_map(event), state)
    {:noreply, state}
  end

  def handle_info(
        {:procedure_event, %ProcedureExecutionEvent{event_type: :cancelled} = event},
        state
      ) do
    process_event("procedure_cancelled", procedure_event_to_map(event), state)
    {:noreply, state}
  end

  def handle_info(
        {:procedure_event, %ProcedureExecutionEvent{event_type: :paused} = event},
        state
      ) do
    process_event("procedure_paused", procedure_event_to_map(event), state)
    {:noreply, state}
  end

  def handle_info(
        {:procedure_event, %ProcedureExecutionEvent{event_type: :step_started} = event},
        state
      ) do
    process_event("procedure_step_started", procedure_event_to_map(event), state)
    {:noreply, state}
  end

  def handle_info(
        {:procedure_event, %ProcedureExecutionEvent{event_type: :step_completed} = event},
        state
      ) do
    process_event("procedure_step_completed", procedure_event_to_map(event), state)
    {:noreply, state}
  end

  # Keep legacy handlers for backwards compatibility during transition
  def handle_info({:execution_completed, execution}, state) do
    process_event("procedure_completed", execution_to_event(execution), state)
    {:noreply, state}
  end

  def handle_info({:execution_failed, execution}, state) do
    process_event("procedure_failed", execution_to_event(execution), state)
    {:noreply, state}
  end

  def handle_info({:automation_updated, automation_id}, state) do
    # Reload single automation when updated
    # Use unscoped version since we're the internal engine and already scoped by mission
    case Automations.get_automation_unscoped(automation_id) do
      nil ->
        :ets.delete(state.table, automation_id)

      automation ->
        if automation.enabled do
          :ets.insert(state.table, {automation_id, automation})
        else
          :ets.delete(state.table, automation_id)
        end
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp subscribe_to_events(mission_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:procedures")
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:automations")
  end

  defp load_automations(state) do
    automations =
      Automations.list_automations(
        state.organization_id,
        mission_id: state.mission_id,
        enabled_only: true
      )

    # Clear existing entries for this mission
    :ets.delete_all_objects(state.table)

    # Insert all enabled automations
    Enum.each(automations, fn automation ->
      :ets.insert(state.table, {automation.id, automation})
    end)

    Logger.debug("Loaded #{length(automations)} automations for mission #{state.mission_id}")
  end

  defp process_event(trigger_type, event, state) do
    # Find matching automations for this trigger type
    # The domain entity stores trigger_type as an atom, so convert for comparison
    trigger_type_atom = String.to_existing_atom(trigger_type)

    matching_automations =
      state.table
      |> :ets.tab2list()
      |> Enum.filter(fn {_id, automation} ->
        automation.trigger_type == trigger_type_atom &&
          Automations.matches_conditions?(automation, event)
      end)
      |> Enum.map(fn {_id, automation} -> automation end)

    # Execute each matching automation
    Enum.each(matching_automations, fn automation ->
      case Automations.check_rate_limits(automation) do
        {:ok, :allowed} ->
          execute_automation(automation, event, state)

        {:error, :cooldown} ->
          Logger.debug("Automation #{automation.id} in cooldown, skipping")
          record_skipped(automation, :cooldown, state)

        {:error, :rate_limited} ->
          Logger.debug("Automation #{automation.id} rate limited, skipping")
          record_skipped(automation, :rate_limited, state)
      end
    end)
  end

  defp execute_automation(%Automation{} = automation, event, state) do
    # Generate idempotency key from automation + event
    # This prevents duplicate executions for the exact same event
    idempotency_key = generate_idempotency_key(automation, event)

    Logger.info(
      "Executing automation '#{automation.name}' (#{automation.id}) " <>
        "for trigger #{automation.trigger_type} (idempotency_key: #{idempotency_key})"
    )

    # Create execution record with idempotency key
    # If this returns {:error, :already_exists}, skip execution
    case Automations.create_execution(%{
           automation_id: automation.id,
           organization_id: state.organization_id,
           mission_id: state.mission_id,
           trigger_event: event,
           idempotency_key: idempotency_key,
           started_at: DateTime.utc_now()
         }) do
      {:ok, execution} ->
        # Record that automation was triggered
        record_triggered(automation, event, state)

        # Execute the action
        result =
          ActionExecutor.execute(automation.action_type, automation.action_config, event, state)

        # Update execution status
        case result do
          {:ok, action_result} ->
            Automations.update_execution_status(execution, %{
              status: :completed,
              action_result: action_result,
              completed_at: DateTime.utc_now()
            })

            Automations.record_trigger(automation)
            record_completed(automation, action_result, state)
            {:ok, execution}

          {:error, reason} ->
            Automations.update_execution_status(execution, %{
              status: :failed,
              error_message: inspect(reason),
              completed_at: DateTime.utc_now()
            })

            record_failed(automation, reason, state)
            {:error, reason}
        end

      {:error, :duplicate} ->
        Logger.debug(
          "Skipping duplicate automation execution: #{automation.id} with key #{idempotency_key}"
        )

        {:error, :duplicate}

      {:error, reason} ->
        Logger.error("Failed to create automation execution: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Generate an idempotency key from automation and event
  # This ensures we don't process the exact same event twice
  defp generate_idempotency_key(automation, event) do
    event_id = extract_event_id(event)
    "automation:#{automation.id}:event:#{event_id}"
  end

  # Extract a unique identifier from the event
  defp extract_event_id(event) when is_map(event) do
    # Priority order for event identification:
    # 1. Explicit event_id
    # 2. Alarm-specific: alarm_id + state change hash
    # 3. Procedure-specific: execution_id + event_type
    # 4. Hash of the entire event
    cond do
      Map.has_key?(event, :event_id) ->
        event.event_id

      Map.has_key?(event, "event_id") ->
        event["event_id"]

      Map.has_key?(event, :alarm_id) ->
        # For alarms, include state to distinguish fired vs cleared
        state = Map.get(event, :state) || Map.get(event, "state") || "unknown"
        "alarm:#{event.alarm_id}:#{state}"

      Map.has_key?(event, :execution_id) ->
        # For procedure events, include event_type
        event_type = Map.get(event, :event_type) || Map.get(event, "event_type") || "unknown"
        "proc:#{event.execution_id}:#{event_type}"

      true ->
        # Fallback: hash the event
        :crypto.hash(:sha256, :erlang.term_to_binary(event))
        |> Base.encode16(case: :lower)
        |> String.slice(0, 32)
    end
  end

  # ============================================================================
  # Event Conversion
  # ============================================================================

  defp alarm_to_event(alarm) do
    %{
      alarm_id: alarm.id,
      alarm_type: alarm.alarm_type,
      alarm_rule_id: alarm.alarm_rule_id,
      source_type: alarm.source_type,
      source_id: alarm.source_id,
      target_id: alarm.target_id,
      severity: alarm.severity,
      status: alarm.status,
      message: alarm.message,
      current_value: alarm.current_value,
      limit_state: alarm.limit_state,
      timestamp: alarm.updated_at
    }
  end

  defp limit_event_to_map(event) do
    %{
      event_id: event.id,
      item_name: event.item_name,
      target_id: event.target_id,
      previous_state: event.previous_state,
      new_state: event.new_state,
      value: event.value,
      limit_set: event.limit_set,
      timestamp: event.timestamp
    }
  end

  defp execution_to_event(execution) do
    %{
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: execution.procedure && execution.procedure.name,
      status: execution.status,
      parameters: execution.parameters,
      triggered_by: execution.triggered_by,
      started_at: execution.started_at,
      completed_at: execution.completed_at,
      error_message: execution.error_message
    }
  end

  defp procedure_event_to_map(%ProcedureExecutionEvent{} = event) do
    %{
      event_id: event.id,
      event_type: event.event_type,
      execution_id: event.execution_id,
      procedure_id: event.procedure_id,
      procedure_name: event.procedure_name,
      mission_id: event.mission_id,
      organization_id: event.organization_id,
      target_id: event.target_id,
      status: event.status,
      previous_status: event.previous_status,
      triggered_by: event.triggered_by,
      parameters: event.parameters,
      error_message: event.error_message,
      step_index: event.step_index,
      step_info: event.step_info,
      started_at: event.started_at,
      completed_at: event.completed_at,
      timestamp: event.timestamp
    }
  end

  # ============================================================================
  # Recording Functions
  # ============================================================================

  defp recorder, do: EventRecorder.impl()

  defp record_triggered(automation, event, state) do
    recorder().record(:automation_triggered, automation, nil, %{
      trigger_event: event,
      organization_id: state.organization_id,
      mission_id: state.mission_id
    })
  end

  defp record_completed(automation, action_result, state) do
    recorder().record(:automation_completed, automation, nil, %{
      action_result: action_result,
      organization_id: state.organization_id,
      mission_id: state.mission_id
    })
  end

  defp record_failed(automation, reason, state) do
    recorder().record(:automation_failed, automation, nil, %{
      error_message: inspect(reason),
      organization_id: state.organization_id,
      mission_id: state.mission_id
    })
  end

  defp record_skipped(automation, reason, state) do
    recorder().record(:automation_skipped, automation, nil, %{
      reason: to_string(reason),
      organization_id: state.organization_id,
      mission_id: state.mission_id
    })
  end
end
