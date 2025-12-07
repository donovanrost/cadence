defmodule Cadence.Alarms.Engine.AlarmManager do
  @moduledoc """
  Per-mission GenServer that manages alarm state and processes events.

  The AlarmManager:
  1. Subscribes to the mission's event PubSub topic
  2. Processes incoming TelemetryLimitEvents
  3. Maintains ETS table of active alarms for fast lookup
  4. Broadcasts alarm changes to the alarms PubSub topic
  5. Periodically checks for expired shelved alarms

  ## PubSub Topics

  Subscribes to:
  - `mission:<mission_id>:events` - Receives TelemetryLimitEvent and other events

  Publishes to:
  - `mission:<mission_id>:alarms` - Broadcasts alarm state changes

  ## Broadcast Messages

  - `{:alarm_triggered, %Alarm{}}` - New alarm created
  - `{:alarm_updated, %Alarm{}}` - Alarm value/severity changed
  - `{:alarm_acknowledged, %Alarm{}}` - Alarm acknowledged by user
  - `{:alarm_shelved, %Alarm{}}` - Alarm shelved
  - `{:alarm_unshelved, %Alarm{}}` - Alarm unshelved
  - `{:alarm_cleared, %Alarm{}}` - Alarm condition resolved

  ## Usage

      # Start as part of mission supervision tree
      {AlarmManager, mission_id: mission.id, organization_id: mission.organization_id}

      # Subscribe to alarm updates in LiveView
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:\#{mission_id}:alarms")

      def handle_info({:alarm_triggered, alarm}, socket) do
        # Handle new alarm
      end
  """

  use GenServer
  require Logger

  alias Cadence.Alarms
  alias Cadence.Alarms.Alarm
  alias Cadence.Alarms.Engine.Handlers.TelemetryLimitHandler
  alias Cadence.Telemetry.Events.TelemetryLimitEvent

  @shelve_check_interval :timer.seconds(30)

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    # Note: We use via_tuple/1 for registration, then update metadata with table in init
    GenServer.start_link(__MODULE__, opts, name: via_tuple(mission_id))
  end

  @doc """
  Returns the PID of the alarm manager for a mission.
  """
  @spec whereis(String.t()) :: pid() | nil
  def whereis(mission_id) do
    case Registry.lookup(Cadence.MissionRegistry, {mission_id, :alarm_manager}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Gets active alarms from the ETS cache.

  This is faster than querying the database for real-time dashboard updates.
  """
  @spec get_active_alarms(String.t()) :: [Alarm.t()]
  def get_active_alarms(mission_id) do
    case get_table(mission_id) do
      nil ->
        []

      table ->
        :ets.tab2list(table)
        |> Enum.map(fn {_key, alarm} -> alarm end)
        |> Enum.sort_by(& &1.triggered_at, {:desc, DateTime})
    end
  end

  @doc """
  Gets alarm counts by severity from the ETS cache.
  """
  @spec get_alarm_counts(String.t()) :: %{
          critical: integer(),
          warning: integer(),
          info: integer()
        }
  def get_alarm_counts(mission_id) do
    case get_table(mission_id) do
      nil ->
        %{critical: 0, warning: 0, info: 0}

      table ->
        :ets.foldl(
          fn {_key, alarm}, acc ->
            Map.update(acc, alarm.severity, 1, &(&1 + 1))
          end,
          %{critical: 0, warning: 0, info: 0},
          table
        )
    end
  end

  # Gets the ETS table reference from Registry metadata
  defp get_table(mission_id) do
    case Registry.lookup(Cadence.MissionRegistry, {mission_id, :alarm_manager}) do
      [{_pid, table}] -> table
      [] -> nil
    end
  end

  # ============================================================================
  # Alarm Mutation APIs (for cache consistency)
  # ============================================================================

  @doc """
  Acknowledges an alarm through the AlarmManager, ensuring cache consistency.
  """
  @spec acknowledge_alarm(String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, term()}
  def acknowledge_alarm(mission_id, alarm_id, user_id, note \\ nil) do
    GenServer.call(via_tuple(mission_id), {:acknowledge, alarm_id, user_id, note})
  end

  @doc """
  Shelves an alarm through the AlarmManager, ensuring cache consistency.
  """
  @spec shelve_alarm(String.t(), String.t(), String.t(), integer(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, term()}
  def shelve_alarm(mission_id, alarm_id, user_id, duration_minutes, reason \\ nil) do
    GenServer.call(via_tuple(mission_id), {:shelve, alarm_id, user_id, duration_minutes, reason})
  end

  @doc """
  Unshelves an alarm through the AlarmManager, ensuring cache consistency.
  """
  @spec unshelve_alarm(String.t(), String.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, term()}
  def unshelve_alarm(mission_id, alarm_id, user_id \\ nil) do
    GenServer.call(via_tuple(mission_id), {:unshelve, alarm_id, user_id})
  end

  @doc """
  Clears an alarm through the AlarmManager, ensuring cache consistency.
  """
  @spec clear_alarm(String.t(), String.t(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, term()}
  def clear_alarm(mission_id, alarm_id, user_id \\ nil) do
    GenServer.call(via_tuple(mission_id), {:clear, alarm_id, user_id})
  end

  @doc """
  Updates an alarm's value through the AlarmManager, ensuring cache consistency.
  """
  @spec update_alarm_value(String.t(), String.t(), float(), atom(), atom(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, term()}
  def update_alarm_value(mission_id, alarm_id, value, limit_state, severity, message \\ nil) do
    GenServer.call(via_tuple(mission_id), {:update_value, alarm_id, value, limit_state, severity, message})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    organization_id = Keyword.fetch!(opts, :organization_id)

    Logger.info("Starting AlarmManager for mission #{mission_id}")

    # Create anonymous ETS table for active alarms cache
    # Using anonymous table (reference, not atom) to avoid atom table exhaustion
    table = :ets.new(:alarm_cache, [
      :public,
      :set,
      read_concurrency: true
    ])

    # Update Registry metadata to store the table reference
    # This allows get_active_alarms/1 and get_alarm_counts/1 to access the table
    # without a GenServer call
    Registry.update_value(Cadence.MissionRegistry, {mission_id, :alarm_manager}, fn _ -> table end)

    # Subscribe to mission events
    events_topic = "mission:#{mission_id}:events"
    Phoenix.PubSub.subscribe(Cadence.PubSub, events_topic)

    # Load existing active alarms into cache
    load_active_alarms(mission_id, table)

    # Schedule shelve expiration check
    schedule_shelve_check()

    state = %{
      mission_id: mission_id,
      organization_id: organization_id,
      table: table,
      events_topic: events_topic,
      alarms_topic: "mission:#{mission_id}:alarms"
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:limit_event, %TelemetryLimitEvent{} = event}, state) do
    handle_limit_event(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_shelve_expiration, state) do
    check_shelve_expiration(state)
    schedule_shelve_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call({:acknowledge, alarm_id, user_id, note}, _from, state) do
    alarm = Alarms.get_alarm!(alarm_id)

    case Alarms.do_acknowledge_alarm(alarm, user_id, note) do
      {:ok, updated} ->
        cache_alarm(updated, state.table)
        broadcast_alarm(state.alarms_topic, :alarm_acknowledged, updated)
        {:reply, {:ok, updated}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:shelve, alarm_id, user_id, duration_minutes, reason}, _from, state) do
    alarm = Alarms.get_alarm!(alarm_id)

    case Alarms.do_shelve_alarm(alarm, user_id, duration_minutes, reason) do
      {:ok, updated} ->
        cache_alarm(updated, state.table)
        broadcast_alarm(state.alarms_topic, :alarm_shelved, updated)
        {:reply, {:ok, updated}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:unshelve, alarm_id, user_id}, _from, state) do
    alarm = Alarms.get_alarm!(alarm_id)

    case Alarms.do_unshelve_alarm(alarm, user_id) do
      {:ok, updated} ->
        cache_alarm(updated, state.table)
        broadcast_alarm(state.alarms_topic, :alarm_unshelved, updated)
        {:reply, {:ok, updated}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:clear, alarm_id, user_id}, _from, state) do
    alarm = Alarms.get_alarm!(alarm_id)

    case Alarms.do_clear_alarm(alarm, user_id) do
      {:ok, updated} ->
        remove_from_cache(updated, state.table)
        broadcast_alarm(state.alarms_topic, :alarm_cleared, updated)
        {:reply, {:ok, updated}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:update_value, alarm_id, value, limit_state, severity, message}, _from, state) do
    alarm = Alarms.get_alarm!(alarm_id)

    case Alarms.do_update_alarm_value(alarm, value, limit_state, severity, message) do
      {:ok, updated} ->
        cache_alarm(updated, state.table)
        broadcast_alarm(state.alarms_topic, :alarm_updated, updated)
        {:reply, {:ok, updated}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Terminating AlarmManager for mission #{state.mission_id}")
    :ets.delete(state.table)
    :ok
  end

  # ============================================================================
  # Event Handling
  # ============================================================================

  defp handle_limit_event(%TelemetryLimitEvent{} = event, state) do
    case TelemetryLimitHandler.handle(event, state.organization_id) do
      {:created, alarm, _rule} ->
        cache_alarm(alarm, state.table)
        broadcast_alarm(state.alarms_topic, :alarm_triggered, alarm)

      {:updated, alarm, _rule} ->
        cache_alarm(alarm, state.table)
        broadcast_alarm(state.alarms_topic, :alarm_updated, alarm)

      {:cleared, alarm} ->
        remove_from_cache(alarm, state.table)
        broadcast_alarm(state.alarms_topic, :alarm_cleared, alarm)

      {:no_rule, _event} ->
        :ok

      {:no_action, _event} ->
        :ok
    end
  end

  # ============================================================================
  # Shelve Expiration
  # ============================================================================

  defp check_shelve_expiration(state) do
    now = DateTime.utc_now()

    # Check ETS cache for expired shelved alarms
    :ets.foldl(
      fn {_key, alarm}, acc ->
        if (alarm.status == :shelved and
              alarm.shelved_until) &&
             DateTime.compare(now, alarm.shelved_until) == :gt do
          [alarm | acc]
        else
          acc
        end
      end,
      [],
      state.table
    )
    |> Enum.each(fn alarm ->
      # Use internal function to avoid deadlock (calling back into ourselves)
      case Alarms.do_unshelve_alarm(alarm, nil) do
        {:ok, unshelved} ->
          cache_alarm(unshelved, state.table)
          broadcast_alarm(state.alarms_topic, :alarm_unshelved, unshelved)

        {:error, reason} ->
          Logger.error("Failed to unshelve alarm #{alarm.id}: #{inspect(reason)}")
      end
    end)
  end

  defp schedule_shelve_check do
    Process.send_after(self(), :check_shelve_expiration, @shelve_check_interval)
  end

  # ============================================================================
  # Cache Management
  # ============================================================================

  defp load_active_alarms(mission_id, table_name) do
    alarms = Alarms.list_active_alarms(mission_id)

    Enum.each(alarms, fn alarm ->
      cache_alarm(alarm, table_name)
    end)

    Logger.debug("Loaded #{length(alarms)} active alarms into cache for mission #{mission_id}")
  end

  defp cache_alarm(%Alarm{} = alarm, table_name) do
    key = {alarm.source_type, alarm.source_id, alarm.target_id}
    :ets.insert(table_name, {key, alarm})
  end

  defp remove_from_cache(%Alarm{} = alarm, table_name) do
    key = {alarm.source_type, alarm.source_id, alarm.target_id}
    :ets.delete(table_name, key)
  end

  # ============================================================================
  # PubSub Broadcasting
  # ============================================================================

  defp broadcast_alarm(topic, event_type, %Alarm{} = alarm) do
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {event_type, alarm}
    )
  end

  # ============================================================================
  # Registry Helpers
  # ============================================================================

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :alarm_manager}}}
  end
end
