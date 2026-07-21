defmodule Cadence.CCSDS.SDLP.AOS.Segmentation do
  @moduledoc """
  Pure sending-end AOS Virtual Channel generation.

  The module constructs fixed-length M_PDUs, B_PDUs, VCA_SDUs, and OID data
  fields. VC frame counters are independent by GVCID, optionally extend to 28
  bits with the Frame Count Cycle, and are not maintained for OID frames.
  Insert and OCF SDUs are supplied by the caller because their synchronous
  release and multiplexing policy is outside the protocol kernel.
  """

  @behaviour Cadence.CCSDS.SDLP.Segmentation

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}
  alias Cadence.CCSDS.SDLP.AOS.{BPDU, Configuration, FrameCodec, MPDU, OnlyIdleData}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Idle
  alias Cadence.CCSDS.SpacePacket.Stream

  @min_idle_packet_octets 7
  @maximum_vcfc 0xFFFFFF
  @maximum_cycle 0x0F

  @impl true
  def init(opts) when is_list(opts) do
    initial_vcfc = Keyword.get(opts, :vcfc, 0)
    initial_cycle = Keyword.get(opts, :vc_frame_count_cycle, 0)
    cycle_use? = Keyword.get(opts, :vc_frame_count_cycle_use, false)

    with :ok <- validate_range(initial_vcfc, 0, @maximum_vcfc, :vcfc),
         :ok <- validate_range(initial_cycle, 0, @maximum_cycle, :vc_frame_count_cycle),
         :ok <- validate_boolean(cycle_use?, :vc_frame_count_cycle_use),
         :ok <- validate_initial_cycle(initial_cycle, cycle_use?) do
      {:ok,
       %{
         initial_vcfc: initial_vcfc,
         initial_cycle: initial_cycle,
         cycle_use?: cycle_use?,
         counters_by_virtual_channel: %{},
         oid_lfsr_by_physical_channel: %{},
         idle_packet_cache: %{}
       }}
    end
  end

  @impl true
  def segment(%SDUOctets{profile: :aos} = sdu, ctx, state)
      when is_map(ctx) and is_map(state) do
    with {:ok, configuration} <- configuration(ctx),
         :ok <- validate_sdu_address(sdu, configuration),
         :ok <- validate_sdu_kind(sdu, configuration) do
      segment_content(sdu, configuration, Map.put_new(ctx, :timestamp, sdu.timestamp), state)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def segment(%SDUOctets{profile: profile}, _ctx, state),
    do: {:error, {:invalid_profile, profile}, state}

  def segment(_sdu, _ctx, state), do: {:error, :invalid_sdu, state}

  @spec segment_encode(SDUOctets.t(), map(), map(), keyword()) ::
          {:ok, binary(), map()} | {:error, term(), map()}
  def segment_encode(%SDUOctets{profile: :aos} = sdu, ctx, state, opts \\ [])
      when is_map(ctx) and is_map(state) and is_list(opts) do
    with {:ok, frames, next_state} <- segment(sdu, ctx, state),
         {:ok, configuration} <- configuration(ctx),
         {:ok, encoded} <- encode_frames(frames, configuration, opts) do
      {:ok, encoded, next_state}
    else
      {:error, reason, _next_state} -> {:error, reason, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @doc """
  Generates an OID frame for the managed reserved VCID 63 channel.
  """
  @spec only_idle(map(), map()) :: {:ok, LinkFrame.t(), map()} | {:error, term(), map()}
  def only_idle(ctx, state) when is_map(ctx) and is_map(state) do
    with {:ok, configuration} <- configuration(ctx),
         :ok <- require_content(configuration, :idle_data),
         {:ok, insert_zone} <-
           synchronous_field(ctx, :insert_zone, 0, configuration.insert_zone_length),
         {payload, next_lfsr} <- oid_payload(configuration, state),
         frame <-
           link_frame(payload, configuration, 0, 0, 0, insert_zone, nil, %{
             oid?: true,
             physical_channel: configuration.physical_channel,
             vcfc: 0,
             replay_flag: 0,
             vc_frame_count_cycle_use_flag: 0,
             vc_frame_count_cycle: 0,
             insert_zone: insert_zone,
             data_field_content: :idle_data
           }) do
      key = configuration.physical_channel

      next_state = %{
        state
        | oid_lfsr_by_physical_channel:
            Map.put(state.oid_lfsr_by_physical_channel, key, next_lfsr)
      }

      {:ok, frame, next_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @doc """
  Generates one idle M_PDU using a caller-selected fixed idle octet.
  """
  @spec idle_mpdu(map(), map()) :: {:ok, LinkFrame.t(), map()} | {:error, term(), map()}
  def idle_mpdu(ctx, state) when is_map(ctx) and is_map(state) do
    with {:ok, configuration} <- configuration(ctx),
         :ok <- require_content(configuration, :m_pdu),
         {:ok, idle_octet} <- idle_octet(ctx),
         payload = :binary.copy(<<idle_octet>>, Configuration.payload_octets(configuration)),
         {:ok, frame, next_state} <-
           build_frame(payload, configuration, ctx, state, 0, %{
             first_header_pointer: MPDU.only_idle_data(),
             idle_mpdu?: true
           }) do
      {:ok, frame, next_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @doc """
  Generates one idle B_PDU using a caller-selected fixed idle octet.
  """
  @spec idle_bpdu(map(), map()) :: {:ok, LinkFrame.t(), map()} | {:error, term(), map()}
  def idle_bpdu(ctx, state) when is_map(ctx) and is_map(state) do
    with {:ok, configuration} <- configuration(ctx),
         :ok <- require_content(configuration, :b_pdu),
         {:ok, idle_octet} <- idle_octet(ctx),
         payload = :binary.copy(<<idle_octet>>, Configuration.payload_octets(configuration)),
         {:ok, frame, next_state} <-
           build_frame(payload, configuration, ctx, state, 0, %{
             bitstream_data_pointer: BPDU.only_idle_data(),
             valid_bits: 0,
             idle_bpdu?: true
           }) do
      {:ok, frame, next_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp segment_content(
         sdu,
         %Configuration{data_field_content: :m_pdu} = configuration,
         ctx,
         state
       ) do
    with {:ok, offsets} <- validate_packet_stream(sdu.octets, configuration),
         {:ok, stream, starts, padded_state} <-
           complete_packet_stream(sdu.octets, offsets, configuration, state),
         {:ok, frames, next_state} <-
           packet_frames(stream, starts, configuration, ctx, padded_state) do
      {:ok, frames, next_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp segment_content(
         sdu,
         %Configuration{data_field_content: :b_pdu} = configuration,
         ctx,
         state
       ) do
    with {:ok, valid_bits} <- valid_bit_count(sdu),
         {:ok, frames, next_state} <-
           bitstream_frames(sdu.octets, valid_bits, configuration, ctx, state) do
      {:ok, frames, next_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp segment_content(
         sdu,
         %Configuration{data_field_content: :vca_sdu} = configuration,
         ctx,
         state
       ) do
    expected = Configuration.payload_octets(configuration)

    if byte_size(sdu.octets) == expected do
      case build_frame(sdu.octets, configuration, ctx, state, 0, %{}) do
        {:ok, frame, next_state} -> {:ok, [frame], next_state}
        {:error, reason} -> {:error, reason, state}
      end
    else
      {:error, {:vca_sdu_length_mismatch, byte_size(sdu.octets), expected}, state}
    end
  end

  defp packet_frames(stream, starts, configuration, ctx, state) do
    zone_octets = Configuration.payload_octets(configuration)
    chunks = for <<chunk::binary-size(^zone_octets) <- stream>>, do: chunk

    chunks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], state}, fn {payload, index}, {:ok, frames, current_state} ->
      zone_start = index * zone_octets
      pointer = first_header_pointer(starts, zone_start, zone_octets)

      case build_frame(payload, configuration, ctx, current_state, index, %{
             first_header_pointer: pointer
           }) do
        {:ok, frame, next_state} -> {:cont, {:ok, [frame | frames], next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_frames()
  end

  defp bitstream_frames(data, valid_bits, configuration, ctx, state) do
    zone_bits = Configuration.payload_octets(configuration) * 8
    <<valid_data::bitstring-size(^valid_bits), _unused::bitstring>> = data
    frame_count = ceil_div(valid_bits, zone_bits)

    0..(frame_count - 1)
    |> Enum.reduce_while({:ok, [], state}, fn index, {:ok, frames, current_state} ->
      offset = index * zone_bits
      count = min(zone_bits, valid_bits - offset)

      <<_prefix::bitstring-size(^offset), chunk::bitstring-size(^count), _rest::bitstring>> =
        valid_data

      padding = zone_bits - count
      payload = <<chunk::bitstring, 0::size(padding)>>
      pointer = if(count == zone_bits, do: BPDU.all_valid(), else: count - 1)

      case build_frame(payload, configuration, ctx, current_state, index, %{
             bitstream_data_pointer: pointer,
             valid_bits: count
           }) do
        {:ok, frame, next_state} -> {:cont, {:ok, [frame | frames], next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_frames()
  end

  defp build_frame(payload, configuration, ctx, state, index, content_meta) do
    with {:ok, insert_zone} <-
           synchronous_field(ctx, :insert_zone, index, configuration.insert_zone_length),
         {:ok, ocf} <- synchronous_field(ctx, :ocf, index, if(configuration.ocf?, do: 4, else: 0)) do
      {vcfc, cycle} = current_counter(configuration, state)
      replay_flag = Map.get(ctx, :replay_flag, 0)

      with :ok <- validate_bit(replay_flag, :replay_flag) do
        meta =
          %{
            vcfc: vcfc,
            replay_flag: replay_flag,
            vc_frame_count_cycle_use_flag: if(state.cycle_use?, do: 1, else: 0),
            vc_frame_count_cycle: if(state.cycle_use?, do: cycle, else: 0),
            physical_channel: configuration.physical_channel,
            insert_zone: insert_zone,
            timestamp: Map.get(ctx, :timestamp),
            data_field_content: configuration.data_field_content
          }
          |> Map.merge(content_meta)

        frame =
          link_frame(
            payload,
            configuration,
            vcfc,
            replay_flag,
            cycle,
            insert_zone,
            ocf,
            meta
          )

        {:ok, frame, increment_counter(configuration, state, vcfc, cycle)}
      end
    end
  end

  defp link_frame(payload, configuration, vcfc, _replay_flag, _cycle, _insert, ocf, meta) do
    %LinkFrame{
      profile: :aos,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: nil,
      frame_seq: vcfc,
      payload_octets: payload,
      quality: :good,
      ocf: ocf,
      timestamp: Map.get(meta, :timestamp),
      meta: meta
    }
  end

  defp validate_packet_stream(<<>>, _configuration), do: {:error, :empty_packet_stream}

  defp validate_packet_stream(packet_stream, configuration) do
    with {:ok, packets, <<>>} <-
           Stream.extract(packet_stream, max_packet_size: configuration.maximum_packet_octets),
         :ok <- validate_packet_versions(packets, configuration.valid_packet_version_numbers) do
      {:ok, cumulative_offsets(packets)}
    else
      {:ok, _packets, rest} -> {:error, {:incomplete_packet_stream, byte_size(rest)}}
      {:error, reason} -> {:error, {:invalid_packet_stream, reason}}
    end
  end

  defp validate_packet_versions(packets, valid_versions) do
    invalid =
      Enum.find_value(packets, fn
        <<version::3, _rest::bitstring>> -> if(version in valid_versions, do: nil, else: version)
        _packet -> :invalid
      end)

    if is_nil(invalid), do: :ok, else: {:error, {:invalid_packet_version_number, invalid}}
  end

  defp cumulative_offsets(packets) do
    packets
    |> Enum.reduce({[], 0}, fn packet, {offsets, offset} ->
      {[offset | offsets], offset + byte_size(packet)}
    end)
    |> then(fn {offsets, _size} -> Enum.reverse(offsets) end)
  end

  defp complete_packet_stream(packet_stream, offsets, configuration, state) do
    zone_octets = Configuration.payload_octets(configuration)
    padding = Integer.mod(-byte_size(packet_stream), zone_octets)

    cond do
      padding == 0 ->
        {:ok, packet_stream, offsets, state}

      padding >= @min_idle_packet_octets ->
        {idle_packet, next_state} = idle_packet(padding, state)
        {:ok, packet_stream <> idle_packet, offsets ++ [byte_size(packet_stream)], next_state}

      spill_idle_size(padding, zone_octets) <= SpacePacket.maximum_size() ->
        idle_size = spill_idle_size(padding, zone_octets)
        {idle_packet, next_state} = idle_packet(idle_size, state)
        {:ok, packet_stream <> idle_packet, offsets ++ [byte_size(packet_stream)], next_state}

      true ->
        {:error, {:idle_packet_spill_exceeds_maximum, zone_octets, padding}}
    end
  end

  defp idle_packet(size, state) do
    case Map.fetch(state.idle_packet_cache, size) do
      {:ok, packet} ->
        {packet, state}

      :error ->
        packet = Idle.encode!(size)
        {packet, %{state | idle_packet_cache: Map.put(state.idle_packet_cache, size, packet)}}
    end
  end

  defp first_header_pointer(offsets, zone_start, zone_octets) do
    zone_end = zone_start + zone_octets

    case Enum.find(offsets, &(&1 >= zone_start and &1 < zone_end)) do
      nil -> MPDU.no_packet_starts()
      packet_start -> packet_start - zone_start
    end
  end

  defp current_counter(configuration, state) do
    Map.get(
      state.counters_by_virtual_channel,
      channel_key(configuration),
      {state.initial_vcfc, state.initial_cycle}
    )
  end

  defp increment_counter(configuration, state, vcfc, cycle) do
    {next_vcfc, next_cycle} =
      if vcfc == @maximum_vcfc do
        {0, if(state.cycle_use?, do: Integer.mod(cycle + 1, @maximum_cycle + 1), else: 0)}
      else
        {vcfc + 1, cycle}
      end

    %{
      state
      | counters_by_virtual_channel:
          Map.put(
            state.counters_by_virtual_channel,
            channel_key(configuration),
            {next_vcfc, next_cycle}
          )
    }
  end

  defp synchronous_field(ctx, field, index, expected_octets) do
    values = Map.get(ctx, plural_field(field))
    value = if(is_list(values), do: Enum.at(values, index), else: Map.get(ctx, field))
    validate_synchronous_field(field, index, expected_octets, value)
  end

  defp validate_synchronous_field(_field, _index, 0, value) when value in [nil, <<>>],
    do: {:ok, nil}

  defp validate_synchronous_field(field, _index, 0, value),
    do: {:error, {:unexpected_synchronous_sdu, field, value}}

  defp validate_synchronous_field(_field, _index, expected, value)
       when is_binary(value) and byte_size(value) == expected,
       do: {:ok, value}

  defp validate_synchronous_field(field, _index, expected, value) when is_binary(value),
    do: {:error, {:synchronous_sdu_length_mismatch, field, byte_size(value), expected}}

  defp validate_synchronous_field(field, index, expected, nil),
    do: {:error, {:missing_synchronous_sdu, field, index, expected}}

  defp validate_synchronous_field(field, _index, expected, value),
    do: {:error, {:invalid_synchronous_sdu, field, value, expected}}

  defp plural_field(:insert_zone), do: :insert_zone_sdus
  defp plural_field(:ocf), do: :ocf_sdus

  defp configuration(%{configuration: %Configuration{} = configuration}) do
    case Configuration.validate(configuration) do
      :ok -> {:ok, configuration}
      {:error, _reason} = error -> error
    end
  end

  defp configuration(ctx),
    do: {:error, {:invalid_aos_configuration, Map.get(ctx, :configuration)}}

  defp validate_sdu_address(sdu, configuration) do
    if (is_nil(sdu.scid) or sdu.scid == configuration.scid) and
         (is_nil(sdu.vcid) or sdu.vcid == configuration.vcid) do
      :ok
    else
      {:error, {:managed_channel_mismatch, sdu.scid, sdu.vcid}}
    end
  end

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %Configuration{
         data_field_content: :m_pdu
       })
       when hint in [:space_packet, :virtual_channel_packet],
       do: :ok

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %Configuration{
         data_field_content: :b_pdu
       })
       when hint in [:bitstream, :bitstream_data],
       do: :ok

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %Configuration{
         data_field_content: :vca_sdu
       })
       when hint in [:vca_sdu, :virtual_channel_access],
       do: :ok

  defp validate_sdu_kind(sdu, configuration),
    do: {:error, {:sdu_kind_mismatch, sdu.sdu_kind_hint, configuration.data_field_content}}

  defp valid_bit_count(%SDUOctets{octets: data, meta: meta}) when is_binary(data) do
    value = Map.get(meta || %{}, :valid_bits, bit_size(data))

    if is_integer(value) and value > 0 and value <= bit_size(data),
      do: {:ok, value},
      else: {:error, {:invalid_bitstream_length, value, bit_size(data)}}
  end

  defp require_content(%Configuration{data_field_content: expected}, expected), do: :ok

  defp require_content(configuration, expected),
    do: {:error, {:service_configuration_mismatch, expected, configuration.data_field_content}}

  defp oid_payload(configuration, state) do
    key = configuration.physical_channel
    lfsr = Map.get(state.oid_lfsr_by_physical_channel, key, OnlyIdleData.initial_state())
    OnlyIdleData.take(Configuration.payload_octets(configuration), lfsr)
  end

  defp idle_octet(ctx) do
    value = Map.get(ctx, :idle_octet, 0)

    if is_integer(value) and value in 0..255,
      do: {:ok, value},
      else: {:error, {:invalid_idle_octet, value}}
  end

  defp encode_frames(frames, configuration, opts) do
    Enum.reduce_while(frames, {:ok, []}, fn frame, {:ok, encoded} ->
      case FrameCodec.encode(frame, Keyword.put(opts, :configuration, configuration)) do
        {:ok, bytes} -> {:cont, {:ok, [bytes | encoded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, encoded |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _reason} = error -> error
    end
  end

  defp reverse_frames({:ok, frames, state}), do: {:ok, Enum.reverse(frames), state}
  defp reverse_frames({:error, _reason} = error), do: error

  defp spill_idle_size(padding, zone_octets) do
    padding + ceil_div(@min_idle_packet_octets - padding, zone_octets) * zone_octets
  end

  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)

  defp channel_key(configuration),
    do: {configuration.physical_channel, 0, configuration.scid, configuration.vcid}

  defp validate_initial_cycle(0, false), do: :ok
  defp validate_initial_cycle(_cycle, true), do: :ok

  defp validate_initial_cycle(cycle, false),
    do: {:error, {:unused_aos_frame_count_cycle_not_zero, cycle}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}
  defp validate_bit(value, _field) when value in [0, 1], do: :ok
  defp validate_bit(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}
end
