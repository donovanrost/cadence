defmodule Cadence.Runtime.Telemetry.Lanes.Router do
  @moduledoc """
  Lane-aware router that subscribes to the raw telemetry PubSub topic and
  dispatches events to shard workers.
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Telemetry.Lanes.{LaneConfig, LaneSelector}
  alias Cadence.Runtime.Telemetry.PipelineEvent
  alias Cadence.Telemetry.{MetricsConfig, PacketEnvelope, Parse, SpacePacket}
  alias Cadence.Telemetry.PipelineMetrics
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

  @default_max_queue_depth 100_000
  @default_max_inflight 5_000
  @default_max_dispatch_batch_size 200
  @high_watermark_ratio 0.8
  @low_watermark_ratio 0.5

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the total queue depth across all lanes.
  """
  def queue_depth(pid) do
    GenServer.call(pid, :queue_depth)
  end

  @doc """
  Returns queue depth per lane.
  """
  def queue_depths(pid) do
    GenServer.call(pid, :queue_depths)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lanes = LaneConfig.from_opts(opts)
    router_version = Keyword.get(opts, :router_version, 1)
    config_version = Keyword.get(opts, :config_version, 0)
    max_queue_depth = Keyword.get(opts, :max_queue_depth, @default_max_queue_depth)
    max_inflight = Keyword.get(opts, :max_inflight, @default_max_inflight)

    max_dispatch_batch_size =
      Keyword.get(opts, :max_dispatch_batch_size, @default_max_dispatch_batch_size)

    lane_summary =
      Enum.map_join(lanes, ", ", fn lane ->
        "#{lane.name}=#{lane.shard_count}"
      end)

    Logger.debug("Starting Lanes.Router for mission_id=#{mission_id}")
    Logger.info("Telemetry router starting for mission_id=#{mission_id}, lanes=#{lane_summary}")

    PipelineMetrics.init_lanes(mission_id, lanes)

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:telemetry:raw")

    lane_state =
      Enum.reduce(lanes, %{}, fn lane, acc ->
        {queues, credits} = init_lane_queues(lane.shard_count)
        lane_max_queue_depth = lane.max_queue_depth || max_queue_depth
        lane_max_inflight = lane.max_inflight || max_inflight

        Map.put(acc, lane.name, %{
          shard_count: lane.shard_count,
          virtual_shards: lane.virtual_shards,
          metric_refs: build_metric_refs(mission_id, lane.name, lane.shard_count),
          max_queue_depth: lane_max_queue_depth,
          max_inflight: lane_max_inflight,
          max_dispatch_batch_size: max(max_dispatch_batch_size, 1),
          high_watermark: floor(lane_max_queue_depth * @high_watermark_ratio),
          low_watermark: floor(lane_max_queue_depth * @low_watermark_ratio),
          backpressure: false,
          queue_depth: 0,
          queues: queues,
          credits: credits,
          dropped_count: 0
        })
      end)

    queue_snapshot_interval_ms = MetricsConfig.queue_snapshot_interval_ms()
    queue_sample_timer = maybe_schedule_queue_sample(queue_snapshot_interval_ms)

    state = %{
      mission_id: mission_id,
      lanes: lanes,
      lane_state: lane_state,
      router_version: router_version,
      config_version: config_version,
      dispatch_pending: false,
      queue_snapshot_interval_ms: queue_snapshot_interval_ms,
      queue_sample_timer: queue_sample_timer
    }

    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Stopping Lanes.Router for mission_id=#{state.mission_id} reason=#{inspect(reason)}"
    )

    :ok
  end

  @impl true
  def handle_info({:packet_envelope, %PacketEnvelope{} = envelope}, state) do
    {:noreply, handle_packet_envelope(envelope, state)}
  end

  @impl true
  def handle_info(:dispatch_events, state) do
    state =
      state
      |> Map.put(:dispatch_pending, false)
      |> dispatch_events()

    {:noreply, state}
  end

  @impl true
  def handle_info({:config_version, version}, state) when is_integer(version) do
    {:noreply, %{state | config_version: version}}
  end

  @impl true
  def handle_info(:queue_snapshot, state) do
    updated_state = record_queue_gauges(state)
    timer = maybe_schedule_queue_sample(state.queue_snapshot_interval_ms)
    {:noreply, %{updated_state | queue_sample_timer: timer}}
  end

  defp handle_packet_envelope(%PacketEnvelope{} = envelope, state) do
    {result, envelope, parse_us} = maybe_time_parse(envelope)

    {lane, shard_id} = select_lane_and_shard(envelope, result, state)
    lane_state = Map.fetch!(state.lane_state, lane)
    metric_refs = Map.fetch!(lane_state.metric_refs, shard_id)

    event = %PipelineEvent{
      packet_id: envelope.packet_id,
      mission_id: state.mission_id,
      lane: lane,
      shard_id: shard_id,
      router_version: state.router_version,
      config_version: state.config_version,
      envelope: envelope,
      parsed_unit: if(match?({:ok, _}, result), do: elem(result, 1), else: nil),
      parse_error: if(match?({:error, _}, result), do: elem(result, 1), else: nil),
      resolved_unit: nil,
      ingest_monotonic_ns: envelope.ingest_monotonic_ns
    }

    PipelineMetrics.inc_refs(metric_refs, :packets_received)
    PipelineMetrics.inc_refs(metric_refs, :bytes_received, byte_size(envelope.raw))
    maybe_record_parse_timing(metric_refs, parse_us)
    record_parse_metrics(metric_refs, result)

    state
    |> enqueue_event_v2(event)
    |> then(fn updated -> maybe_toggle_backpressure(updated, event.lane) end)
    |> maybe_schedule_dispatch()
  end

  @impl true
  def handle_call(:queue_depth, _from, state) do
    total =
      state.lane_state
      |> Map.values()
      |> Enum.reduce(0, fn lane_state, acc -> acc + lane_state.queue_depth end)

    {:reply, total, state}
  end

  @impl true
  def handle_call(:queue_depths, _from, state) do
    depths =
      state.lane_state
      |> Enum.into(%{}, fn {lane, lane_state} ->
        {lane, lane_state.queue_depth}
      end)

    {:reply, depths, state}
  end

  @impl true
  def handle_cast({:shard_ready, lane, shard_id, count}, state)
      when is_integer(count) and count >= 0 do
    lane_state = Map.fetch!(state.lane_state, lane)

    credits =
      Map.update!(lane_state.credits, shard_id, fn current ->
        min(current + count, lane_state.max_inflight)
      end)

    updated_lane_state = %{lane_state | credits: credits}
    updated_state = put_in(state.lane_state[lane], updated_lane_state)

    {:noreply, maybe_schedule_dispatch(updated_state)}
  end

  @impl true
  def handle_cast({:set_max_inflight, lane, max_inflight}, state)
      when is_integer(max_inflight) and max_inflight > 0 do
    lane_state = Map.fetch!(state.lane_state, lane)

    credits =
      lane_state.credits
      |> Enum.map(fn {shard_id, credit} ->
        {shard_id, min(credit, max_inflight)}
      end)
      |> Enum.into(%{})

    updated_lane_state = %{lane_state | max_inflight: max_inflight, credits: credits}
    updated_state = put_in(state.lane_state[lane], updated_lane_state)

    {:noreply, updated_state}
  end

  defp enqueue(state, event, queue, lane_state) do
    new_queue = :queue.in(event, queue)

    updated_lane_state = %{
      lane_state
      | queues: Map.put(lane_state.queues, event.shard_id, new_queue),
        queue_depth: lane_state.queue_depth + 1
    }

    put_in(state.lane_state[event.lane], updated_lane_state)
  end

  defp enqueue_event_v2(state, %PipelineEvent{} = event) do
    shard_id = event.shard_id
    lane_state = Map.fetch!(state.lane_state, event.lane)
    queue = Map.fetch!(lane_state.queues, shard_id)

    if lane_state.queue_depth >= lane_state.max_queue_depth do
      drop_oldest(state, event, queue, lane_state)
    else
      enqueue(state, event, queue, lane_state)
    end
  end

  defp drop_oldest(state, event, queue, lane_state) do
    metric_refs = Map.fetch!(lane_state.metric_refs, event.shard_id)

    case :queue.out(queue) do
      {{:value, _dropped}, trimmed_queue} ->
        dropped_count = lane_state.dropped_count + 1
        PipelineMetrics.inc_refs(metric_refs, :packets_dropped)

        if rem(dropped_count, 1000) == 0 do
          Logger.warning(
            "Router queue full for lane=#{event.lane}, dropped #{dropped_count} events",
            mission_id: state.mission_id
          )
        end

        new_queue = :queue.in(event, trimmed_queue)

        updated_lane_state = %{
          lane_state
          | queues: Map.put(lane_state.queues, event.shard_id, new_queue),
            dropped_count: dropped_count
        }

        put_in(state.lane_state[event.lane], updated_lane_state)

      {:empty, _} ->
        dropped_count = lane_state.dropped_count + 1
        PipelineMetrics.inc_refs(metric_refs, :packets_dropped)

        updated_lane_state = %{lane_state | dropped_count: dropped_count}
        put_in(state.lane_state[event.lane], updated_lane_state)
    end
  end

  defp dispatch_events(state) do
    Enum.reduce(state.lanes, state, fn lane, acc ->
      Enum.reduce(0..(lane.shard_count - 1), acc, fn shard_id, acc_state ->
        dispatch_shard(lane.name, shard_id, acc_state)
      end)
    end)
  end

  defp maybe_schedule_dispatch(%{dispatch_pending: true} = state), do: state

  defp maybe_schedule_dispatch(state) do
    send(self(), :dispatch_events)
    %{state | dispatch_pending: true}
  end

  defp dispatch_shard(lane, shard_id, state) do
    lane_state = Map.fetch!(state.lane_state, lane)
    queue = Map.fetch!(lane_state.queues, shard_id)
    credit = Map.fetch!(lane_state.credits, shard_id)

    dispatch_from_queue(lane, shard_id, queue, credit, lane_state.max_dispatch_batch_size, state)
  end

  defp dispatch_from_queue(_lane, _shard_id, _queue, credit, _dispatch_batch_size, state)
       when credit <= 0,
       do: state

  defp dispatch_from_queue(lane, shard_id, queue, credit, dispatch_batch_size, state) do
    batch_count = min(credit, dispatch_batch_size)
    {events, new_queue, dispatched_count} = take_dispatch_batch(queue, batch_count)

    if dispatched_count == 0 do
      state
    else
      GenServer.cast(
        shard_name(state.mission_id, lane, shard_id),
        {:telemetry_batch, events, dispatch_started_ns()}
      )

      lane_state = Map.fetch!(state.lane_state, lane)

      new_state = %{
        state
        | lane_state:
            Map.put(state.lane_state, lane, %{
              lane_state
              | queues: Map.put(lane_state.queues, shard_id, new_queue),
                credits: Map.put(lane_state.credits, shard_id, credit - dispatched_count),
                queue_depth: lane_state.queue_depth - dispatched_count
            })
      }

      dispatch_from_queue(
        lane,
        shard_id,
        new_queue,
        credit - dispatched_count,
        dispatch_batch_size,
        new_state
      )
    end
  end

  defp take_dispatch_batch(queue, count) when count <= 0 do
    {[], queue, 0}
  end

  defp take_dispatch_batch(queue, count) do
    do_take_dispatch_batch(queue, count, [])
  end

  defp do_take_dispatch_batch(queue, 0, acc) do
    {Enum.reverse(acc), queue, length(acc)}
  end

  defp do_take_dispatch_batch(queue, remaining, acc) do
    case :queue.out(queue) do
      {{:value, event}, new_queue} ->
        do_take_dispatch_batch(new_queue, remaining - 1, [event | acc])

      {:empty, _} ->
        {Enum.reverse(acc), queue, length(acc)}
    end
  end

  defp shard_name(mission_id, lane, shard_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, {:shard, lane, shard_id}}}}
  end

  defp maybe_toggle_backpressure(state, lane) do
    lane_state = Map.fetch!(state.lane_state, lane)
    depth = lane_state.queue_depth

    cond do
      lane_state.backpressure == false and depth >= lane_state.high_watermark ->
        Logger.warning(
          "Router high watermark exceeded for lane=#{lane} (#{depth}/#{lane_state.max_queue_depth})",
          mission_id: state.mission_id
        )

        updated_lane_state = %{lane_state | backpressure: true}
        put_in(state.lane_state[lane], updated_lane_state)

      lane_state.backpressure == true and depth <= lane_state.low_watermark ->
        Logger.info(
          "Router queue recovered below low watermark for lane=#{lane} (#{depth}/#{lane_state.max_queue_depth})",
          mission_id: state.mission_id
        )

        updated_lane_state = %{lane_state | backpressure: false}
        put_in(state.lane_state[lane], updated_lane_state)

      true ->
        state
    end
  end

  defp init_lane_queues(shard_count) do
    queues =
      for shard <- 0..(shard_count - 1), into: %{} do
        {shard, :queue.new()}
      end

    credits =
      for shard <- 0..(shard_count - 1), into: %{} do
        {shard, 0}
      end

    {queues, credits}
  end

  defp build_metric_refs(mission_id, lane, shard_count) do
    for shard <- 0..(shard_count - 1), into: %{} do
      {shard, PipelineMetrics.partition_refs(mission_id, {lane, shard})}
    end
  end

  defp dispatch_started_ns do
    if MetricsConfig.enable_pipeline_timings?() do
      CadenceTime.monotonic(:nanosecond)
    else
      nil
    end
  end

  defp select_lane_and_shard(envelope, result, state) do
    metadata = envelope.provenance || %{}
    parsed_unit = if(match?({:ok, _}, result), do: elem(result, 1), else: nil)

    lane = LaneSelector.select_lane_envelope(envelope, parsed_unit, metadata, state.lanes)

    lane_config = Enum.find(state.lanes, &(&1.name == lane)) || List.first(state.lanes)
    apid = apid_from_parsed(parsed_unit)

    shard_id =
      compute_shard_v2(
        envelope.packet_id,
        apid,
        lane_config.shard_count,
        lane_config.virtual_shards
      )

    {lane, shard_id}
  end

  defp apid_from_parsed({:space_packet, %SpacePacket{} = packet}) do
    SpacePacket.get_apid(packet)
  end

  defp apid_from_parsed(_), do: nil

  defp compute_shard_v2(packet_id, apid, shard_count, virtual_shards) do
    vnode = :erlang.phash2({packet_id, apid}, virtual_shards)
    rem(vnode, shard_count)
  end

  defp record_parse_metrics(metric_refs, {:ok, _parsed_unit}) do
    PipelineMetrics.inc_refs(metric_refs, :packets_parsed_ok)
  end

  defp record_parse_metrics(metric_refs, {:error, _reason}) do
    PipelineMetrics.inc_refs(metric_refs, :packets_malformed)
  end

  defp maybe_time_parse(envelope) do
    if MetricsConfig.timing_sample?() do
      t0 = CadenceTime.monotonic(:nanosecond)
      {result, updated_envelope} = parse_envelope(envelope)
      t1 = CadenceTime.monotonic(:nanosecond)
      {result, updated_envelope, div(t1 - t0, 1000)}
    else
      {result, updated_envelope} = parse_envelope(envelope)
      {result, updated_envelope, nil}
    end
  end

  defp parse_envelope(envelope) do
    case Parse.run(envelope) do
      {:ok, parsed_unit, updated_envelope} ->
        {{:ok, parsed_unit}, updated_envelope}

      {:error, reason, updated_envelope} ->
        {{:error, reason}, updated_envelope}
    end
  end

  defp maybe_record_parse_timing(_metric_refs, nil), do: :ok

  defp maybe_record_parse_timing(metric_refs, parse_us) do
    PipelineMetrics.record_timing_refs(metric_refs, :parse, parse_us)
  end

  defp maybe_schedule_queue_sample(interval_ms)
       when is_integer(interval_ms) and interval_ms > 0 do
    if MetricsConfig.enable_process_queue_sampling?() do
      TimeTimer.send_after(self(), :queue_snapshot, interval_ms)
    else
      nil
    end
  end

  defp maybe_schedule_queue_sample(_interval_ms), do: nil

  defp record_queue_gauges(state) do
    if MetricsConfig.enable_process_queue_sampling?() do
      Enum.each(state.lane_state, fn lane_entry ->
        record_lane_queue_gauges(state.mission_id, lane_entry)
      end)
    end

    state
  end

  defp record_lane_queue_gauges(mission_id, {lane, lane_state}) do
    Enum.each(lane_state.queues, fn {shard_id, queue} ->
      queue_len = :queue.len(queue)
      PipelineMetrics.set_gauge(mission_id, {lane, shard_id}, :router_queue_len, queue_len)
    end)
  end
end
