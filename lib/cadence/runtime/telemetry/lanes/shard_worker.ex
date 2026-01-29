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

    Logger.debug(
      "Starting Lanes.ShardWorker for mission_id=#{mission_id} lane=#{lane} shard_id=#{shard_id}"
    )

    queue_snapshot_interval_ms = MetricsConfig.queue_snapshot_interval_ms()
    queue_sample_timer = maybe_schedule_queue_sample(queue_snapshot_interval_ms)

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

  def handle_info(:queue_snapshot, state) do
    updated_state = record_queue_gauge(state)
    timer = maybe_schedule_queue_sample(state.queue_snapshot_interval_ms)
    {:noreply, %{updated_state | queue_sample_timer: timer}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp enqueue_event(event, state) do
    buffer = [event | state.buffer]

    %{state | buffer: buffer, buffer_size: state.buffer_size + 1}
  end

  defp ensure_flush_timer(%{flush_timer: nil} = state) do
    timer =
      TimeTimer.send_after(self(), :flush_batch, state.max_batch_delay_ms)

    %{state | flush_timer: timer}
  end

  defp ensure_flush_timer(state), do: state

  defp flush_batch(%{buffer_size: 0} = state), do: state

  defp flush_batch(state) do
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

    append_result = maybe_append(records, state)
    maybe_record_batch_end_to_end(pending_end_to_end, append_result, state)
    GenServer.cast(state.router, {:shard_ready, state.lane, state.shard_id, length(events)})

    state
    |> Map.put(:buffer, [])
    |> Map.put(:buffer_size, 0)
    |> Map.put(:flush_timer, nil)
    |> apply_pending_bundle()
  end

  defp process_event(%PipelineEvent{} = event, state) do
    records = [PacketLogRecord.envelope_record(event.envelope, state.lane, state.shard_id)]

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

    records = [
      PacketLogRecord.classification_record(resolved, state.lane, state.shard_id) | records
    ]

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

    PipelineMetrics.inc(
      state.mission_id,
      {state.lane, state.shard_id},
      :packets_decom_processed
    )

    {:ok, records, map_size(qualified_items), :append}
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

  defp maybe_append([], _state), do: :ok

  defp maybe_append(records, state) do
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

  defp record_resolution_metrics(state, resolved) do
    partition = {state.lane, state.shard_id}

    record_identity_metrics(state, partition, resolved.identity)
    record_schema_metrics(state, partition, resolved.schema)
  end

  defp record_identity_metrics(state, partition, identity) do
    case identity do
      {:ok, _} -> PipelineMetrics.inc(state.mission_id, partition, :packets_resolved_ok)
      {:unresolved, _, _} -> PipelineMetrics.inc(state.mission_id, partition, :packets_unresolved)
      {:ambiguous, _, _} -> PipelineMetrics.inc(state.mission_id, partition, :packets_ambiguous)
      _ -> :ok
    end
  end

  defp record_schema_metrics(state, partition, schema) do
    case schema do
      {:ok, _} ->
        PipelineMetrics.inc(state.mission_id, partition, :packets_schema_ok)

      {:unknown_apid, _, _, _} ->
        PipelineMetrics.inc(state.mission_id, partition, :packets_unknown_apid)

      {:uncataloged_target, _} ->
        PipelineMetrics.inc(state.mission_id, partition, :packets_uncataloged_target)

      {:unsupported_format, _} ->
        PipelineMetrics.inc(state.mission_id, partition, :packets_unsupported_format)

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

      PipelineMetrics.record_timing(
        state.mission_id,
        {state.lane, state.shard_id},
        stage,
        div(t1 - t0, 1000)
      )

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
      partition = {state.lane, state.shard_id}

      PipelineMetrics.record_timing(state.mission_id, partition, :end_to_end, duration_us)
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
      queue_len =
        case Process.info(self(), :message_queue_len) do
          {:message_queue_len, len} -> len
          _ -> 0
        end

      PipelineMetrics.set_gauge(
        state.mission_id,
        {state.lane, state.shard_id},
        :shard_queue_len,
        queue_len
      )
    end

    state
  end
end
