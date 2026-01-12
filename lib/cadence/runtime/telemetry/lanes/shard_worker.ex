defmodule Cadence.Runtime.Telemetry.Lanes.ShardWorker do
  @moduledoc """
  Fused shard worker that runs identify -> decom -> convert -> derive in-process
  and appends batches to the durable sink.
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Runtime.Telemetry.Lanes.Event
  alias Cadence.Runtime.Telemetry.Limits.StateTracker
  alias Cadence.Telemetry.{Convert, Decom, Derive, Identify}

  alias Cadence.Telemetry.LogEnvelope
  alias Cadence.Telemetry.PipelineMetrics

  @timing_sample_rate 100
  @default_max_batch_size 200
  @default_max_batch_delay_ms 50
  @default_max_inflight 5_000

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lane = Keyword.fetch!(opts, :lane)
    shard_id = Keyword.fetch!(opts, :shard_id)
    router = Keyword.fetch!(opts, :router)
    sink = Keyword.get(opts, :sink, Cadence.Telemetry.LogSink.Noop)
    sink_opts = Keyword.get(opts, :sink_opts, [])
    config_version = Keyword.get(opts, :config_version, 0)
    router_version = Keyword.get(opts, :router_version, 1)
    max_batch_size = Keyword.get(opts, :max_batch_size, @default_max_batch_size)
    max_batch_delay_ms = Keyword.get(opts, :max_batch_delay_ms, @default_max_batch_delay_ms)
    max_inflight = Keyword.get(opts, :max_inflight, @default_max_inflight)

    state = %{
      mission_id: mission_id,
      lane: lane,
      shard_id: shard_id,
      router: router,
      router_version: router_version,
      config_version: config_version,
      config_bundle: load_config_bundle(mission_id),
      pending_config_version: nil,
      pending_config_bundle: nil,
      sink: sink,
      sink_opts: sink_opts,
      max_batch_size: max_batch_size,
      max_batch_delay_ms: max_batch_delay_ms,
      max_inflight: max_inflight,
      buffer: [],
      buffer_size: 0,
      flush_timer: nil
    }

    GenServer.cast(router, {:shard_ready, lane, shard_id, max_inflight})

    {:ok, state}
  end

  @impl true
  def handle_cast({:telemetry_event, event}, state) do
    state =
      if event.config_version != state.config_version and
           event.config_version == state.pending_config_version do
        state
        |> maybe_flush_before_swap()
        |> apply_pending_bundle()
      else
        state
      end

    state = enqueue_event(event, state)

    state =
      if state.buffer_size >= state.max_batch_size do
        flush_batch(state)
      else
        ensure_flush_timer(state)
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush_batch, state) do
    {:noreply, flush_batch(state)}
  end

  @impl true
  def handle_info({:config_version, version}, state) when is_integer(version) do
    pending_bundle = load_config_bundle(state.mission_id)

    {:noreply,
     %{
       state
       | pending_config_version: version,
         pending_config_bundle: pending_bundle
     }}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp enqueue_event(event, state) do
    buffer = [event | state.buffer]

    %{state | buffer: buffer, buffer_size: state.buffer_size + 1}
  end

  defp ensure_flush_timer(%{flush_timer: nil} = state) do
    timer =
      Process.send_after(self(), :flush_batch, state.max_batch_delay_ms)

    %{state | flush_timer: timer}
  end

  defp ensure_flush_timer(state), do: state

  defp flush_batch(%{buffer_size: 0} = state), do: state

  defp flush_batch(state) do
    if state.flush_timer do
      Process.cancel_timer(state.flush_timer)
    end

    events = Enum.reverse(state.buffer)

    {records, processed, items_processed} =
      events
      |> Enum.reduce({[], 0, 0}, fn event, {acc_records, processed_count, item_count} ->
        case process_event(event, state) do
          {:ok, envelope, items} ->
            {[envelope | acc_records], processed_count + 1, item_count + items}

          {:skip, reason} ->
            Logger.debug(
              "Shard #{state.shard_id} (lane=#{state.lane}) skipped event #{event.id}: #{inspect(reason)}",
              mission_id: state.mission_id
            )

            PipelineMetrics.inc(state.mission_id, {state.lane, state.shard_id}, :packets_dropped)
            {acc_records, processed_count, item_count}

          {:error, reason} ->
            Logger.error(
              "Shard #{state.shard_id} (lane=#{state.lane}) failed event #{event.id}: #{inspect(reason)}",
              mission_id: state.mission_id
            )

            PipelineMetrics.inc(state.mission_id, {state.lane, state.shard_id}, :packets_dropped)
            {acc_records, processed_count, item_count}
        end
      end)

    PipelineMetrics.inc(
      state.mission_id,
      {state.lane, state.shard_id},
      :packets_processed,
      processed
    )

    PipelineMetrics.inc(
      state.mission_id,
      {state.lane, state.shard_id},
      :items_processed,
      items_processed
    )

    maybe_append(records, state)
    GenServer.cast(state.router, {:shard_ready, state.lane, state.shard_id, length(events)})

    state
    |> Map.put(:buffer, [])
    |> Map.put(:buffer_size, 0)
    |> Map.put(:flush_timer, nil)
    |> apply_pending_bundle()
  end

  defp process_event(%Event{} = event, state) do
    stage_state = %{
      mission_id: state.mission_id,
      partition: {state.lane, state.shard_id},
      config_bundle: state.config_bundle
    }

    sample? = :rand.uniform(@timing_sample_rate) == 1

    case run_pipeline(event, stage_state, sample?, state) do
      {:ok, event} ->
        {event, limits_us} = apply_stateless_limits(event, state, sample?)
        _ = timed_stage(:limits, limits_us, sample?, state)

        record_end_to_end(event, sample?, state)

        payload = event.all_items || event.converted_items || event.raw_items || %{}

        envelope = %LogEnvelope{
          mission_id: state.mission_id,
          target_id: event.target_id,
          apid: event.apid,
          lane: state.lane,
          shard_id: state.shard_id,
          router_version: event.router_version,
          config_version: event.config_version,
          sequence: extract_sequence(event.packet),
          ingest_monotonic_ns: event.ingest_monotonic_ns,
          source_wall_clock_ms: to_wall_ms(event.metadata[:received_at]),
          checksum: checksum(event.packet),
          payload: payload,
          meta: %{
            packet_format: event.packet_format,
            packet_def: event.packet_def && event.packet_def.name,
            link_meta: extract_link_meta(event.metadata),
            qualified_items: event.qualified_items,
            items_with_limits: event.items_with_limits
          }
        }

        {:ok, envelope, map_size(payload)}

      {:skip, reason} ->
        {:skip, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_append([], _state), do: :ok

  defp maybe_append(records, state) do
    case state.sink.append(state.shard_id, Enum.reverse(records), state.sink_opts) do
      {:ok, _meta} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to append to sink on shard #{state.shard_id} (lane=#{state.lane}): #{inspect(reason)}",
          mission_id: state.mission_id
        )
    end
  end

  defp checksum(%{raw: raw}) when is_binary(raw), do: :erlang.crc32(raw)
  defp checksum(_), do: nil

  defp extract_sequence(%{ccsds_header: %{sequence_count: seq}}) when is_integer(seq), do: seq
  defp extract_sequence(_), do: nil

  defp to_wall_ms(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)
  defp to_wall_ms(_), do: nil

  defp load_config_bundle(mission_id) do
    case ConfigBundle.fetch(mission_id) do
      {:ok, bundle} -> bundle
      _ -> nil
    end
  end

  defp maybe_flush_before_swap(%{buffer_size: 0} = state), do: state
  defp maybe_flush_before_swap(state), do: flush_batch(state)

  defp apply_pending_bundle(%{pending_config_version: nil} = state), do: state
  defp apply_pending_bundle(%{pending_config_bundle: nil} = state), do: state

  defp apply_pending_bundle(state) do
    %{
      state
      | config_version: state.pending_config_version,
        config_bundle: state.pending_config_bundle,
        pending_config_version: nil,
        pending_config_bundle: nil
    }
  end

  defp maybe_time(true, fun) do
    start = System.monotonic_time(:microsecond)
    result = fun.()
    duration = System.monotonic_time(:microsecond) - start
    {result, duration}
  end

  defp maybe_time(false, fun), do: {fun.(), nil}

  defp timed_stage(_stage, nil, _sample?, _state), do: {:ok, :no_timing}

  defp timed_stage(stage, duration_us, true, state) do
    PipelineMetrics.record_timing(
      state.mission_id,
      {state.lane, state.shard_id},
      stage,
      duration_us
    )

    {:ok, :timed}
  end

  defp timed_stage(_stage, _duration_us, false, _state), do: {:ok, :no_timing}

  defp apply_stateless_limits(%Event{all_items: items} = event, state, sample?)
       when is_map(items) and map_size(items) > 0 do
    {limits_items, limits_us} =
      maybe_time(sample?, fn ->
        StateTracker.evaluate_stateless_batch(
          state.mission_id,
          event.target_id,
          Enum.to_list(items)
        )
      end)

    {%{event | items_with_limits: limits_items}, limits_us}
  end

  defp apply_stateless_limits(event, _state, _sample?), do: {event, nil}

  defp record_end_to_end(%Event{} = event, true, state) do
    now_us = System.monotonic_time(:microsecond)
    ingest_us = div(event.ingest_monotonic_ns, 1_000)
    duration_us = max(now_us - ingest_us, 0)

    PipelineMetrics.record_timing(
      state.mission_id,
      {state.lane, state.shard_id},
      :end_to_end,
      duration_us
    )
  end

  defp record_end_to_end(_event, _sample?, _state), do: :ok

  defp run_pipeline(event, stage_state, sample?, state) do
    with {:ok, event} <- run_stage(:identify, event, stage_state, sample?, state),
         {:ok, event} <- run_stage(:decom, event, stage_state, sample?, state),
         {:ok, event} <- run_stage(:convert, event, stage_state, sample?, state),
         {:ok, event} <- run_stage(:derive, event, stage_state, sample?, state) do
      {:ok, event}
    else
      {:skip, reason} -> {:skip, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_stage(:identify, event, stage_state, sample?, state) do
    {result, duration} = maybe_time(sample?, fn -> Identify.run(event, stage_state) end)
    handle_stage_result(:identify, result, duration, sample?, state)
  end

  defp run_stage(:decom, event, stage_state, sample?, state) do
    {result, duration} = maybe_time(sample?, fn -> Decom.run(event, stage_state) end)
    handle_stage_result(:decom, result, duration, sample?, state)
  end

  defp run_stage(:convert, event, stage_state, sample?, state) do
    {result, duration} = maybe_time(sample?, fn -> Convert.run(event, stage_state) end)
    handle_stage_result(:convert, result, duration, sample?, state)
  end

  defp run_stage(:derive, event, stage_state, sample?, state) do
    {result, duration} = maybe_time(sample?, fn -> Derive.run(event, stage_state) end)
    handle_stage_result(:derive, result, duration, sample?, state)
  end

  defp handle_stage_result(stage, {:ok, event}, duration, sample?, state) do
    _ = timed_stage(stage, duration, sample?, state)
    {:ok, event}
  end

  defp handle_stage_result(_stage, {:skip, reason}, _duration, _sample?, _state),
    do: {:skip, reason}

  defp handle_stage_result(stage, {:error, reason}, _duration, _sample?, state) do
    PipelineMetrics.record_error(state.mission_id, {state.lane, state.shard_id}, stage)
    maybe_record_identify_reason(stage, reason, state)
    {:error, reason}
  end

  defp maybe_record_identify_reason(:identify, {:identify_failed, :missing_packet_catalog}, state) do
    PipelineMetrics.inc(
      state.mission_id,
      {state.lane, state.shard_id},
      :errors_identify_missing_catalog
    )
  end

  defp maybe_record_identify_reason(:identify, {:identify_failed, :unknown_packet}, state) do
    PipelineMetrics.inc(
      state.mission_id,
      {state.lane, state.shard_id},
      :errors_identify_unknown_packet
    )
  end

  defp maybe_record_identify_reason(_stage, _reason, _state), do: :ok

  defp extract_link_meta(metadata) when is_map(metadata) do
    Map.take(metadata, [
      :scid,
      :vcid,
      :map_id,
      :mcfc,
      :vcfc,
      :fhp,
      :ocf,
      :ocf_flag,
      :secondary_header_flag,
      :sync_flag,
      :packet_order_flag,
      :segment_length_id,
      :lane,
      :qos
    ])
  end

  defp extract_link_meta(_), do: %{}
end
