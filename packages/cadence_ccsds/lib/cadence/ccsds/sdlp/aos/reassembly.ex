defmodule Cadence.CCSDS.SDLP.AOS.Reassembly do
  @moduledoc """
  Pure receiving-end AOS Virtual Channel reception.

  Reception is keyed independently by GVCID and replay stream. It extracts
  Packets from M_PDUs, delivers valid Bitstream Data and VCA_SDUs with VCFC
  loss evidence, validates continuous OID data, and surfaces synchronous OCF
  and Insert SDUs as separate values. Partial Packet disposition is managed by
  the Virtual Channel configuration.
  """

  @behaviour Cadence.CCSDS.SDLP.Reassembly

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}
  alias Cadence.CCSDS.SDLP.AOS.{Configuration, Continuity, MPDU, OnlyIdleData}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec
  alias Cadence.CCSDS.SpacePacket.Stream

  @default_oid_validation :none
  @default_oid_prefix_octets 10

  @impl true
  def init(opts) when is_list(opts) do
    with {:ok, configurations} <- normalize_configurations(opts),
         {:ok, oid_validation} <-
           normalize_oid_validation(Keyword.get(opts, :oid_validation, @default_oid_validation)),
         {:ok, prefix_octets} <-
           normalize_prefix_octets(
             Keyword.get(opts, :oid_validation_prefix_octets, @default_oid_prefix_octets)
           ) do
      {:ok,
       %{
         configurations: configurations,
         continuity: Continuity.init(),
         oid_validation: oid_validation,
         oid_validation_prefix_octets: prefix_octets,
         oid_lfsr_by_physical_channel: %{},
         packet_buffers_by_channel: %{}
       }}
    end
  end

  @impl true
  def ingest(%LinkFrame{profile: :aos} = frame, ctx, state) do
    case ingest_detailed(frame, ctx, state) do
      {:ok, sdus, _anomalies, next_state} -> {:ok, sdus, next_state}
      {:error, reason, _anomalies, next_state} -> {:error, reason, next_state}
    end
  end

  def ingest(%LinkFrame{profile: profile}, _ctx, state),
    do: {:error, {:invalid_profile, profile}, state}

  def ingest(_frame, _ctx, state), do: {:error, :invalid_frame, state}

  @spec ingest_detailed(LinkFrame.t(), map(), map()) ::
          {:ok, [SDUOctets.t()], [map()], map()}
          | {:error, term(), [map()], map()}
  def ingest_detailed(%LinkFrame{profile: :aos} = frame, ctx, state)
      when is_map(ctx) and is_map(state) do
    with {:ok, configuration} <- fetch_configuration(frame, state),
         :ok <- validate_managed_frame(frame, configuration),
         {:ok, continuity, next_continuity} <- Continuity.observe(frame, state.continuity) do
      frame = %{frame | meta: Map.put(frame.meta, :aos_configuration, configuration)}
      state = %{state | continuity: next_continuity}

      {partial_sdus, partial_anomalies, state} =
        handle_packet_loss(frame, ctx, configuration, continuity, state)

      case dispatch_frame(frame, ctx, configuration, continuity, state) do
        {:ok, content_sdus, anomalies, next_state} ->
          auxiliary = auxiliary_sdus(frame, ctx, configuration, continuity)

          {:ok, partial_sdus ++ content_sdus ++ auxiliary,
           continuity.anomalies ++ partial_anomalies ++ anomalies, next_state}

        {:error, reason, anomalies, next_state} ->
          {:error, reason, continuity.anomalies ++ partial_anomalies ++ anomalies, next_state}
      end
    else
      {:error, reason} -> {:error, reason, [], state}
    end
  end

  def ingest_detailed(%LinkFrame{profile: profile}, _ctx, state),
    do: {:error, {:invalid_profile, profile}, [], state}

  @spec stats(map()) :: map()
  def stats(state) when is_map(state) do
    %{
      buffered_virtual_channels: map_size(state.packet_buffers_by_channel),
      buffered_octets:
        state.packet_buffers_by_channel
        |> Map.values()
        |> Enum.sum_by(&byte_size(&1.bytes)),
      observed_virtual_channels: map_size(state.continuity.counts),
      observed_oid_physical_channels: map_size(state.oid_lfsr_by_physical_channel)
    }
  end

  defp dispatch_frame(frame, ctx, configuration, continuity, state) do
    case configuration.data_field_content do
      :m_pdu -> extract_packets(frame, ctx, configuration, continuity, state)
      :b_pdu -> deliver_bitstream(frame, ctx, continuity, state)
      :vca_sdu -> deliver_vca(frame, ctx, continuity, state)
      :idle_data -> handle_oid(frame, configuration, state)
    end
  end

  defp extract_packets(frame, ctx, configuration, continuity, state) do
    pointer = Map.get(frame.meta, :first_header_pointer)
    key = channel_key(frame)

    cond do
      pointer == MPDU.only_idle_data() ->
        discard_for_idle_mpdu(frame, key, state)

      pointer == MPDU.no_packet_starts() ->
        continue_packet(frame, ctx, configuration, continuity, key, state)

      is_integer(pointer) and pointer >= 0 and pointer < byte_size(frame.payload_octets) ->
        process_pointed_zone(frame, ctx, configuration, continuity, key, pointer, state)

      true ->
        {:error, {:invalid_mpdu_first_header_pointer, pointer}, [], clear_packet(state, key)}
    end
  end

  defp discard_for_idle_mpdu(frame, key, state) do
    case Map.get(state.packet_buffers_by_channel, key) do
      nil ->
        {:ok, [], [], state}

      entry ->
        anomaly =
          anomaly(:packet_resynchronization_at_idle_mpdu, frame, %{
            discarded_octets: byte_size(entry.bytes),
            source_frames: entry.source_frames
          })

        {:ok, [], [anomaly], clear_packet(state, key)}
    end
  end

  defp continue_packet(frame, ctx, configuration, continuity, key, state) do
    case Map.get(state.packet_buffers_by_channel, key) do
      nil ->
        orphan =
          anomaly(:orphan_packet_continuation, frame, %{
            discarded_octets: byte_size(frame.payload_octets)
          })

        {:ok, [], [orphan], state}

      entry ->
        combined = entry.bytes <> frame.payload_octets

        case extract_packet_stream(combined, entry, frame, configuration, key, state) do
          {:ok, records, anomalies, next_state} ->
            {records, boundary_anomalies, next_state} =
              enforce_no_start_boundary(records, frame, key, anomalies, next_state)

            deliver_packet_records(
              records,
              frame,
              ctx,
              continuity,
              boundary_anomalies,
              next_state
            )

          {:error, reason, anomalies, next_state} ->
            {:error, reason, anomalies, next_state}
        end
    end
  end

  defp process_pointed_zone(frame, ctx, configuration, continuity, key, pointer, state) do
    <<prefix::binary-size(^pointer), suffix::binary>> = frame.payload_octets
    entry = Map.get(state.packet_buffers_by_channel, key)

    {continued, continuation_anomalies, state} =
      finish_continuation(entry, prefix, frame, configuration, key, state)

    case extract_packet_stream(suffix, nil, frame, configuration, key, state) do
      {:ok, records, anomalies, next_state} ->
        deliver_packet_records(
          continued ++ records,
          frame,
          ctx,
          continuity,
          continuation_anomalies ++ anomalies,
          next_state
        )

      {:error, reason, anomalies, next_state} ->
        {:error, reason, continuation_anomalies ++ anomalies, next_state}
    end
  end

  defp finish_continuation(nil, <<>>, _frame, _configuration, _key, state),
    do: {[], [], state}

  defp finish_continuation(nil, prefix, frame, _configuration, _key, state) do
    orphan = anomaly(:orphan_packet_continuation, frame, %{discarded_octets: byte_size(prefix)})
    {[], [orphan], state}
  end

  defp finish_continuation(entry, prefix, frame, configuration, key, state) do
    case extract_packet_stream(entry.bytes <> prefix, entry, frame, configuration, key, state) do
      {:ok, records, anomalies, next_state} ->
        case Map.get(next_state.packet_buffers_by_channel, key) do
          nil ->
            {records, anomalies, next_state}

          remaining ->
            mismatch =
              anomaly(:first_header_pointer_resynchronization, frame, %{
                discarded_octets: byte_size(remaining.bytes),
                indicated_packet_start: byte_size(prefix)
              })

            {records, anomalies ++ [mismatch], clear_packet(next_state, key)}
        end

      {:error, reason, anomalies, next_state} ->
        failed = anomaly(:continuation_decode_failed, frame, %{reason: reason})
        {[], anomalies ++ [failed], clear_packet(next_state, key)}
    end
  end

  defp enforce_no_start_boundary(records, frame, key, anomalies, state) do
    remaining = Map.get(state.packet_buffers_by_channel, key)

    cond do
      length(records) > 1 ->
        mismatch =
          anomaly(:first_header_pointer_resynchronization, frame, %{
            reason: :multiple_packets_with_no_packet_start,
            packet_count: length(records)
          })

        {[hd(records)], anomalies ++ [mismatch], clear_packet(state, key)}

      records != [] and remaining ->
        mismatch =
          anomaly(:first_header_pointer_resynchronization, frame, %{
            reason: :trailing_octets_after_continued_packet,
            discarded_octets: byte_size(remaining.bytes)
          })

        {records, anomalies ++ [mismatch], clear_packet(state, key)}

      true ->
        {records, anomalies, state}
    end
  end

  defp extract_packet_stream(bytes, prior_entry, frame, configuration, key, state) do
    case Stream.extract(bytes, max_packet_size: configuration.maximum_packet_octets) do
      {:ok, packets, remaining} ->
        records = packet_records(packets, prior_entry, frame)
        next_state = put_remainder(state, key, remaining, packets, prior_entry, frame)
        {:ok, records, [], next_state}

      {:error, reason} ->
        invalid = anomaly(:invalid_space_packet, frame, %{reason: reason})
        {:error, {:invalid_space_packet, reason}, [invalid], clear_packet(state, key)}
    end
  end

  defp packet_records(packets, prior_entry, frame) do
    prior_octets = if(prior_entry, do: byte_size(prior_entry.bytes), else: 0)
    prior_frames = if(prior_entry, do: prior_entry.source_frames, else: [])

    packets
    |> Enum.map_reduce(0, fn packet, offset ->
      source_frames =
        if offset < prior_octets,
          do: Enum.uniq(prior_frames ++ [frame.frame_seq]),
          else: [frame.frame_seq]

      {%{octets: packet, source_frames: source_frames}, offset + byte_size(packet)}
    end)
    |> elem(0)
  end

  defp put_remainder(state, key, <<>>, _packets, _prior_entry, _frame),
    do: clear_packet(state, key)

  defp put_remainder(state, key, remaining, packets, prior_entry, frame) do
    consumed = Enum.sum_by(packets, &byte_size/1)
    prior_octets = if(prior_entry, do: byte_size(prior_entry.bytes), else: 0)

    source_frames =
      case prior_entry do
        %{source_frames: source_frames} when consumed < prior_octets ->
          Enum.uniq(source_frames ++ [frame.frame_seq])

        _other ->
          [frame.frame_seq]
      end

    entry = %{bytes: remaining, source_frames: source_frames, timestamp: frame.timestamp}
    %{state | packet_buffers_by_channel: Map.put(state.packet_buffers_by_channel, key, entry)}
  end

  defp deliver_packet_records(records, frame, ctx, continuity, anomalies, state) do
    case packet_sdus(records, frame, ctx, continuity) do
      {:ok, sdus} -> {:ok, sdus, anomalies, state}
      {:error, reason} -> {:error, reason, anomalies, state}
    end
  end

  defp packet_sdus(records, frame, ctx, continuity) do
    records
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, sdus} ->
      case packet_sdu(record, frame, ctx, continuity) do
        {:ok, nil} -> {:cont, {:ok, sdus}}
        {:ok, sdu} -> {:cont, {:ok, [sdu | sdus]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, sdus} -> {:ok, Enum.reverse(sdus)}
      {:error, _reason} = error -> error
    end
  end

  defp packet_sdu(record, frame, ctx, continuity) do
    <<version::3, _rest::bitstring>> = record.octets

    with :ok <- validate_packet_version(version, frame, ctx) do
      case SpacePacketCodec.decode(record.octets) do
        {:ok, packet} -> packet_delivery(packet, record, frame, ctx, continuity, version)
        {:error, reason} -> {:error, {:invalid_space_packet, reason}}
      end
    end
  end

  defp packet_delivery(packet, record, frame, ctx, continuity, version) do
    if SpacePacket.idle?(packet) do
      {:ok, nil}
    else
      {:ok,
       build_sdu(
         frame,
         ctx,
         continuity,
         :space_packet,
         record.octets,
         :good,
         record.source_frames,
         %{packet_version_number: version}
       )}
    end
  end

  defp validate_packet_version(version, frame, _ctx) do
    configuration = Map.get(frame.meta, :aos_configuration)

    if is_nil(configuration) or version in configuration.valid_packet_version_numbers,
      do: :ok,
      else: {:error, {:invalid_packet_version_number, version}}
  end

  defp deliver_bitstream(frame, ctx, continuity, state) do
    valid_bits = Map.get(frame.meta, :valid_bits)

    cond do
      valid_bits == 0 ->
        {:ok, [], [], clear_packet(state, channel_key(frame))}

      is_integer(valid_bits) and valid_bits > 0 and valid_bits <= bit_size(frame.payload_octets) ->
        octets = binary_part(frame.payload_octets, 0, ceil_div(valid_bits, 8))

        sdu =
          build_sdu(frame, ctx, continuity, :bitstream, octets, :good, [frame.frame_seq], %{
            valid_bits: valid_bits,
            bitstream_data_loss_flag: continuity.loss?
          })

        {:ok, [sdu], [], clear_packet(state, channel_key(frame))}

      true ->
        {:error, {:invalid_bitstream_data_length, valid_bits}, [], state}
    end
  end

  defp deliver_vca(frame, ctx, continuity, state) do
    sdu =
      build_sdu(
        frame,
        ctx,
        continuity,
        :vca_sdu,
        frame.payload_octets,
        :good,
        [frame.frame_seq],
        %{
          vca_sdu_loss_flag: continuity.loss?
        }
      )

    {:ok, [sdu], [], clear_packet(state, channel_key(frame))}
  end

  defp handle_oid(frame, configuration, state) do
    case validate_oid(frame.payload_octets, configuration.physical_channel, state) do
      {:ok, next_state} ->
        {:ok, [], [], next_state}

      {:error, reason, next_state} ->
        failed = anomaly(:oid_validation_failed, frame, %{reason: reason})
        {:error, reason, [failed], next_state}
    end
  end

  defp validate_oid(_data, _physical_channel, %{oid_validation: :none} = state),
    do: {:ok, state}

  defp validate_oid(data, physical_channel, state) do
    lfsr =
      Map.get(
        state.oid_lfsr_by_physical_channel,
        physical_channel,
        OnlyIdleData.initial_state()
      )

    result =
      case state.oid_validation do
        :prefix -> OnlyIdleData.validate_prefix(data, state.oid_validation_prefix_octets, lfsr)
        :strict -> OnlyIdleData.validate(data, lfsr)
      end

    case result do
      {:ok, next_lfsr} ->
        {:ok,
         %{
           state
           | oid_lfsr_by_physical_channel:
               Map.put(state.oid_lfsr_by_physical_channel, physical_channel, next_lfsr)
         }}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp auxiliary_sdus(frame, ctx, configuration, continuity) do
    insert_sdu(frame, ctx, configuration, continuity) ++ ocf_sdu(frame, ctx, continuity)
  end

  defp insert_sdu(
         frame,
         ctx,
         %Configuration{insert_zone_length: length} = configuration,
         continuity
       )
       when length > 0 do
    [
      build_sdu(
        frame,
        ctx,
        continuity,
        :insert,
        Map.fetch!(frame.meta, :insert_zone),
        :good,
        [frame.frame_seq],
        %{
          physical_channel: configuration.physical_channel,
          in_sdu_loss_flag: Map.get(ctx, :in_sdu_loss_flag, false)
        }
      )
    ]
  end

  defp insert_sdu(_frame, _ctx, _configuration, _continuity), do: []

  defp ocf_sdu(%LinkFrame{ocf: ocf} = frame, ctx, continuity)
       when is_binary(ocf) and byte_size(ocf) == 4 do
    [
      build_sdu(
        frame,
        ctx,
        continuity,
        :operational_control_field,
        ocf,
        :good,
        [frame.frame_seq],
        %{ocf_sdu_loss_flag: continuity.loss?}
      )
    ]
  end

  defp ocf_sdu(_frame, _ctx, _continuity), do: []

  defp build_sdu(frame, ctx, continuity, kind, octets, quality, source_frames, extra_meta) do
    meta =
      frame.meta
      |> Map.delete(:aos_configuration)
      |> Map.put(:continuity, continuity)
      |> Map.put(:verification_status_code, Map.get(ctx, :verification_status_code))
      |> Map.merge(extra_meta)

    %SDUOctets{
      profile: :aos,
      scid: frame.scid,
      vcid: frame.vcid,
      map_id: nil,
      direction: Map.get(ctx, :direction, :downlink),
      sdu_kind_hint: kind,
      octets: octets,
      quality: quality,
      source_frames: source_frames,
      timestamp: frame.timestamp,
      meta: meta
    }
  end

  defp handle_packet_loss(frame, ctx, configuration, continuity, state) do
    key = channel_key(frame)
    entry = Map.get(state.packet_buffers_by_channel, key)

    if configuration.data_field_content == :m_pdu and continuity.loss? and entry do
      disposition =
        if(configuration.deliver_incomplete_packets?, do: :delivered, else: :discarded)

      partial =
        anomaly(:partial_packet_on_frame_count_discontinuity, frame, %{
          buffered_octets: byte_size(entry.bytes),
          source_frames: entry.source_frames,
          disposition: disposition,
          continuity: continuity
        })

      sdus =
        if disposition == :delivered do
          [
            build_sdu(
              frame,
              ctx,
              continuity,
              :space_packet,
              entry.bytes,
              :partial,
              entry.source_frames,
              %{partial_reason: :frame_count_discontinuity}
            )
          ]
        else
          []
        end

      {sdus, [partial], clear_packet(state, key)}
    else
      {[], [], state}
    end
  end

  defp fetch_configuration(frame, state) do
    physical_channel = Map.get(frame.meta, :physical_channel)

    case physical_channel do
      value when is_binary(value) ->
        fetch_physical_configuration(state.configurations, value, frame.scid, frame.vcid)

      _other ->
        fetch_unique_configuration(state.configurations, frame.scid, frame.vcid)
    end
  end

  defp fetch_physical_configuration(configurations, physical_channel, scid, vcid) do
    case Map.fetch(configurations, {physical_channel, scid, vcid}) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:unknown_aos_channel, physical_channel, scid, vcid}}
    end
  end

  defp fetch_unique_configuration(configurations, scid, vcid) do
    matches =
      configurations
      |> Map.values()
      |> Enum.filter(&Configuration.matches?(&1, scid, vcid))

    case matches do
      [configuration] -> {:ok, configuration}
      [] -> {:error, {:unknown_aos_channel, scid, vcid}}
      _many -> {:error, {:ambiguous_aos_channel, scid, vcid}}
    end
  end

  defp validate_managed_frame(frame, configuration) do
    actual_content = Map.get(frame.meta, :data_field_content)
    expected_octets = Configuration.payload_octets(configuration)

    with true <- Configuration.matches?(configuration, frame.scid, frame.vcid),
         true <- actual_content == configuration.data_field_content,
         true <- byte_size(frame.payload_octets) == expected_octets,
         true <- managed_insert_valid?(frame, configuration),
         true <- managed_ocf_valid?(frame, configuration) do
      :ok
    else
      false ->
        {:error,
         {:managed_aos_frame_mismatch,
          %{content: actual_content, payload_octets: byte_size(frame.payload_octets)}}}
    end
  end

  defp managed_insert_valid?(frame, configuration) do
    insert = Map.get(frame.meta, :insert_zone)

    case configuration.insert_zone_length do
      0 -> insert in [nil, <<>>]
      expected -> is_binary(insert) and byte_size(insert) == expected
    end
  end

  defp managed_ocf_valid?(frame, configuration) do
    case {configuration.ocf?, frame.ocf} do
      {false, nil} -> true
      {false, <<>>} -> true
      {true, ocf} when is_binary(ocf) -> byte_size(ocf) == 4
      _other -> false
    end
  end

  defp normalize_configurations(opts) do
    values =
      case {Keyword.get(opts, :configuration), Keyword.get(opts, :configurations)} do
        {%Configuration{} = configuration, nil} -> [configuration]
        {nil, configurations} when is_list(configurations) -> configurations
        _other -> :invalid
      end

    case values do
      :invalid -> {:error, :invalid_aos_configurations}
      [] -> {:error, :empty_aos_configuration_plan}
      configurations -> index_configurations(configurations)
    end
  end

  defp index_configurations(configurations) do
    with :ok <- Configuration.validate_plan(configurations) do
      {:ok, Map.new(configurations, &{Configuration.physical_address(&1), &1})}
    end
  end

  defp clear_packet(state, key) do
    %{state | packet_buffers_by_channel: Map.delete(state.packet_buffers_by_channel, key)}
  end

  defp channel_key(frame) do
    replay = Map.get(frame.meta, :replay_flag, 0)
    {Map.get(frame.meta, :physical_channel, "default"), 0, frame.scid, frame.vcid, replay}
  end

  defp anomaly(kind, frame, metadata) do
    %{
      anomaly_kind: kind,
      scid: frame.scid,
      vcid: frame.vcid,
      frame_seq: frame.frame_seq,
      metadata: metadata
    }
  end

  defp normalize_oid_validation(value) when value in [:none, :prefix, :strict], do: {:ok, value}
  defp normalize_oid_validation(value), do: {:error, {:invalid_oid_validation, value}}

  defp normalize_prefix_octets(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp normalize_prefix_octets(value), do: {:error, {:invalid_oid_prefix_octets, value}}
  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)
end
