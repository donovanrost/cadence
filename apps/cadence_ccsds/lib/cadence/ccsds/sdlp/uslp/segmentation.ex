defmodule Cadence.CCSDS.SDLP.USLP.Segmentation do
  @moduledoc """
  Pure sending-end USLP MAP and Virtual Channel generation.

  Variable-length Packet, MAPA and VCA SDUs use the standard start,
  continuation, last and unsegmented construction rules. Fixed-length Packet
  data zones are filled with standards-shaped Idle Packets and carry an FHP;
  fixed-length access SDUs carry an LVO and project-selected idle pattern.
  Sequence-Controlled and Expedited counters advance independently per VC.
  """

  @behaviour Cadence.CCSDS.SDLP.Segmentation

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}
  alias Cadence.CCSDS.SDLP.USLP.{Configuration, FrameCodec, OnlyIdleData, TFDF}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Idle
  alias Cadence.CCSDS.TC.Service.{PacketConfiguration, PacketFormat}

  @minimum_idle_packet_octets 7

  @impl true
  def init(opts \\ []) when is_list(opts) do
    sequence_count = Keyword.get(opts, :sequence_count, 0)
    expedited_count = Keyword.get(opts, :expedited_count, 0)

    with :ok <- validate_non_negative(sequence_count, :sequence_count),
         :ok <- validate_non_negative(expedited_count, :expedited_count) do
      {:ok,
       %{
         initial_counts: %{
           sequence_controlled: sequence_count,
           expedited: expedited_count
         },
         counters: %{},
         idle_packet_cache: %{},
         oid_lfsr_by_physical_channel: %{}
       }}
    end
  end

  @impl true
  def segment(%SDUOctets{profile: :uslp} = sdu, ctx, state)
      when is_map(ctx) and is_map(state) do
    with {:ok, configuration} <- configuration(ctx),
         :ok <- validate_sdu_address(sdu, configuration),
         :ok <- validate_sdu_kind(sdu, configuration),
         {:ok, qos} <- qos(ctx, configuration) do
      segment_content(
        sdu,
        configuration,
        qos,
        Map.put_new(ctx, :timestamp, sdu.timestamp),
        state
      )
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def segment(%SDUOctets{profile: profile}, _ctx, state),
    do: {:error, {:invalid_profile, profile}, state}

  def segment(_sdu, _ctx, state), do: {:error, :invalid_sdu, state}

  @spec segment_encode(SDUOctets.t(), map(), map(), keyword()) ::
          {:ok, binary(), map()} | {:error, term(), map()}
  def segment_encode(%SDUOctets{profile: :uslp} = sdu, ctx, state, opts \\ []) do
    with {:ok, frames, next_state} <- segment(sdu, ctx, state),
         {:ok, configuration} <- configuration(ctx),
         {:ok, encoded} <- encode_frames(frames, configuration, opts) do
      {:ok, IO.iodata_to_binary(encoded), next_state}
    else
      {:error, reason, _next_state} -> {:error, reason, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @spec only_idle(map(), map()) :: {:ok, LinkFrame.t(), map()} | {:error, term(), map()}
  def only_idle(ctx, state) when is_map(ctx) and is_map(state) do
    with {:ok, configuration} <- configuration(ctx),
         true <- configuration.data_field_content == :idle_data,
         {:ok, insert_zone} <-
           synchronous_field(ctx, :insert_zone, 0, configuration.insert_zone_length),
         {:ok, count, state} <- take_counter(configuration, :sequence_controlled, state),
         length <- Configuration.maximum_tfdz_octets(configuration, :sequence_controlled),
         lfsr <-
           Map.get(
             state.oid_lfsr_by_physical_channel,
             configuration.physical_channel,
             OnlyIdleData.initial_state()
           ),
         {payload, next_lfsr} <- OnlyIdleData.take(length, lfsr),
         frame <-
           link_frame(payload, configuration, count, :sequence_controlled, nil, insert_zone, %{
             construction_rule: :start_access_sdu,
             tfdf_pointer: length - 1,
             upid: TFDF.upid(:only_idle),
             oid?: true
           }) do
      next_state = %{
        state
        | oid_lfsr_by_physical_channel:
            Map.put(
              state.oid_lfsr_by_physical_channel,
              configuration.physical_channel,
              next_lfsr
            )
      }

      {:ok, frame, next_state}
    else
      false -> {:error, :uslp_only_idle_service_not_configured, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp segment_content(sdu, configuration, qos, ctx, state) do
    cond do
      Map.get(ctx, :truncated?, false) -> segment_truncated(sdu, configuration, qos, ctx, state)
      configuration.frame_type == :fixed -> segment_fixed(sdu, configuration, qos, ctx, state)
      true -> segment_variable(sdu, configuration, qos, ctx, state)
    end
  end

  defp segment_truncated(sdu, configuration, :expedited, ctx, state) do
    expected = configuration.truncated_frame_length

    cond do
      not is_integer(expected) ->
        {:error, :truncated_uslp_not_configured, state}

      configuration.data_field_content != :mapa_sdu ->
        {:error, :truncated_uslp_requires_mapa_sdu, state}

      byte_size(sdu.octets) != expected - 5 ->
        {:error, {:truncated_uslp_sdu_length_mismatch, byte_size(sdu.octets), expected - 5},
         state}

      true ->
        frame =
          link_frame(sdu.octets, configuration, nil, :expedited, nil, nil, %{
            truncated?: true,
            construction_rule: :unsegmented,
            upid: TFDF.upid(:mission_specific),
            timestamp: Map.get(ctx, :timestamp)
          })

        {:ok, [frame], state}
    end
  end

  defp segment_truncated(_sdu, _configuration, qos, _ctx, state),
    do: {:error, {:truncated_uslp_requires_expedited_qos, qos}, state}

  defp segment_fixed(
         sdu,
         %Configuration{data_field_content: :packets} = configuration,
         qos,
         ctx,
         state
       ) do
    with {:ok, pvn} <- PacketFormat.packet_version_number(sdu.octets),
         :ok <-
           PacketConfiguration.validate_packet(
             sdu.octets,
             pvn,
             configuration.packet_configuration
           ),
         {:ok, stream, starts, state} <-
           fixed_packet_stream(sdu.octets, configuration, qos, state),
         {:ok, frames, next_state} <-
           fixed_packet_frames(stream, starts, configuration, qos, ctx, state) do
      {:ok, frames, next_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp segment_fixed(sdu, configuration, qos, ctx, state)
       when configuration.data_field_content in [:mapa_sdu, :vca_sdu] do
    zone_octets = Configuration.maximum_tfdz_octets(configuration, qos)
    chunks = chunk_binary(sdu.octets, zone_octets)

    chunks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], state}, fn {chunk, index}, {:ok, frames, current_state} ->
      last? = index == length(chunks) - 1
      valid_octets = byte_size(chunk)
      payload = pad(chunk, zone_octets, Map.get(ctx, :idle_pattern, <<0>>))
      rule = if(index == 0, do: :start_access_sdu, else: :continue_access_sdu)
      pointer = if(last?, do: valid_octets - 1, else: 0xFFFF)

      case build_frame(payload, configuration, qos, ctx, current_state, index, %{
             construction_rule: rule,
             tfdf_pointer: pointer
           }) do
        {:ok, frame, next_state} -> {:cont, {:ok, [frame | frames], next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_frames(state)
  end

  defp segment_fixed(_sdu, configuration, _qos, _ctx, state),
    do: {:error, {:fixed_uslp_content_not_supported, configuration.data_field_content}, state}

  defp segment_variable(sdu, configuration, qos, ctx, state) do
    with :ok <- validate_non_empty_binary(sdu.octets, :sdu),
         :ok <- validate_variable_sdu(sdu, configuration) do
      zone_octets = Configuration.maximum_tfdz_octets(configuration, qos)

      if configuration.data_field_content == :octet_stream do
        octet_stream_frames(sdu.octets, zone_octets, configuration, qos, ctx, state)
      else
        variable_sdu_frames(sdu.octets, zone_octets, configuration, qos, ctx, state)
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp variable_sdu_frames(data, zone_octets, configuration, qos, ctx, state) do
    chunks = chunk_binary(data, zone_octets)

    chunks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], state}, fn {payload, index}, {:ok, frames, current_state} ->
      rule = variable_rule(index, length(chunks))

      case build_frame(payload, configuration, qos, ctx, current_state, index, %{
             construction_rule: rule
           }) do
        {:ok, frame, next_state} -> {:cont, {:ok, [frame | frames], next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_frames(state)
  end

  defp octet_stream_frames(data, zone_octets, configuration, qos, ctx, state) do
    data
    |> chunk_binary(zone_octets)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], state}, fn {payload, index}, {:ok, frames, current_state} ->
      case build_frame(payload, configuration, qos, ctx, current_state, index, %{
             construction_rule: :octet_stream
           }) do
        {:ok, frame, next_state} -> {:cont, {:ok, [frame | frames], next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_frames(state)
  end

  defp fixed_packet_stream(packet, configuration, qos, state) do
    zone_octets = Configuration.maximum_tfdz_octets(configuration, qos)
    padding = Integer.mod(-byte_size(packet), zone_octets)

    cond do
      padding == 0 ->
        {:ok, packet, [0], state}

      padding >= @minimum_idle_packet_octets ->
        {idle, next_state} = idle_packet(padding, state)
        {:ok, packet <> idle, [0, byte_size(packet)], next_state}

      spill_idle_size(padding, zone_octets) <= SpacePacket.maximum_size() ->
        size = spill_idle_size(padding, zone_octets)
        {idle, next_state} = idle_packet(size, state)
        {:ok, packet <> idle, [0, byte_size(packet)], next_state}

      true ->
        {:error, {:idle_packet_spill_exceeds_maximum, zone_octets, padding}}
    end
  end

  defp fixed_packet_frames(stream, starts, configuration, qos, ctx, state) do
    zone_octets = Configuration.maximum_tfdz_octets(configuration, qos)
    chunks = for <<chunk::binary-size(^zone_octets) <- stream>>, do: chunk

    chunks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], state}, fn {payload, index}, {:ok, frames, current_state} ->
      zone_start = index * zone_octets
      pointer = first_header_pointer(starts, zone_start, zone_octets)

      case build_frame(payload, configuration, qos, ctx, current_state, index, %{
             construction_rule: :packets_spanning_frames,
             tfdf_pointer: pointer
           }) do
        {:ok, frame, next_state} -> {:cont, {:ok, [frame | frames], next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_frames(state)
  end

  defp build_frame(payload, configuration, qos, ctx, state, index, content_meta) do
    with {:ok, insert_zone} <-
           synchronous_field(ctx, :insert_zone, index, configuration.insert_zone_length),
         {:ok, ocf} <- synchronous_field(ctx, :ocf, index, if(configuration.ocf?, do: 4, else: 0)),
         {:ok, count, next_state} <- take_counter(configuration, qos, state) do
      meta =
        %{
          physical_channel: configuration.physical_channel,
          qos: qos,
          protocol_control?: configuration.data_field_content == :protocol_control,
          vcf_count: count,
          vcf_count_length: Configuration.count_octets(configuration, qos),
          insert_zone: insert_zone,
          upid: configuration.upid,
          timestamp: Map.get(ctx, :timestamp)
        }
        |> Map.merge(content_meta)

      {:ok, link_frame(payload, configuration, count, qos, ocf, insert_zone, meta), next_state}
    end
  end

  defp link_frame(payload, configuration, count, qos, ocf, insert_zone, meta) do
    %LinkFrame{
      profile: :uslp,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: configuration.map_id,
      frame_seq: count,
      payload_octets: payload,
      quality: :good,
      ocf: ocf,
      timestamp: Map.get(meta, :timestamp),
      meta:
        meta
        |> Map.put_new(:qos, qos)
        |> Map.put_new(:insert_zone, insert_zone)
        |> Map.put(:uslp_configuration, configuration)
    }
  end

  defp take_counter(configuration, qos, state) do
    octets = Configuration.count_octets(configuration, qos)

    if octets == 0 do
      {:ok, nil, state}
    else
      key = {configuration.physical_channel, configuration.scid, configuration.vcid, qos}
      initial = Map.fetch!(state.initial_counts, qos)
      count = Integer.mod(Map.get(state.counters, key, initial), Integer.pow(256, octets))
      next = Integer.mod(count + 1, Integer.pow(256, octets))
      {:ok, count, %{state | counters: Map.put(state.counters, key, next)}}
    end
  end

  defp validate_variable_sdu(sdu, %Configuration{data_field_content: :packets} = configuration) do
    with {:ok, pvn} <- PacketFormat.packet_version_number(sdu.octets) do
      PacketConfiguration.validate_packet(sdu.octets, pvn, configuration.packet_configuration)
    end
  end

  defp validate_variable_sdu(_sdu, _configuration), do: :ok

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %Configuration{
         data_field_content: :packets
       })
       when hint in [:packet, :space_packet, :map_packet, :virtual_channel_packet],
       do: :ok

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %Configuration{
         data_field_content: :mapa_sdu
       })
       when hint in [:mapa_sdu, :map_access],
       do: :ok

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %Configuration{
         data_field_content: :vca_sdu
       })
       when hint in [:vca_sdu, :virtual_channel_access],
       do: :ok

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %Configuration{
         data_field_content: :octet_stream
       })
       when hint in [:octet_stream, :octet_stream_data],
       do: :ok

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %Configuration{
         data_field_content: :protocol_control
       })
       when hint in [:protocol_control, :cop_control_command],
       do: :ok

  defp validate_sdu_kind(sdu, configuration),
    do: {:error, {:sdu_kind_mismatch, sdu.sdu_kind_hint, configuration.data_field_content}}

  defp validate_sdu_address(sdu, configuration) do
    if (is_nil(sdu.scid) or sdu.scid == configuration.scid) and
         (is_nil(sdu.vcid) or sdu.vcid == configuration.vcid) and
         (is_nil(sdu.map_id) or sdu.map_id == configuration.map_id),
       do: :ok,
       else: {:error, {:managed_channel_mismatch, sdu.scid, sdu.vcid, sdu.map_id}}
  end

  defp qos(ctx, %Configuration{data_field_content: :protocol_control}) do
    case Map.get(ctx, :qos, :expedited) do
      :expedited -> {:ok, :expedited}
      value -> {:error, {:protocol_control_requires_expedited_qos, value}}
    end
  end

  defp qos(ctx, _configuration) do
    case Map.get(ctx, :qos, :sequence_controlled) do
      value when value in [:sequence_controlled, :expedited] -> {:ok, value}
      value -> {:error, {:invalid_uslp_qos, value}}
    end
  end

  defp variable_rule(_index, 1), do: :unsegmented
  defp variable_rule(0, _count), do: :start_segment
  defp variable_rule(index, count) when index == count - 1, do: :last_segment
  defp variable_rule(_index, _count), do: :continue_segment

  defp first_header_pointer(starts, zone_start, zone_octets) do
    case Enum.find(starts, &(&1 >= zone_start and &1 < zone_start + zone_octets)) do
      nil -> 0xFFFF
      packet_start -> packet_start - zone_start
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

  defp synchronous_field(ctx, field, index, expected_octets) do
    values = Map.get(ctx, plural_field(field))
    value = if(is_list(values), do: Enum.at(values, index), else: Map.get(ctx, field))
    validate_synchronous_field(value, field, index, expected_octets)
  end

  defp validate_synchronous_field(value, _field, _index, 0) when value in [nil, <<>>],
    do: {:ok, nil}

  defp validate_synchronous_field(value, field, _index, 0),
    do: {:error, {:unexpected_synchronous_sdu, field, value}}

  defp validate_synchronous_field(value, _field, _index, expected)
       when is_binary(value) and byte_size(value) == expected,
       do: {:ok, value}

  defp validate_synchronous_field(value, field, _index, expected) when is_binary(value),
    do: {:error, {:synchronous_sdu_length_mismatch, field, byte_size(value), expected}}

  defp validate_synchronous_field(nil, field, index, expected),
    do: {:error, {:missing_synchronous_sdu, field, index, expected}}

  defp validate_synchronous_field(value, field, _index, expected),
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
    do: {:error, {:invalid_uslp_configuration, Map.get(ctx, :configuration)}}

  defp encode_frames(frames, configuration, opts) do
    Enum.reduce_while(frames, {:ok, []}, fn frame, {:ok, encoded} ->
      case FrameCodec.encode(frame, Keyword.put(opts, :configuration, configuration)) do
        {:ok, bytes} -> {:cont, {:ok, [encoded, bytes]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reverse_frames({:ok, frames, next_state}, _original_state),
    do: {:ok, Enum.reverse(frames), next_state}

  defp reverse_frames({:error, reason}, original_state), do: {:error, reason, original_state}

  defp chunk_binary(data, size), do: do_chunk_binary(data, size, [])
  defp do_chunk_binary(<<>>, _size, acc), do: Enum.reverse(acc)

  defp do_chunk_binary(data, size, acc) when byte_size(data) <= size,
    do: Enum.reverse([data | acc])

  defp do_chunk_binary(data, size, acc) do
    <<chunk::binary-size(^size), rest::binary>> = data
    do_chunk_binary(rest, size, [chunk | acc])
  end

  defp pad(data, size, pattern) when is_binary(pattern) and byte_size(pattern) > 0 do
    missing = size - byte_size(data)
    repetitions = div(missing + byte_size(pattern) - 1, byte_size(pattern))
    data <> (pattern |> :binary.copy(repetitions) |> binary_part(0, missing))
  end

  defp spill_idle_size(padding, zone_octets) do
    padding + ceil_div(@minimum_idle_packet_octets - padding, zone_octets) * zone_octets
  end

  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)

  defp validate_non_empty_binary(value, _field) when is_binary(value) and byte_size(value) > 0,
    do: :ok

  defp validate_non_empty_binary(value, field), do: {:error, {:invalid_field, field, value}}
  defp validate_non_negative(value, _field) when is_integer(value) and value >= 0, do: :ok
  defp validate_non_negative(value, field), do: {:error, {:invalid_field, field, value}}
end
