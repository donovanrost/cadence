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
    PipelineRouter,
    Resolve,
    SpacePacket
  }

  alias Cadence.Telemetry.PacketLogRecord
  alias Cadence.Telemetry.PipelineMetrics
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

    {records, processed, items_processed} =
      events
      |> Enum.reduce({[], 0, 0}, fn event, {acc_records, processed_count, item_count} ->
        {:ok, event_records, items} = process_event(event, state)
        {event_records ++ acc_records, processed_count + 1, item_count + items}
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

        {:ok, records, 0}
    end
  end

  defp process_event_v2_with_parse(%PipelineEvent{parsed_unit: nil} = event, records, _state) do
    publish_sink(event.mission_id, :malformed, %{
      envelope: event.envelope,
      parsed_unit: nil,
      resolved_unit: nil,
      reason: %{parse_error: :missing_parsed_unit}
    })

    {:ok, records, 0}
  end

  defp process_event_v2_with_parse(%PipelineEvent{} = event, records, state) do
    resolved = Resolve.resolve(event.envelope, event.parsed_unit, state.config_bundle)

    records = [
      PacketLogRecord.classification_record(resolved, state.lane, state.shard_id) | records
    ]

    record_resolution_metrics(state, resolved)

    case PipelineRouter.route_resolved(resolved) do
      {:decom, _resolved} ->
        case decom_space_packet(event.parsed_unit, resolved) do
          {:ok, raw_items} ->
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

            {:ok, records, map_size(qualified_items)}

          {:error, reason} ->
            publish_sink(event.mission_id, :malformed, %{
              envelope: event.envelope,
              parsed_unit: event.parsed_unit,
              resolved_unit: resolved,
              reason: %{decom_error: reason}
            })

            {:ok, records, 0}
        end

      {:sink, sink, reason} ->
        publish_sink(event.mission_id, sink, %{
          envelope: event.envelope,
          parsed_unit: event.parsed_unit,
          resolved_unit: resolved,
          reason: reason
        })

        {:ok, records, 0}
    end
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

    case state.sink.append(state.shard_id, Enum.reverse(records), state.sink_opts) do
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
end
