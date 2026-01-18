defmodule Cadence.Runtime.Telemetry.Limits.StalenessMonitor do
  @moduledoc """
  Monitors telemetry items for staleness and transitions them to :blue state.

  Each mission has its own StalenessMonitor that periodically scans the
  StateTracker ETS table for items that haven't been updated within their
  configured `stale_timeout_ms`.

  ## Staleness Detection

  The monitor runs on a configurable interval (default: 5 seconds) and:
  1. Scans all tracked items in the StateTracker
  2. Identifies items past their stale_timeout_ms
  3. Transitions stale items to :blue state
  4. Emits TelemetryLimitEvent for each transition
  5. Updates the CVT with the new limit state

  ## Configuration

  Each item can have its own `stale_timeout_ms` in its limits configuration.
  If not specified, a default timeout is used.

  ## PubSub Events

  When an item goes stale, a TelemetryLimitEvent is broadcast to:
  `mission:<mission_id>:events`

  ## Usage

  The StalenessMonitor is automatically started as part of the MissionInstance
  supervision tree. No manual intervention is required.

  To manually check for stale items (for testing):

      StalenessMonitor.check_staleness(mission_id)
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.Limits.StateTracker
  alias Cadence.Time.Timer, as: TimeTimer

  @default_check_interval_ms 5_000
  # Note: stale_timeout_ms is passed via opts, default value for reference only
  # @default_stale_timeout_ms 30_000

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the staleness monitor for a specific mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    check_interval = Keyword.get(opts, :check_interval_ms, @default_check_interval_ms)

    GenServer.start_link(
      __MODULE__,
      %{mission_id: mission_id, check_interval: check_interval},
      name: via_tuple(mission_id)
    )
  end

  @doc """
  Manually triggers a staleness check for a mission.

  Returns the number of items transitioned to :blue state.
  """
  @spec check_staleness(String.t()) :: {:ok, non_neg_integer()}
  def check_staleness(mission_id) do
    GenServer.call(via_tuple(mission_id), :check_staleness)
  end

  @doc """
  Gets the current status of the staleness monitor.
  """
  @spec status(String.t()) :: map()
  def status(mission_id) do
    GenServer.call(via_tuple(mission_id), :status)
  end

  @doc """
  Pauses staleness monitoring (useful for testing or maintenance).
  """
  @spec pause(String.t()) :: :ok
  def pause(mission_id) do
    GenServer.call(via_tuple(mission_id), :pause)
  end

  @doc """
  Resumes staleness monitoring after being paused.
  """
  @spec resume(String.t()) :: :ok
  def resume(mission_id) do
    GenServer.call(via_tuple(mission_id), :resume)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(%{mission_id: mission_id, check_interval: check_interval}) do
    Logger.info(
      "Starting staleness monitor for mission=#{mission_id}, " <>
        "check_interval=#{check_interval}ms"
    )

    # Schedule first check
    schedule_check(check_interval)

    {:ok,
     %{
       mission_id: mission_id,
       check_interval: check_interval,
       paused: false,
       last_check: nil,
       items_marked_stale: 0,
       total_checks: 0
     }}
  end

  @impl GenServer
  def handle_call(:check_staleness, _from, state) do
    count = do_staleness_check(state.mission_id)

    new_state = %{
      state
      | last_check: Cadence.Time.now(),
        items_marked_stale: state.items_marked_stale + count
    }

    {:reply, {:ok, count}, new_state}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    status = %{
      mission_id: state.mission_id,
      check_interval_ms: state.check_interval,
      paused: state.paused,
      last_check: state.last_check,
      items_marked_stale: state.items_marked_stale,
      total_checks: state.total_checks
    }

    {:reply, status, state}
  end

  @impl GenServer
  def handle_call(:pause, _from, state) do
    Logger.info("Staleness monitor paused for mission=#{state.mission_id}")
    {:reply, :ok, %{state | paused: true}}
  end

  @impl GenServer
  def handle_call(:resume, _from, state) do
    Logger.info("Staleness monitor resumed for mission=#{state.mission_id}")
    schedule_check(state.check_interval)
    {:reply, :ok, %{state | paused: false}}
  end

  @impl GenServer
  def handle_info(:check_staleness, %{paused: true} = state) do
    # Don't schedule next check when paused
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:check_staleness, state) do
    count = do_staleness_check(state.mission_id)

    # Schedule next check
    schedule_check(state.check_interval)

    new_state = %{
      state
      | last_check: Cadence.Time.now(),
        items_marked_stale: state.items_marked_stale + count,
        total_checks: state.total_checks + 1
    }

    {:noreply, new_state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.info("Staleness monitor stopping for mission=#{state.mission_id}")
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_staleness_check(mission_id) do
    # Get all stale items from StateTracker
    stale_items = StateTracker.get_stale_items(mission_id)

    # Mark each item as stale and update CVT
    Enum.reduce(stale_items, 0, fn {target_id, item_name, _entry}, count ->
      case StateTracker.mark_stale(mission_id, target_id, item_name) do
        {:ok, true} ->
          # Update CVT with blue state
          update_cvt_stale(mission_id, target_id, item_name)
          count + 1

        {:ok, false} ->
          # Already stale or not found
          count
      end
    end)
  end

  defp update_cvt_stale(mission_id, target_id, qualified_item_name) do
    # Parse qualified name to get packet and item name
    case String.split(qualified_item_name, ".", parts: 2) do
      [packet_name, item_name] ->
        # Get current value from CVT to preserve it
        case CurrentValueTable.get(mission_id, target_id, packet_name, item_name) do
          {:ok, current} ->
            # Update with blue state
            CurrentValueTable.set(
              mission_id,
              target_id,
              packet_name,
              item_name,
              current.value,
              limits_state: :blue,
              received_time: current.received_time,
              packet_time: current.packet_time
            )

          {:error, :not_found} ->
            # Item not in CVT, nothing to update
            :ok
        end

      _ ->
        Logger.warning("Invalid qualified item name: #{qualified_item_name}")
        :ok
    end
  end

  defp schedule_check(interval) do
    TimeTimer.send_after(self(), :check_staleness, interval)
  end

  defp via_tuple(mission_id) when is_binary(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :staleness_monitor}}}
  end
end
