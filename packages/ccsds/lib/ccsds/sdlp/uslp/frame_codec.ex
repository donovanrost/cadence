defmodule CCSDS.SDLP.USLP.FrameCodec do
  @moduledoc """
  CCSDS 732.1-B-3 Unified Space Data Link Protocol frame codec.

  The codec implements Version-4 fixed- and variable-length frames, separate
  Sequence-Controlled and Expedited counter widths from zero through seven
  octets, Insert Zone, OCF, FECF, all eight TFDZ construction rules, and the
  normative four-octet truncated primary header. Managed decoding can route a
  mixed variable-length physical-channel stream by SCID, VCID and MAP ID.
  """

  @behaviour CCSDS.SDLP.FrameCodec

  import Bitwise

  alias CCSDS.Core.LinkFrame
  alias CCSDS.FrameErrorControl
  alias CCSDS.SDLP.USLP.{Configuration, TFDF}

  @version 0b1100
  @ocf_octets 4

  @impl true
  def profile, do: :uslp

  @impl true
  def encode(%LinkFrame{profile: :uslp} = frame, opts) when is_list(opts) do
    with {:ok, configuration} <- configuration(opts),
         :ok <- validate_address(frame, configuration) do
      if Map.get(frame.meta, :truncated?, false),
        do: encode_truncated(frame, configuration),
        else: encode_complete(frame, configuration)
    end
  end

  def encode(%LinkFrame{profile: profile}, _opts), do: {:error, {:invalid_profile, profile}}
  def encode(_frame, _opts), do: {:error, :invalid_frame}

  @impl true
  def decode(binary, opts) when is_binary(binary) and is_list(opts) do
    with {:ok, decoded, _dropped, rest} <- decode_detailed(binary, opts) do
      {:ok, Enum.map(decoded, & &1.frame), rest}
    end
  end

  @spec decode_detailed(binary(), keyword()) ::
          {:ok, [map()], [map()], binary()} | {:error, term()}
  def decode_detailed(binary, opts) when is_binary(binary) and is_list(opts) do
    with {:ok, configuration} <- configuration(opts) do
      decode_stream(binary, %{Configuration.address(configuration) => configuration}, opts)
    end
  end

  @spec decode_managed(binary(), [Configuration.t()], keyword()) ::
          {:ok, [map()], [map()], binary()} | {:error, term()}
  def decode_managed(binary, configurations, opts \\ [])

  def decode_managed(binary, configurations, opts)
      when is_binary(binary) and is_list(configurations) and is_list(opts) do
    with :ok <- Configuration.validate_plan(configurations),
         {:ok, selected} <- select_physical_channel(configurations, opts) do
      decode_stream(binary, Map.new(selected, &{Configuration.address(&1), &1}), opts)
    end
  end

  def decode_managed(binary, configurations, opts),
    do: {:error, {:invalid_uslp_managed_decode, binary, configurations, opts}}

  defp encode_complete(frame, configuration) do
    with {:ok, qos} <- qos(frame),
         {:ok, protocol_control?} <- protocol_control(frame, qos),
         {:ok, insert_zone} <- encode_insert_zone(frame, configuration),
         {:ok, data_field} <- encode_data_field(frame, configuration),
         {:ok, ocf} <- encode_ocf(frame, configuration),
         {:ok, count, count_octets} <- frame_count(frame, configuration, qos),
         {:ok, provisional_header} <-
           complete_primary_header(
             frame,
             configuration,
             qos,
             protocol_control?,
             count,
             count_octets,
             0
           ) do
      total_octets =
        byte_size(provisional_header) + byte_size(insert_zone) + byte_size(data_field) +
          byte_size(ocf) + if(configuration.fecf?, do: FrameErrorControl.size(), else: 0)

      with :ok <- validate_encoded_size(total_octets, configuration),
           {:ok, header} <-
             complete_primary_header(
               frame,
               configuration,
               qos,
               protocol_control?,
               count,
               count_octets,
               total_octets
             ) do
        body = header <> insert_zone <> data_field <> ocf
        {:ok, if(configuration.fecf?, do: FrameErrorControl.append(body), else: body)}
      end
    end
  end

  defp encode_truncated(frame, configuration) do
    with expected when is_integer(expected) <- configuration.truncated_frame_length,
         :ok <- validate_truncated_frame(frame, configuration),
         {:ok, tfdf_header} <- TFDF.encode(:unsegmented, TFDF.upid(:mission_specific), nil),
         header <- abbreviated_header(frame, configuration, 1),
         encoded = header <> tfdf_header <> frame.payload_octets,
         true <- byte_size(encoded) == expected do
      {:ok, encoded}
    else
      nil ->
        {:error, :truncated_uslp_not_configured}

      false ->
        {:error,
         {:truncated_uslp_frame_size_mismatch, 5 + byte_size(frame.payload_octets),
          configuration.truncated_frame_length}}

      {:error, _reason} = error ->
        error
    end
  end

  defp complete_primary_header(
         frame,
         configuration,
         qos,
         protocol_control?,
         count,
         count_octets,
         total_octets
       ) do
    with :ok <- validate_range(total_octets, 0, 65_536, :frame_size) do
      prefix = abbreviated_header(frame, configuration, 0)
      bypass = if(qos == :expedited, do: 1, else: 0)
      protocol = if(protocol_control?, do: 1, else: 0)
      ocf = if(configuration.ocf?, do: 1, else: 0)
      length = max(total_octets - 1, 0)

      {:ok,
       prefix <>
         <<length::16, bypass::1, protocol::1, 0::2, ocf::1, count_octets::3,
           count::size(count_octets * 8)>>}
    end
  end

  defp abbreviated_header(frame, configuration, end_flag) do
    source_destination = if(configuration.source_destination == :destination, do: 1, else: 0)

    <<@version::4, frame.scid::16, source_destination::1, frame.vcid::6, frame.map_id::4,
      end_flag::1>>
  end

  defp encode_insert_zone(frame, %Configuration{insert_zone_length: 0}) do
    case Map.get(frame.meta, :insert_zone) do
      value when value in [nil, <<>>] -> {:ok, <<>>}
      value -> {:error, {:unexpected_uslp_insert_zone, value}}
    end
  end

  defp encode_insert_zone(frame, %Configuration{insert_zone_length: length}) do
    case Map.get(frame.meta, :insert_zone) do
      value when is_binary(value) and byte_size(value) == length -> {:ok, value}
      value -> {:error, {:invalid_uslp_insert_zone_length, value, length}}
    end
  end

  defp encode_data_field(frame, configuration) do
    rule = Map.get(frame.meta, :construction_rule, default_rule(configuration))
    pointer = Map.get(frame.meta, :tfdf_pointer)
    upid = Map.get(frame.meta, :upid, configuration.upid)

    with :ok <- TFDF.validate_for_frame_type(rule, configuration.frame_type),
         :ok <- validate_upid(upid, configuration),
         :ok <- validate_pointer_for_payload(rule, pointer, frame.payload_octets),
         {:ok, header} <- TFDF.encode(rule, upid, pointer) do
      {:ok, header <> frame.payload_octets}
    end
  end

  defp encode_ocf(%LinkFrame{ocf: value}, %Configuration{ocf?: true})
       when is_binary(value) and byte_size(value) == @ocf_octets,
       do: {:ok, value}

  defp encode_ocf(%LinkFrame{ocf: nil}, %Configuration{ocf?: false}), do: {:ok, <<>>}

  defp encode_ocf(frame, configuration),
    do: {:error, {:invalid_uslp_ocf, frame.ocf, configuration.ocf?}}

  defp frame_count(frame, configuration, qos) do
    count_octets = Configuration.count_octets(configuration, qos)
    count = Map.get(frame.meta, :vcf_count, frame.frame_seq)

    validate_frame_count(count, count_octets)
  end

  defp validate_frame_count(count, 0) when count in [nil, 0], do: {:ok, 0, 0}
  defp validate_frame_count(count, 0), do: {:error, {:unexpected_uslp_frame_count, count}}

  defp validate_frame_count(count, count_octets)
       when is_integer(count) and count >= 0 and count < 1 <<< (count_octets * 8),
       do: {:ok, count, count_octets}

  defp validate_frame_count(count, count_octets),
    do: {:error, {:invalid_uslp_frame_count, count, count_octets}}

  defp validate_encoded_size(size, %Configuration{frame_type: :fixed, frame_size: size}), do: :ok

  defp validate_encoded_size(size, %Configuration{frame_type: :fixed, frame_size: expected}),
    do: {:error, {:uslp_fixed_frame_size_mismatch, size, expected}}

  defp validate_encoded_size(size, %Configuration{frame_type: :variable, frame_size: maximum})
       when size <= maximum,
       do: :ok

  defp validate_encoded_size(size, %Configuration{frame_type: :variable, frame_size: maximum}),
    do: {:error, {:uslp_frame_exceeds_managed_maximum, size, maximum}}

  defp decode_stream(binary, indexed, opts),
    do: decode_stream(binary, indexed, opts, 0, [], [])

  defp decode_stream(binary, indexed, opts, offset, decoded, dropped) do
    case next_frame(binary, indexed) do
      {:ok, raw, rest, configuration} ->
        case decode_frame(raw, configuration, opts) do
          {:ok, frame} ->
            evidence = %{
              frame: frame,
              raw_frame_offset_bytes: offset,
              raw_frame_length_bytes: byte_size(raw)
            }

            decode_stream(
              rest,
              indexed,
              opts,
              offset + byte_size(raw),
              [evidence | decoded],
              dropped
            )

          {:error, reason} ->
            anomaly = %{
              anomaly_kind: :frame_decode_dropped,
              raw_frame_offset_bytes: offset,
              raw_frame_length_bytes: byte_size(raw),
              metadata: %{profile: :uslp, reason: reason}
            }

            decode_stream(
              rest,
              indexed,
              opts,
              offset + byte_size(raw),
              decoded,
              [anomaly | dropped]
            )
        end

      {:incomplete, rest} ->
        {:ok, Enum.reverse(decoded), Enum.reverse(dropped), rest}

      {:error, _reason} = error ->
        error
    end
  end

  defp next_frame(binary, _indexed) when byte_size(binary) < 4, do: {:incomplete, binary}

  defp next_frame(binary, indexed) do
    with {:ok, address, truncated?} <- routing_header(binary),
         {:ok, configuration} <- fetch_configuration(indexed, address),
         {:ok, length} <- wire_frame_length(binary, configuration, truncated?) do
      if byte_size(binary) >= length do
        <<frame::binary-size(^length), rest::binary>> = binary
        {:ok, frame, rest, configuration}
      else
        {:incomplete, binary}
      end
    end
  end

  defp routing_header(
         <<version::4, scid::16, _source_destination::1, vcid::6, map_id::4, end_flag::1,
           _rest::binary>>
       ) do
    with :ok <- validate_version(version),
         :ok <- validate_bit(end_flag, :end_of_primary_header_flag) do
      {:ok, {scid, vcid, map_id}, end_flag == 1}
    end
  end

  defp wire_frame_length(_binary, configuration, true) do
    case configuration.truncated_frame_length do
      value when is_integer(value) -> {:ok, value}
      nil -> {:error, :unexpected_truncated_uslp_frame}
    end
  end

  defp wire_frame_length(binary, _configuration, false) when byte_size(binary) < 6,
    do: {:incomplete, binary}

  defp wire_frame_length(
         <<_prefix::binary-size(4), length_minus_one::16, _rest::binary>>,
         configuration,
         false
       ) do
    length = length_minus_one + 1

    case validate_wire_size(length, configuration) do
      :ok -> {:ok, length}
      {:error, _reason} = error -> error
    end
  end

  defp decode_frame(raw, configuration, opts) do
    <<_prefix::31, end_flag::1, _rest::binary>> = raw

    if end_flag == 1,
      do: decode_truncated(raw, configuration, opts),
      else: decode_complete(raw, configuration, opts)
  end

  defp decode_complete(raw, configuration, opts) do
    with {:ok, body, fecf} <- strip_fecf(raw, configuration),
         {:ok, primary, rest} <- decode_primary_header(body),
         :ok <- validate_primary(primary, raw, configuration),
         {:ok, insert_zone, after_insert} <-
           take_prefix(rest, configuration.insert_zone_length, :insert_zone),
         {:ok, without_ocf, ocf} <- take_ocf(after_insert, configuration),
         {:ok, tfdf, payload} <- TFDF.decode(without_ocf),
         :ok <- validate_tfdf(tfdf, payload, configuration) do
      {:ok,
       %LinkFrame{
         profile: :uslp,
         scid: primary.scid,
         vcid: primary.vcid,
         map_id: primary.map_id,
         frame_seq: primary.vcf_count,
         payload_octets: payload,
         quality: quality(opts),
         ocf: ocf,
         timestamp: Keyword.get(opts, :timestamp),
         meta: %{
           physical_channel: configuration.physical_channel,
           source_destination: primary.source_destination,
           qos: primary.qos,
           protocol_control?: primary.protocol_control?,
           frame_length: byte_size(raw),
           vcf_count: primary.vcf_count,
           vcf_count_length: primary.vcf_count_length,
           construction_rule: tfdf.construction_rule,
           upid: tfdf.upid,
           tfdf_pointer: tfdf.pointer,
           insert_zone: insert_zone,
           fecf: fecf,
           truncated?: false,
           uslp_configuration: configuration
         }
       }}
    end
  end

  defp decode_truncated(raw, configuration, opts) do
    with true <- byte_size(raw) == configuration.truncated_frame_length,
         <<version::4, scid::16, source_destination::1, vcid::6, map_id::4, 1::1, rule::3,
           upid::5, payload::binary>> <- raw,
         :ok <- validate_version(version),
         true <- rule == 7,
         true <- upid == TFDF.upid(:mission_specific),
         true <- byte_size(payload) > 0,
         :ok <- validate_decoded_address(scid, vcid, map_id, configuration) do
      {:ok,
       %LinkFrame{
         profile: :uslp,
         scid: scid,
         vcid: vcid,
         map_id: map_id,
         frame_seq: nil,
         payload_octets: payload,
         quality: quality(opts),
         ocf: nil,
         timestamp: Keyword.get(opts, :timestamp),
         meta: %{
           physical_channel: configuration.physical_channel,
           source_destination: decode_source_destination(source_destination),
           qos: :expedited,
           protocol_control?: false,
           frame_length: byte_size(raw),
           vcf_count: nil,
           vcf_count_length: 0,
           construction_rule: :unsegmented,
           upid: upid,
           tfdf_pointer: nil,
           insert_zone: nil,
           fecf: nil,
           truncated?: true,
           uslp_configuration: configuration
         }
       }}
    else
      false -> {:error, :invalid_truncated_uslp_frame}
      _other -> {:error, :malformed_truncated_uslp_frame}
    end
  end

  defp decode_primary_header(
         <<version::4, scid::16, source_destination::1, vcid::6, map_id::4, 0::1,
           length_minus_one::16, bypass::1, protocol::1, spare::2, ocf::1, count_octets::3,
           rest::binary>>
       ) do
    count_bits = count_octets * 8

    if bit_size(rest) >= count_bits do
      <<count::size(^count_bits), remaining::binary>> = rest

      {:ok,
       %{
         version: version,
         scid: scid,
         source_destination: decode_source_destination(source_destination),
         vcid: vcid,
         map_id: map_id,
         length: length_minus_one + 1,
         qos: if(bypass == 1, do: :expedited, else: :sequence_controlled),
         protocol_control?: protocol == 1,
         spare: spare,
         ocf?: ocf == 1,
         vcf_count_length: count_octets,
         vcf_count: if(count_octets == 0, do: nil, else: count)
       }, remaining}
    else
      {:error, :truncated_uslp_vcf_count}
    end
  end

  defp decode_primary_header(_binary), do: {:error, :malformed_uslp_primary_header}

  defp validate_primary(primary, raw, configuration) do
    with :ok <- validate_version(primary.version),
         true <- primary.length == byte_size(raw),
         true <- primary.spare == 0,
         true <- not (primary.qos == :sequence_controlled and primary.protocol_control?),
         true <- primary.ocf? == configuration.ocf?,
         true <- primary.source_destination == configuration.source_destination,
         true <-
           primary.vcf_count_length == Configuration.count_octets(configuration, primary.qos) do
      validate_decoded_address(primary.scid, primary.vcid, primary.map_id, configuration)
    else
      false -> {:error, {:uslp_primary_header_managed_mismatch, primary}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_tfdf(tfdf, payload, configuration) do
    with :ok <- TFDF.validate_for_frame_type(tfdf.construction_rule, configuration.frame_type),
         :ok <- validate_upid(tfdf.upid, configuration),
         true <- byte_size(payload) > 0 do
      validate_pointer_for_payload(tfdf.construction_rule, tfdf.pointer, payload)
    else
      false -> {:error, :empty_uslp_transfer_frame_data_zone}
      {:error, _reason} = error -> error
    end
  end

  defp strip_fecf(raw, %Configuration{fecf?: true}) do
    case FrameErrorControl.validate_and_strip(raw) do
      {:ok, body, fecf} -> {:ok, body, fecf}
      {:error, _reason} = error -> error
    end
  end

  defp strip_fecf(raw, %Configuration{fecf?: false}), do: {:ok, raw, nil}

  defp take_prefix(binary, 0, _field), do: {:ok, <<>>, binary}

  defp take_prefix(binary, length, _field) when byte_size(binary) >= length do
    <<value::binary-size(^length), rest::binary>> = binary
    {:ok, value, rest}
  end

  defp take_prefix(_binary, _length, field), do: {:error, {:truncated_uslp_field, field}}

  defp take_ocf(binary, %Configuration{ocf?: false}), do: {:ok, binary, nil}

  defp take_ocf(binary, %Configuration{ocf?: true}) when byte_size(binary) >= @ocf_octets do
    payload_size = byte_size(binary) - @ocf_octets
    <<payload::binary-size(^payload_size), ocf::binary-size(@ocf_octets)>> = binary
    {:ok, payload, ocf}
  end

  defp take_ocf(_binary, %Configuration{ocf?: true}), do: {:error, :truncated_uslp_ocf}

  defp validate_truncated_frame(frame, configuration) do
    cond do
      configuration.frame_type != :variable ->
        {:error, :truncated_uslp_requires_variable_frames}

      frame.ocf not in [nil, <<>>] ->
        {:error, :truncated_uslp_forbids_ocf}

      Map.get(frame.meta, :insert_zone) not in [nil, <<>>] ->
        {:error, :truncated_uslp_forbids_insert_zone}

      Map.get(frame.meta, :qos, :expedited) != :expedited ->
        {:error, :truncated_uslp_requires_expedited_qos}

      Map.get(frame.meta, :protocol_control?, false) ->
        {:error, :truncated_uslp_forbids_protocol_control}

      byte_size(frame.payload_octets) == 0 ->
        {:error, :empty_uslp_transfer_frame_data_zone}

      true ->
        :ok
    end
  end

  defp validate_wire_size(size, %Configuration{frame_type: :fixed, frame_size: size}), do: :ok

  defp validate_wire_size(size, %Configuration{frame_type: :fixed, frame_size: expected}),
    do: {:error, {:uslp_fixed_frame_size_mismatch, size, expected}}

  defp validate_wire_size(size, %Configuration{frame_type: :variable, frame_size: maximum})
       when size >= 9 and size <= maximum,
       do: :ok

  defp validate_wire_size(size, %Configuration{frame_type: :variable, frame_size: maximum}),
    do: {:error, {:invalid_uslp_variable_frame_size, size, maximum}}

  defp validate_address(frame, configuration) do
    validate_decoded_address(frame.scid, frame.vcid, frame.map_id, configuration)
  end

  defp validate_decoded_address(scid, vcid, map_id, configuration) do
    if {scid, vcid, map_id} == Configuration.address(configuration),
      do: :ok,
      else:
        {:error,
         {:uslp_address_mismatch, {scid, vcid, map_id}, Configuration.address(configuration)}}
  end

  defp validate_pointer_for_payload(rule, nil, _payload)
       when rule not in [
              :packets_spanning_frames,
              :start_access_sdu,
              :continue_access_sdu
            ],
       do: :ok

  defp validate_pointer_for_payload(rule, 0xFFFF, _payload)
       when rule in [:packets_spanning_frames, :start_access_sdu, :continue_access_sdu],
       do: :ok

  defp validate_pointer_for_payload(rule, pointer, payload)
       when rule in [:packets_spanning_frames, :start_access_sdu, :continue_access_sdu] and
              is_integer(pointer) and pointer >= 0 and pointer < byte_size(payload),
       do: :ok

  defp validate_pointer_for_payload(rule, pointer, payload),
    do: {:error, {:invalid_uslp_tfdf_pointer, rule, pointer, byte_size(payload)}}

  defp validate_upid(upid, configuration) do
    if upid == configuration.upid,
      do: :ok,
      else: {:error, {:uslp_upid_mismatch, upid, configuration.upid}}
  end

  defp qos(frame) do
    case Map.get(frame.meta, :qos, :sequence_controlled) do
      value when value in [:sequence_controlled, :expedited] -> {:ok, value}
      value -> {:error, {:invalid_uslp_qos, value}}
    end
  end

  defp protocol_control(frame, qos) do
    value = Map.get(frame.meta, :protocol_control?, false)

    cond do
      not is_boolean(value) -> {:error, {:invalid_field, :protocol_control?, value}}
      value and qos != :expedited -> {:error, :protocol_control_requires_expedited_qos}
      true -> {:ok, value}
    end
  end

  defp default_rule(%Configuration{frame_type: :fixed, data_field_content: :packets}),
    do: :packets_spanning_frames

  defp default_rule(%Configuration{frame_type: :fixed}), do: :start_access_sdu
  defp default_rule(%Configuration{data_field_content: :octet_stream}), do: :octet_stream
  defp default_rule(%Configuration{}), do: :unsegmented

  defp configuration(opts) do
    case Keyword.get(opts, :configuration) do
      %Configuration{} = configuration ->
        case Configuration.validate(configuration) do
          :ok -> {:ok, configuration}
          {:error, _reason} = error -> error
        end

      nil ->
        {:error, {:missing_option, :configuration}}

      value ->
        {:error, {:invalid_uslp_configuration, value}}
    end
  end

  defp select_physical_channel(configurations, opts) do
    grouped = Enum.group_by(configurations, & &1.physical_channel)

    case Keyword.get(opts, :physical_channel) do
      nil ->
        case Map.to_list(grouped) do
          [{_name, selected}] -> {:ok, selected}
          _many -> {:error, {:physical_channel_required, grouped |> Map.keys() |> Enum.sort()}}
        end

      name when is_binary(name) ->
        case Map.fetch(grouped, name) do
          {:ok, selected} -> {:ok, selected}
          :error -> {:error, {:unknown_physical_channel, name}}
        end

      value ->
        {:error, {:invalid_physical_channel, value}}
    end
  end

  defp fetch_configuration(indexed, address) do
    case Map.fetch(indexed, address) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:unknown_uslp_channel, address}}
    end
  end

  defp decode_source_destination(0), do: :source
  defp decode_source_destination(1), do: :destination

  defp quality(opts) do
    case Keyword.get(opts, :quality, :good) do
      value when value in [:good, :suspect, :invalid] -> value
      _value -> :good
    end
  end

  defp validate_version(@version), do: :ok
  defp validate_version(value), do: {:error, {:invalid_uslp_version, value}}
  defp validate_bit(value, _field) when value in [0, 1], do: :ok
  defp validate_bit(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}
end
