defmodule Cadence.Commanding.Dispatcher do
  @moduledoc false

  use GenServer

  alias Cadence.Commanding.DispatchSupervisor
  alias Cadence.Commanding.LaneDispatcher
  alias Cadence.Control.Commanding

  @default_safety_poll_interval_ms 60_000
  @event_prefix [:cadence, :commanding, :dispatcher]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec reconcile_now(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def reconcile_now(server \\ __MODULE__) do
    GenServer.call(server, :reconcile_now, :infinity)
  end

  @spec kick_lane(binary(), binary(), binary(), keyword()) :: :ok | {:error, term()}
  def kick_lane(organization_id, mission_id, queue_lane_key, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_list(opts) do
    case drain_lane(organization_id, mission_id, queue_lane_key, opts) do
      {:ok, _summary} -> :ok
      {:error, :dispatcher_not_running} -> :ok
      {:error, :noproc} -> :ok
      {:error, %{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec drain_lane(binary(), binary(), binary(), keyword()) ::
          {:ok, LaneDispatcher.drain_summary()} | {:error, term()}
  def drain_lane(organization_id, mission_id, queue_lane_key, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_list(opts) do
    with :ok <-
           DispatchSupervisor.ensure_lane_dispatcher_started(
             organization_id,
             mission_id,
             queue_lane_key,
             Keyword.put_new(opts, :run_on_boot?, false)
           ),
         {:ok, lane_dispatcher} <-
           DispatchSupervisor.lane_dispatcher(organization_id, mission_id, queue_lane_key) do
      LaneDispatcher.drain(lane_dispatcher)
    else
      :error -> {:error, :dispatcher_not_running}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def init(opts) do
    state = %{
      safety_poll_interval_ms:
        Keyword.get(opts, :safety_poll_interval_ms, @default_safety_poll_interval_ms),
      lane_safety_poll_interval_ms:
        Keyword.get(opts, :lane_safety_poll_interval_ms, @default_safety_poll_interval_ms),
      auto_schedule?: Keyword.get(opts, :auto_schedule?, true),
      run_on_boot?: Keyword.get(opts, :run_on_boot?, true)
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    _ = Commanding.requeue_release_pending_queue_entries()

    if state.run_on_boot? do
      _ = reconcile_dispatch_lanes(state, :boot)
    end

    schedule_next_reconcile(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:reconcile_now, _from, state) do
    summary = reconcile_dispatch_lanes(state, :manual)
    {:reply, {:ok, summary}, state}
  end

  @impl true
  def handle_info(:reconcile, state) do
    _ = reconcile_dispatch_lanes(state, :safety)
    schedule_next_reconcile(state)
    {:noreply, state}
  end

  defp reconcile_dispatch_lanes(state, reason) do
    pending_lanes = Commanding.list_pending_queue_lanes()

    Enum.each(pending_lanes, fn lane ->
      :ok =
        DispatchSupervisor.ensure_lane_dispatcher_started(
          lane.organization_id,
          lane.mission_id,
          lane.queue_lane_key,
          safety_poll_interval_ms: state.lane_safety_poll_interval_ms
        )
    end)

    summary = %{pending_lane_count: length(pending_lanes)}
    emit(:reconcile, state, summary, %{reason: reason})
    summary
  end

  defp schedule_next_reconcile(%{
         auto_schedule?: true,
         safety_poll_interval_ms: safety_poll_interval_ms
       }) do
    Process.send_after(self(), :reconcile, safety_poll_interval_ms)
  end

  defp schedule_next_reconcile(_state), do: :ok

  defp emit(event, state, measurements, metadata) when is_atom(event) do
    :telemetry.execute(
      @event_prefix ++ [event],
      measurements,
      Map.merge(metadata, %{
        safety_poll_interval_ms: state.safety_poll_interval_ms,
        lane_safety_poll_interval_ms: state.lane_safety_poll_interval_ms
      })
    )
  end
end
