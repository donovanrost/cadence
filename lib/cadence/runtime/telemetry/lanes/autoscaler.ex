defmodule Cadence.Runtime.Telemetry.Lanes.Autoscaler do
  @moduledoc """
  Autoscaler for lane/shard workers based on router backlog depth.
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Telemetry.Lanes.Router
  alias Cadence.Time.Timer, as: TimeTimer

  @default_interval_ms 2_000
  @default_scale_step 500
  @default_min_inflight 1_000
  @default_max_inflight 10_000
  @default_scale_up_threshold 0.7
  @default_scale_down_threshold 0.3

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    name = {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, :autoscaler}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    router = Keyword.fetch!(opts, :router)
    lanes = Keyword.fetch!(opts, :lanes)

    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)

    state = %{
      mission_id: mission_id,
      router: router,
      lanes: lanes,
      interval_ms: interval_ms,
      max_queue_depth: Keyword.get(opts, :max_queue_depth, 100_000),
      scale_step: Keyword.get(opts, :scale_step, @default_scale_step),
      min_inflight: Keyword.get(opts, :min_inflight, @default_min_inflight),
      max_inflight: Keyword.get(opts, :max_inflight, @default_max_inflight),
      scale_up_threshold: Keyword.get(opts, :scale_up_threshold, @default_scale_up_threshold),
      scale_down_threshold:
        Keyword.get(opts, :scale_down_threshold, @default_scale_down_threshold),
      inflight: init_inflight(lanes)
    }

    schedule_tick(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    depths = Router.queue_depths(state.router)
    {updated_state, updates} = compute_updates(state, depths)

    Enum.each(updates, fn {lane, inflight} ->
      GenServer.cast(state.router, {:set_max_inflight, lane, inflight})
    end)

    schedule_tick(state.interval_ms)
    {:noreply, updated_state}
  end

  defp compute_updates(state, depths) do
    Enum.reduce(state.lanes, {state, []}, fn lane, {acc_state, updates} ->
      depth = Map.get(depths, lane.name, 0)
      max_queue = Map.get(lane, :max_queue_depth) || acc_state.max_queue_depth
      ratio = depth / max_queue
      current = Map.get(acc_state.inflight, lane.name, acc_state.min_inflight)

      {next, reason} =
        cond do
          ratio >= acc_state.scale_up_threshold ->
            {min(current + acc_state.scale_step, acc_state.max_inflight), :scale_up}

          ratio <= acc_state.scale_down_threshold ->
            {max(current - acc_state.scale_step, acc_state.min_inflight), :scale_down}

          true ->
            {current, :steady}
        end

      if next != current do
        Logger.info(
          "Autoscaler adjusted lane=#{lane.name} inflight #{current} -> #{next} (#{reason})",
          mission_id: acc_state.mission_id
        )

        updated_inflight = Map.put(acc_state.inflight, lane.name, next)
        {%{acc_state | inflight: updated_inflight}, [{lane.name, next} | updates]}
      else
        {acc_state, updates}
      end
    end)
  end

  defp init_inflight(lanes) do
    Enum.reduce(lanes, %{}, fn lane, acc ->
      Map.put(acc, lane.name, Map.get(lane, :max_inflight) || @default_min_inflight)
    end)
  end

  defp schedule_tick(interval_ms) do
    TimeTimer.send_after(self(), :tick, interval_ms)
  end
end
