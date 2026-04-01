defmodule Cadence.Runtime.Telemetry.Lanes.ShardWorker do
  @moduledoc """
  Fused shard worker that runs identify -> decom -> convert -> derive in-process
  and appends batches to the durable sink.
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Runtime.Telemetry.PipelineEvent

  alias Cadence.Telemetry.{
    Conversions,
    Decommutation,
    MetricsConfig,
    PipelineRouter,
    Resolve,
    SpacePacket,
    Stats
  }

  alias Cadence.Telemetry.PacketLogRecord
  alias Cadence.Telemetry.PipelineMetrics
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

  @default_max_batch_size 200
  @default_max_batch_delay_ms 10
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
    skip_log_records = Keyword.get(sink_opts, :skip_log_records, false)
    config_version = Keyword.get(opts, :config_version, 0)
    router_version = Keyword.get(opts, :router_version, 1)
    max_batch_size = Keyword.get(opts, :max_batch_size, @default_max_batch_size)
    max_batch_delay_ms = Keyword.get(opts, :max_batch_delay_ms, @default_max_batch_delay_ms)
    max_inflight = Keyword.get(opts, :max_inflight, @default_max_inflight)

    Logger.debug(
      "Starting Lanes.ShardWorker for mission_id=#{mission_id} lane=#{lane} shard_id=#{shard_id}"
    )

    queue_snapshot_interval_ms = MetricsConfig.queue_snapshot_interval_ms()
    queue_sample_timer = maybe_schedule_queue_sample(queue_snapshot_interval_ms)

    state = %{
      mission_id: mission_id,
      lane: lane,
      shard_id: shard_id,
      metrics_refs: PipelineMetrics.partition_refs(mission_id, {lane, shard_id}),
      router: router,
      router_version: router_version,
      config_version: config_version,
      config_bundle: load_config_bundle(mission_id),
      pending_config_version: nil,
      pending_config_bundle: nil,
      sink: sink,
      sink_opts: sink_opts,
      skip_log_records: skip_log_records,
      max_batch_size: max_batch_size,
      max_batch_delay_ms: max_batch_delay_ms,
      max_inflight: max_inflight,
      buffer: [],
      buffer_size: 0,
      buffer_started_ns: nil,
      flush_timer: nil,
      queue_snapshot_interval_ms: queue_snapshot_interval_ms,
      queue_sample_timer: queue_sample_timer
    }

    GenServer.cast(router, {:shard_ready, lane, shard_id, max_inflight})

    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Stopping Lanes.ShardWorker for mission_id=#{state.mission_id} lane=#{state.lane} shard_id=#{state.shard_id} reason=#{inspect(reason)}"
    )

    :ok
  end

  @impl true
  def handle_cast({:telemetry_event, %PipelineEvent{} = event}, state) do
    received_ns = batch_received_ns()
    {:noreply, handle_events([event], received_ns, nil, state)}
  end

  @impl true
  def handle_cast({:telemetry_batch, events}, state) when is_list(events) do
    received_ns = batch_received_ns()
    {:noreply, handle_events(events, received_ns, nil, state)}
  end

  @impl true
  def handle_cast({:telemetry_batch, events, dispatch_ns}, state)
      when is_list(events) and (is_integer(dispatch_ns) or is_nil(dispatch_ns)) do
    received_ns = batch_received_ns()
    {:noreply, handle_events(events, received_ns, dispatch_ns, state)}
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

  def handle_info(:queue_snapshot, state) do
    updated_state = record_queue_gauge(state)
    timer = maybe_schedule_queue_sample(state.queue_snapshot_interval_ms)
    {:noreply, %{updated_state | queue_sample_timer: timer}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp enqueue_events([], _received_ns, state), do: state

  defp enqueue_events(events, received_ns, state) when is_list(events) do
    do_enqueue_events(events, received_ns, state)
  end

  defp do_enqueue_events([], _received_ns, state), do: state

  defp do_enqueue_events(
         events,
         received_ns,
         %{max_batch_size: max_batch_size, buffer_size: buffer_size} = state
       )
       when buffer_size >= max_batch_size do
    do_enqueue_events(events, received_ns, flush_batch(state))
  end

  defp do_enqueue_events(events, received_ns, state) do
    capacity = max(state.max_batch_size - state.buffer_size, 1)
    {chunk, rest} = Enum.split(events, capacity)
    chunk_size = length(chunk)
    buffer = Enum.reverse(chunk, state.buffer)

    updated_state =
      maybe_begin_buffer(
        %{state | buffer: buffer, buffer_size: state.buffer_size + chunk_size},
        chunk_size,
        received_ns
      )

    next_state =
      if updated_state.buffer_size >= updated_state.max_batch_size do
        flush_batch(updated_state)
      else
        updated_state
      end

    do_enqueue_events(rest, received_ns, next_state)
  end

  defp handle_events([], _received_ns, _dispatch_ns, state), do: state

  defp handle_events(events, received_ns, dispatch_ns, state) do
    maybe_record_worker_queue_wait(state.metrics_refs, received_ns, dispatch_ns)
    state = maybe_flush_on_followup_dispatch(state, dispatch_ns)
    state = maybe_swap_config(state, List.last(events))
    state = enqueue_events(events, received_ns, state)
    finalize_enqueue(state)
  end

  defp maybe_swap_config(state, %PipelineEvent{config_version: config_version}) do
    if config_version != state.config_version and config_version == state.pending_config_version do
      state
      |> maybe_flush_before_swap()
      |> apply_pending_bundle()
    else
      state
    end
  end

  defp maybe_swap_config(state, _event), do: state

  defp maybe_flush_on_followup_dispatch(%{buffer_size: 0} = state, _dispatch_ns), do: state
  defp maybe_flush_on_followup_dispatch(state, nil), do: state
  defp maybe_flush_on_followup_dispatch(state, _dispatch_ns), do: flush_batch(state)

  defp finalize_enqueue(%{buffer_size: 0} = state), do: state
  defp finalize_enqueue(state), do: ensure_flush_timer(state)

  defp ensure_flush_timer(%{flush_timer: nil} = state) do
    timer =
      TimeTimer.send_after(self(), :flush_batch, state.max_batch_delay_ms)

    %{state | flush_timer: timer}
  end

  defp ensure_flush_timer(state), do: state

  defp flush_batch(%{buffer_size: 0} = state), do: state

  defp flush_batch(state) do
    flush_started_ns = batch_received_ns()
    maybe_record_worker_buffer_wait(state.metrics_refs, state.buffer_started_ns, flush_started_ns)

    if state.flush_timer do
      TimeTimer.cancel(state.flush_timer)
    end

    events = Enum.reverse(state.buffer)

    {records, processed, items_processed, pending_end_to_end} =
      events
      |> Enum.reduce({[], 0, 0, []}, fn event,
                                        {acc_records, processed_count, item_count, pending} ->
        {:ok, event_records, items, end_to_end_status} = process_event(event, state)

        updated_pending =
          case end_to_end_status do
            :append -> [event | pending]
            _ -> pending
          end

        {event_records ++ acc_records, processed_count + 1, item_count + items, updated_pending}
      end)

    PipelineMetrics.inc_refs(state.metrics_refs, :packets_processed, processed)
    PipelineMetrics.inc_refs(state.metrics_refs, :items_processed, items_processed)

    append_result = maybe_append(records, pending_end_to_end, state)
    maybe_record_batch_end_to_end(pending_end_to_end, append_result, state)
    GenServer.cast(state.router, {:shard_ready, state.lane, state.shard_id, length(events)})
    maybe_record_worker_batch_total(state.metrics_refs, flush_started_ns, batch_received_ns())

    state
    |> Map.put(:buffer, [])
    |> Map.put(:buffer_size, 0)
    |> Map.put(:buffer_started_ns, nil)
    |> Map.put(:flush_timer, nil)
    |> apply_pending_bundle()
  end

  defp process_event(%PipelineEvent{} = event, state) do
    records =
      maybe_prepend_record([], state, fn ->
        PacketLogRecord.envelope_record(event.envelope, state.lane, state.shard_id)
      end)

    case event.parse_error do
      nil ->
        process_event_v2_with_parse(event, records, state)

      parse_error ->
        publish_sink(event.mission_id, :malformed, %{
          envelope: event.envelope,
          parsed_unit: event.parsed_unit,
          resolved_unit: nil,
          reason: %{parse_error: parse_error}
        })

        maybe_record_end_to_end(event, state)
        {:ok, records, 0, :recorded}
    end
  end

  defp process_event_v2_with_parse(%PipelineEvent{parsed_unit: nil} = event, records, state) do
    publish_sink(event.mission_id, :malformed, %{
      envelope: event.envelope,
      parsed_unit: nil,
      resolved_unit: nil,
      reason: %{parse_error: :missing_parsed_unit}
    })

    maybe_record_end_to_end(event, state)
    {:ok, records, 0, :recorded}
  end

  defp process_event_v2_with_parse(%PipelineEvent{} = event, records, state) do
    resolved =
      maybe_time_pipeline(state, :resolve, fn ->
        Resolve.resolve(event.envelope, event.parsed_unit, state.config_bundle)
      end)

    records =
      maybe_prepend_record(records, state, fn ->
        PacketLogRecord.classification_record(resolved, state.lane, state.shard_id)
      end)

    record_resolution_metrics(state, resolved)

    route_resolved_event(event, records, resolved, state)
  end

  defp route_resolved_event(event, records, resolved, state) do
    case PipelineRouter.route_resolved(resolved) do
      {:decom, _resolved} ->
        handle_decom_route(event, records, resolved, state)

      {:sink, sink, reason} ->
        handle_sink_route(event, records, resolved, sink, reason, state)
    end
  end

  defp handle_decom_route(event, records, resolved, state) do
    result =
      maybe_time_pipeline(state, :decom, fn ->
        decom_space_packet(event.parsed_unit, resolved)
      end)

    case result do
      {:ok, raw_items} ->
        handle_decom_success(event, records, resolved, raw_items, state)

      {:error, reason} ->
        handle_decom_error(event, records, resolved, reason, state)
    end
  end

  defp handle_decom_success(event, records, resolved, raw_items, state) do
    {records, item_count} =
      maybe_time_pipeline(state, :worker_post_decom, fn ->
        if state.skip_log_records do
          {records, map_size(raw_items)}
        else
          packet_def = packet_def_from_resolved(resolved)
          converted_items = convert_items(raw_items, packet_def)
          qualified_items = qualify_items(converted_items, resolved)
          apid = apid_from_parsed(event.parsed_unit)
          target_identifier = target_identifier(state.config_bundle, resolved.identity)

          records = [
            PacketLogRecord.decom_record(
              resolved,
              qualified_items,
              apid,
              state.lane,
              state.shard_id,
              target_identifier
            )
            | records
          ]

          {records, map_size(qualified_items)}
        end
      end)

    PipelineMetrics.inc_refs(state.metrics_refs, :packets_decom_processed)

    {:ok, records, item_count, :append}
  end

  defp handle_decom_error(event, records, resolved, reason, state) do
    publish_sink(event.mission_id, :malformed, %{
      envelope: event.envelope,
      parsed_unit: event.parsed_unit,
      resolved_unit: resolved,
      reason: %{decom_error: reason}
    })

    maybe_record_end_to_end(event, state)
    {:ok, records, 0, :recorded}
  end

  defp handle_sink_route(event, records, resolved, sink, reason, state) do
    publish_sink(event.mission_id, sink, %{
      envelope: event.envelope,
      parsed_unit: event.parsed_unit,
      resolved_unit: resolved,
      reason: reason
    })

    maybe_record_end_to_end(event, state)
    {:ok, records, 0, :recorded}
  end

  defp maybe_append([], [], _state), do: :ok

  defp maybe_append([], _pending_events, %{skip_log_records: true} = state) do
    maybe_time_pipeline(state, :log_append, fn -> :ok end)
  end

  defp maybe_append([], _pending_events, _state), do: :ok

  defp maybe_append(records, _pending_events, state) do
    # Logger.debug("[DEBUG] lanes.shard_worker.appending",
    #   mission_id: state.mission_id,
    #   lane: state.lane,
    #   shard_id: state.shard_id,
    #   record_count: length(records),
    #   sink: state.sink
    # )

    append_result =
      maybe_time_pipeline(state, :log_append, fn ->
        state.sink.append(state.shard_id, Enum.reverse(records), state.sink_opts)
      end)

    case append_result do
      {:ok, _meta} ->
        # Logger.debug("[DEBUG] lanes.shard_worker.appended",
        #   mission_id: state.mission_id,
        #   lane: state.lane,
        #   shard_id: state.shard_id,
        #   meta: inspect(meta)
        # )

        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to append to sink on shard #{state.shard_id} (lane=#{state.lane}): #{inspect(reason)}",
          mission_id: state.mission_id
        )

        {:error, reason}
    end
  end

  defp maybe_prepend_record(records, %{skip_log_records: true}, _builder), do: records

  defp maybe_prepend_record(records, _state, builder) when is_function(builder, 0) do
    [builder.() | records]
  end

  defp record_resolution_metrics(state, resolved) do
    record_identity_metrics(state.metrics_refs, resolved.identity)
    record_schema_metrics(state.metrics_refs, resolved.schema)
  end

  defp record_identity_metrics(metric_refs, identity) do
    case identity do
      {:ok, _} -> PipelineMetrics.inc_refs(metric_refs, :packets_resolved_ok)
      {:unresolved, _, _} -> PipelineMetrics.inc_refs(metric_refs, :packets_unresolved)
      {:ambiguous, _, _} -> PipelineMetrics.inc_refs(metric_refs, :packets_ambiguous)
      _ -> :ok
    end
  end

  defp record_schema_metrics(metric_refs, schema) do
    case schema do
      {:ok, _} ->
        PipelineMetrics.inc_refs(metric_refs, :packets_schema_ok)

      {:unknown_apid, _, _, _} ->
        PipelineMetrics.inc_refs(metric_refs, :packets_unknown_apid)

      {:uncataloged_target, _} ->
        PipelineMetrics.inc_refs(metric_refs, :packets_uncataloged_target)

      {:unsupported_format, _} ->
        PipelineMetrics.inc_refs(metric_refs, :packets_unsupported_format)

      _ ->
        :ok
    end
  end

  defp decom_space_packet({:space_packet, %Cadence.Telemetry.SpacePacket{} = packet}, resolved) do
    case resolved.schema do
      {:ok, packet_def} ->
        Decommutation.decommutate(packet.user_data, packet_def, :ccsds)

      _ ->
        {:error, :missing_schema}
    end
  end

  defp decom_space_packet(_parsed_unit, _resolved), do: {:error, :unsupported_format}

  defp qualify_items(raw_items, resolved) do
    case packet_def_name(resolved) do
      name when is_binary(name) ->
        Map.new(raw_items, fn {item_name, value} ->
          {qualify_item_name(name, item_name), value}
        end)

      _ ->
        raw_items
    end
  end

  defp packet_def_from_resolved(%{schema: {:ok, packet_def}}), do: packet_def
  defp packet_def_from_resolved(_), do: nil

  defp convert_items(raw_items, %{items_by_name: items_by_name}) when is_map(items_by_name) do
    Map.new(raw_items, fn {item_name, raw_value} ->
      item_def = Map.get(items_by_name, to_string(item_name))
      {item_name, convert_item_value(raw_value, item_def)}
    end)
  end

  defp convert_items(raw_items, _packet_def), do: raw_items

  defp convert_item_value(raw_value, %{conversion: conversion}) when not is_nil(conversion) do
    case Conversions.apply_db_conversion(raw_value, conversion) do
      {:ok, converted} -> converted
      _ -> raw_value
    end
  end

  defp convert_item_value(raw_value, _item_def), do: raw_value

  defp packet_def_name(%{schema: {:ok, packet_def}}), do: Map.get(packet_def, :name)
  defp packet_def_name(_), do: nil

  defp qualify_item_name(packet_def_name, item_name) do
    item_name = to_string(item_name)

    if String.starts_with?(item_name, packet_def_name <> ".") do
      item_name
    else
      packet_def_name <> "." <> item_name
    end
  end

  defp apid_from_parsed({:space_packet, %SpacePacket{} = packet}) do
    SpacePacket.get_apid(packet)
  end

  defp apid_from_parsed(_), do: nil

  defp target_identifier(%ConfigBundle{targets: targets}, {:ok, target_id}) do
    case Enum.find(targets, fn target -> Map.get(target, :id) == target_id end) do
      nil -> nil
      target -> Map.get(target, :identifier) || Map.get(target, :name)
    end
  end

  defp target_identifier(_bundle, _identity), do: nil

  defp publish_sink(mission_id, sink, payload) do
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "mission:#{mission_id}:telemetry:#{sink}",
      {:telemetry_sink, payload}
    )
  end

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

  defp maybe_time_pipeline(state, stage, fun) when is_function(fun, 0) do
    if MetricsConfig.timing_sample?() do
      t0 = CadenceTime.monotonic(:nanosecond)
      result = fun.()
      t1 = CadenceTime.monotonic(:nanosecond)

      PipelineMetrics.record_timing_refs(state.metrics_refs, stage, div(t1 - t0, 1000))

      result
    else
      fun.()
    end
  end

  defp maybe_record_end_to_end(%PipelineEvent{ingest_monotonic_ns: ingest_ns} = event, state)
       when is_integer(ingest_ns) do
    if MetricsConfig.end_to_end_sample?() do
      now_ns = CadenceTime.monotonic(:nanosecond)
      duration_us = div(max(now_ns - ingest_ns, 0), 1000)

      PipelineMetrics.record_timing_refs(state.metrics_refs, :end_to_end, duration_us)
      Stats.record_timing_sample(state.mission_id, :end_to_end, duration_us)
    end

    event
  end

  defp maybe_record_end_to_end(event, _state), do: event

  defp maybe_record_batch_end_to_end([], _append_result, _state), do: :ok

  defp maybe_record_batch_end_to_end(_events, {:error, _reason}, _state), do: :ok

  defp maybe_record_batch_end_to_end(events, :ok, state) do
    Enum.each(events, &maybe_record_end_to_end(&1, state))
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

  defp record_queue_gauge(state) do
    if MetricsConfig.enable_process_queue_sampling?() do
      {queue_len, memory_kb} =
        case Process.info(self(), [:message_queue_len, :memory]) do
          info when is_list(info) ->
            {
              Keyword.get(info, :message_queue_len, 0),
              div(Keyword.get(info, :memory, 0), 1024)
            }

          _ ->
            {0, 0}
        end

      PipelineMetrics.set_gauge(
        state.mission_id,
        {state.lane, state.shard_id},
        :shard_queue_len,
        queue_len
      )

      PipelineMetrics.set_gauge(
        state.mission_id,
        {state.lane, state.shard_id},
        :shard_buffer_size,
        state.buffer_size
      )

      PipelineMetrics.set_gauge(
        state.mission_id,
        {state.lane, state.shard_id},
        :shard_memory_kb,
        memory_kb
      )
    end

    state
  end

  defp batch_received_ns do
    if MetricsConfig.enable_pipeline_timings?() do
      CadenceTime.monotonic(:nanosecond)
    else
      nil
    end
  end

  defp maybe_begin_buffer(state, 0, _received_ns), do: state

  defp maybe_begin_buffer(%{buffer_size: chunk_size} = state, chunk_size, received_ns)
       when chunk_size > 0 do
    %{state | buffer_started_ns: received_ns || batch_received_ns()}
  end

  defp maybe_begin_buffer(state, _chunk_size, _received_ns), do: state

  defp maybe_record_worker_queue_wait(_metric_refs, nil, _dispatch_ns), do: :ok
  defp maybe_record_worker_queue_wait(_metric_refs, _received_ns, nil), do: :ok

  defp maybe_record_worker_queue_wait(metric_refs, received_ns, dispatch_ns) do
    PipelineMetrics.record_timing_refs(
      metric_refs,
      :worker_queue_wait,
      ns_duration_to_us(received_ns - dispatch_ns)
    )
  end

  defp maybe_record_worker_buffer_wait(_metric_refs, nil, _flush_started_ns), do: :ok
  defp maybe_record_worker_buffer_wait(_metric_refs, _buffer_started_ns, nil), do: :ok

  defp maybe_record_worker_buffer_wait(metric_refs, buffer_started_ns, flush_started_ns) do
    PipelineMetrics.record_timing_refs(
      metric_refs,
      :worker_buffer_wait,
      ns_duration_to_us(flush_started_ns - buffer_started_ns)
    )
  end

  defp maybe_record_worker_batch_total(_metric_refs, nil, _finished_ns), do: :ok
  defp maybe_record_worker_batch_total(_metric_refs, _flush_started_ns, nil), do: :ok

  defp maybe_record_worker_batch_total(metric_refs, flush_started_ns, finished_ns) do
    PipelineMetrics.record_timing_refs(
      metric_refs,
      :worker_batch_total,
      ns_duration_to_us(finished_ns - flush_started_ns)
    )
  end

  defp ns_duration_to_us(duration_ns) when is_integer(duration_ns) do
    div(max(duration_ns, 0), 1000)
  end
end
