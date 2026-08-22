defmodule CCSDS.SDLP.AOS.FrameCodec do
  @moduledoc """
  CCSDS 732.0-B-5 AOS Transfer Frame wire codec.

  The codec supports the issue-5 10-bit SCID, optional shortened Reed-Solomon
  Frame Header Error Control, Insert Zone, M_PDU, B_PDU, VCA_SDU and OID data
  fields, per-VC OCF, and physical-channel FECF. All optional field presence is
  supplied through managed `AOS.Configuration`.
  """

  @behaviour CCSDS.SDLP.FrameCodec

  import Bitwise

  alias CCSDS.Core.LinkFrame
  alias CCSDS.FrameErrorControl

  alias CCSDS.SDLP.AOS.{BPDU, Configuration, FrameHeaderErrorControl, MPDU}

  @version 1
  @base_primary_header_octets 6
  @ocf_octets 4

  @impl true
  def profile, do: :aos

  @impl true
  def encode(%LinkFrame{profile: :aos} = frame, opts) when is_list(opts) do
    with {:ok, configuration} <- configuration(opts),
         :ok <- validate_address(frame, configuration),
         {:ok, primary_header, header_metadata} <- encode_primary_header(frame, configuration),
         {:ok, insert_zone} <- encode_insert_zone(frame, configuration),
         {:ok, data_field} <- encode_data_field(frame, configuration),
         {:ok, ocf} <- encode_ocf(frame, configuration),
         :ok <- validate_data_field_size(data_field, configuration) do
      body = primary_header <> insert_zone <> data_field <> ocf
      encoded = if(configuration.fecf?, do: FrameErrorControl.append(body), else: body)

      if byte_size(encoded) == configuration.frame_size do
        {:ok, encoded}
      else
        {:error,
         {:aos_frame_size_mismatch, byte_size(encoded), configuration.frame_size, header_metadata}}
      end
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
      decode_complete_frames(binary, configuration, opts)
    end
  end

  @doc """
  Decodes a fixed-length physical-channel stream and routes each frame to its
  managed Virtual Channel configuration.

  The optional FHEC is corrected before the issue-5 SCID and VCID are used for
  routing. `:physical_channel` is required only when the supplied plan spans
  more than one physical channel.
  """
  @spec decode_managed(binary(), [Configuration.t()], keyword()) ::
          {:ok, [map()], [map()], binary()} | {:error, term()}
  def decode_managed(binary, configurations, opts \\ [])

  def decode_managed(binary, configurations, opts)
      when is_binary(binary) and is_list(configurations) and is_list(opts) do
    with :ok <- Configuration.validate_plan(configurations),
         {:ok, physical_configurations} <- select_physical_channel(configurations, opts) do
      decode_managed_frames(binary, physical_configurations, opts)
    end
  end

  def decode_managed(binary, configurations, opts),
    do: {:error, {:invalid_aos_managed_decode, binary, configurations, opts}}

  defp decode_complete_frames(binary, configuration, opts) do
    {frames, rest} = split_frames(binary, configuration.frame_size)

    {decoded, dropped} =
      frames
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {frame, index}, {decoded, dropped} ->
        accumulate_decoded_frame(frame, index, configuration, opts, decoded, dropped)
      end)

    {:ok, Enum.reverse(decoded), Enum.reverse(dropped), rest}
  end

  defp decode_managed_frames(binary, configurations, opts) do
    frame_size = hd(configurations).frame_size
    {frames, rest} = split_frames(binary, frame_size)
    indexed = Map.new(configurations, &{Configuration.address(&1), &1})

    {decoded, dropped} =
      frames
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {frame, index}, {decoded, dropped} ->
        accumulate_managed_frame(frame, index, frame_size, indexed, opts, decoded, dropped)
      end)

    {:ok, Enum.reverse(decoded), Enum.reverse(dropped), rest}
  end

  defp accumulate_managed_frame(frame, index, frame_size, indexed, opts, decoded, dropped) do
    offset = index * frame_size

    case decode_routed_frame(frame, indexed, opts) do
      {:ok, link_frame} ->
        evidence = %{
          frame: link_frame,
          raw_frame_offset_bytes: offset,
          raw_frame_length_bytes: frame_size
        }

        {[evidence | decoded], dropped}

      {:error, reason} ->
        anomaly = %{
          anomaly_kind: :frame_decode_dropped,
          raw_frame_offset_bytes: offset,
          raw_frame_length_bytes: frame_size,
          metadata: %{profile: :aos, reason: reason}
        }

        {decoded, [anomaly | dropped]}
    end
  end

  defp decode_routed_frame(frame, indexed, opts) do
    sample_configuration = indexed |> Map.values() |> hd()

    with {:ok, scid, vcid} <- routing_address(frame, sample_configuration),
         {:ok, configuration} <- fetch_routed_configuration(indexed, scid, vcid) do
      decode_frame(frame, configuration, opts)
    end
  end

  defp routing_address(
         <<protected::16, _vcfc::24, signaling::8, error_control::16, _rest::binary>>,
         %Configuration{frame_header_error_control?: true}
       ) do
    with {:ok, decoded} <- FrameHeaderErrorControl.decode(protected, signaling, error_control) do
      decode_routing_fields(decoded.protected_header, decoded.signaling)
    end
  end

  defp routing_address(
         <<protected::16, _vcfc::24, signaling::8, _rest::binary>>,
         %Configuration{frame_header_error_control?: false}
       ) do
    decode_routing_fields(protected, signaling)
  end

  defp routing_address(_frame, _configuration), do: {:error, :truncated_aos_primary_header}

  defp decode_routing_fields(protected, signaling) do
    <<version::2, scid_lsb::8, vcid::6>> = <<protected::16>>
    <<_replay::1, _cycle_use::1, scid_msb::2, _cycle::4>> = <<signaling::8>>

    with :ok <- validate_version(version) do
      {:ok, scid_msb <<< 8 ||| scid_lsb, vcid}
    end
  end

  defp fetch_routed_configuration(indexed, scid, vcid) do
    case Map.fetch(indexed, {scid, vcid}) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:unknown_aos_channel, scid, vcid}}
    end
  end

  defp select_physical_channel(configurations, opts) do
    grouped = Enum.group_by(configurations, & &1.physical_channel)

    case Keyword.get(opts, :physical_channel) do
      nil -> select_only_physical_channel(grouped)
      physical when is_binary(physical) -> fetch_physical_channel(grouped, physical)
      value -> {:error, {:invalid_physical_channel, value}}
    end
  end

  defp select_only_physical_channel(grouped) do
    case Map.to_list(grouped) do
      [{_physical, configurations}] -> {:ok, configurations}
      _many -> {:error, {:physical_channel_required, grouped |> Map.keys() |> Enum.sort()}}
    end
  end

  defp fetch_physical_channel(grouped, physical) do
    case Map.fetch(grouped, physical) do
      {:ok, configurations} -> {:ok, configurations}
      :error -> {:error, {:unknown_physical_channel, physical}}
    end
  end

  defp accumulate_decoded_frame(frame, index, configuration, opts, decoded, dropped) do
    offset = index * configuration.frame_size

    case decode_frame(frame, configuration, opts) do
      {:ok, link_frame} ->
        evidence = %{
          frame: link_frame,
          raw_frame_offset_bytes: offset,
          raw_frame_length_bytes: configuration.frame_size
        }

        {[evidence | decoded], dropped}

      {:error, reason} ->
        anomaly = %{
          anomaly_kind: :frame_decode_dropped,
          raw_frame_offset_bytes: offset,
          raw_frame_length_bytes: configuration.frame_size,
          metadata: %{profile: :aos, reason: reason}
        }

        {decoded, [anomaly | dropped]}
    end
  end

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
        {:error, {:invalid_aos_configuration, value}}
    end
  end

  defp encode_primary_header(frame, configuration) do
    vcfc = Map.get(frame.meta, :vcfc, frame.frame_seq || 0)
    replay_flag = Map.get(frame.meta, :replay_flag, 0)
    cycle_use_flag = Map.get(frame.meta, :vc_frame_count_cycle_use_flag, 0)
    cycle = Map.get(frame.meta, :vc_frame_count_cycle, 0)

    with :ok <- validate_range(vcfc, 0, 0xFFFFFF, :vcfc),
         :ok <- validate_bit(replay_flag, :replay_flag),
         :ok <- validate_bit(cycle_use_flag, :vc_frame_count_cycle_use_flag),
         :ok <- validate_cycle(cycle, cycle_use_flag) do
      scid_lsb = frame.scid &&& 0xFF
      scid_msb = frame.scid >>> 8
      protected_header = <<@version::2, scid_lsb::8, frame.vcid::6>>
      signaling = <<replay_flag::1, cycle_use_flag::1, scid_msb::2, cycle::4>>
      base = protected_header <> <<vcfc::24>> <> signaling

      if configuration.frame_header_error_control? do
        <<protected_value::16>> = protected_header
        <<signaling_value::8>> = signaling
        {:ok, error_control} = FrameHeaderErrorControl.encode(protected_value, signaling_value)

        {:ok, base <> <<error_control::16>>,
         %{frame_header_error_control: error_control, protected_header: protected_value}}
      else
        {:ok, base, %{frame_header_error_control: nil}}
      end
    end
  end

  defp encode_insert_zone(frame, %Configuration{insert_zone_length: 0}) do
    case Map.get(frame.meta, :insert_zone) do
      value when value in [nil, <<>>] -> {:ok, <<>>}
      value -> {:error, {:unexpected_aos_insert_zone, value}}
    end
  end

  defp encode_insert_zone(frame, %Configuration{insert_zone_length: expected}) do
    case Map.get(frame.meta, :insert_zone) do
      value when is_binary(value) and byte_size(value) == expected ->
        {:ok, value}

      value when is_binary(value) ->
        {:error, {:aos_insert_zone_length_mismatch, byte_size(value), expected}}

      value ->
        {:error, {:missing_aos_insert_zone, value, expected}}
    end
  end

  defp encode_data_field(frame, %Configuration{data_field_content: :m_pdu}) do
    MPDU.encode(%MPDU{
      first_header_pointer: Map.get(frame.meta, :first_header_pointer),
      packet_zone: frame.payload_octets
    })
  end

  defp encode_data_field(frame, %Configuration{data_field_content: :b_pdu}) do
    BPDU.encode(%BPDU{
      bitstream_data_pointer: Map.get(frame.meta, :bitstream_data_pointer),
      data_zone: frame.payload_octets
    })
  end

  defp encode_data_field(%LinkFrame{payload_octets: payload}, %Configuration{
         data_field_content: content
       })
       when content in [:vca_sdu, :idle_data] and is_binary(payload),
       do: {:ok, payload}

  defp encode_data_field(frame, configuration),
    do:
      {:error, {:invalid_aos_data_field, configuration.data_field_content, frame.payload_octets}}

  defp encode_ocf(%LinkFrame{ocf: ocf}, %Configuration{ocf?: true})
       when is_binary(ocf) and byte_size(ocf) == @ocf_octets,
       do: {:ok, ocf}

  defp encode_ocf(%LinkFrame{ocf: ocf}, %Configuration{ocf?: true}),
    do: {:error, {:invalid_aos_ocf, ocf}}

  defp encode_ocf(%LinkFrame{ocf: ocf}, %Configuration{ocf?: false}) when ocf in [nil, <<>>],
    do: {:ok, <<>>}

  defp encode_ocf(%LinkFrame{ocf: ocf}, %Configuration{ocf?: false}),
    do: {:error, {:unexpected_aos_ocf, ocf}}

  defp validate_data_field_size(data_field, configuration) do
    expected = Configuration.data_field_octets(configuration)
    actual = byte_size(data_field)

    if actual == expected,
      do: :ok,
      else: {:error, {:invalid_aos_data_field_length, actual, expected}}
  end

  defp decode_frame(frame, configuration, opts) do
    with {:ok, body, received_fecf} <- split_fecf(frame, configuration.fecf?),
         {:ok, corrected_body, header_evidence} <- correct_header(body, configuration),
         :ok <- validate_fecf(corrected_body, received_fecf),
         {:ok, decoded} <- decode_body(corrected_body, configuration, opts) do
      meta =
        decoded.meta
        |> Map.merge(header_evidence)
        |> Map.put(:fecf_present, configuration.fecf?)
        |> Map.put(:fecf, received_fecf)

      {:ok, %{decoded | meta: meta}}
    end
  end

  defp split_fecf(frame, true) do
    size = byte_size(frame) - FrameErrorControl.size()
    <<body::binary-size(^size), fecf::16>> = frame
    {:ok, body, fecf}
  end

  defp split_fecf(frame, false), do: {:ok, frame, nil}

  defp correct_header(
         <<protected::16, vcfc::24, signaling::8, error_control::16, rest::binary>>,
         %Configuration{frame_header_error_control?: true}
       ) do
    with {:ok, decoded} <- FrameHeaderErrorControl.decode(protected, signaling, error_control) do
      corrected =
        <<decoded.protected_header::16, vcfc::24, decoded.signaling::8, decoded.error_control::16,
          rest::binary>>

      {:ok, corrected,
       %{
         frame_header_error_control_present: true,
         frame_header_error_control: decoded.error_control,
         frame_header_error_control_status: decoded.status,
         corrected_header_symbols: decoded.corrected_symbols
       }}
    end
  end

  defp correct_header(body, %Configuration{frame_header_error_control?: false})
       when byte_size(body) >= @base_primary_header_octets do
    {:ok, body,
     %{
       frame_header_error_control_present: false,
       frame_header_error_control: nil,
       frame_header_error_control_status: :absent,
       corrected_header_symbols: []
     }}
  end

  defp correct_header(_body, _configuration), do: {:error, :truncated_aos_primary_header}

  defp validate_fecf(_body, nil), do: :ok

  defp validate_fecf(body, received) do
    expected = FrameErrorControl.calculate(body)
    if expected == received, do: :ok, else: {:error, {:invalid_fecf, expected, received}}
  end

  defp decode_body(body, configuration, opts) do
    header_octets = Configuration.primary_header_octets(configuration)
    <<primary_header::binary-size(^header_octets), rest::binary>> = body

    <<
      version::2,
      scid_lsb::8,
      vcid::6,
      vcfc::24,
      replay_flag::1,
      cycle_use_flag::1,
      scid_msb::2,
      cycle::4,
      _header_error_control::binary
    >> = primary_header

    scid = scid_msb <<< 8 ||| scid_lsb
    insert_octets = configuration.insert_zone_length
    data_octets = Configuration.data_field_octets(configuration)
    ocf_octets = if(configuration.ocf?, do: @ocf_octets, else: 0)

    with :ok <- validate_version(version),
         :ok <- validate_decoded_address(scid, vcid, configuration),
         :ok <- validate_cycle(cycle, cycle_use_flag),
         :ok <- validate_remaining_size(rest, insert_octets + data_octets + ocf_octets),
         {:ok, insert_zone, data_field, ocf} <-
           split_body(rest, insert_octets, data_octets, ocf_octets),
         {:ok, payload, content_meta} <- decode_data_field(data_field, configuration) do
      meta =
        %{
          version: version,
          vcfc: vcfc,
          replay_flag: replay_flag,
          vc_frame_count_cycle_use_flag: cycle_use_flag,
          vc_frame_count_cycle: cycle,
          physical_channel: configuration.physical_channel,
          data_field_content: configuration.data_field_content,
          insert_zone: insert_zone,
          insert_zone_present: insert_octets > 0,
          ocf_present: ocf_octets > 0
        }
        |> Map.merge(content_meta)

      {:ok,
       %LinkFrame{
         profile: :aos,
         scid: scid,
         vcid: vcid,
         map_id: nil,
         frame_seq: vcfc,
         payload_octets: payload,
         quality: :good,
         ocf: if(ocf_octets > 0, do: ocf, else: nil),
         timestamp: Keyword.get(opts, :timestamp),
         meta: meta
       }}
    end
  end

  defp decode_data_field(data_field, %Configuration{data_field_content: :m_pdu}) do
    with {:ok, mpdu} <- MPDU.decode(data_field) do
      {:ok, mpdu.packet_zone, %{first_header_pointer: mpdu.first_header_pointer}}
    end
  end

  defp decode_data_field(data_field, %Configuration{data_field_content: :b_pdu}) do
    with {:ok, bpdu} <- BPDU.decode(data_field),
         {:ok, valid_bits} <- BPDU.valid_bits(bpdu) do
      {:ok, bpdu.data_zone,
       %{bitstream_data_pointer: bpdu.bitstream_data_pointer, valid_bits: valid_bits}}
    end
  end

  defp decode_data_field(data_field, %Configuration{data_field_content: content})
       when content in [:vca_sdu, :idle_data],
       do: {:ok, data_field, %{}}

  defp validate_address(%LinkFrame{scid: scid, vcid: vcid}, configuration) do
    if scid == configuration.scid and vcid == configuration.vcid,
      do: :ok,
      else: {:error, {:aos_address_mismatch, {scid, vcid}, Configuration.address(configuration)}}
  end

  defp validate_decoded_address(scid, vcid, configuration) do
    cond do
      scid not in configuration.valid_scids ->
        {:error, {:unmanaged_aos_scid, scid}}

      vcid not in configuration.valid_vcids ->
        {:error, {:unmanaged_aos_vcid, vcid}}

      scid != configuration.scid or vcid != configuration.vcid ->
        {:error, {:aos_address_mismatch, {scid, vcid}, Configuration.address(configuration)}}

      true ->
        :ok
    end
  end

  defp validate_version(@version), do: :ok
  defp validate_version(value), do: {:error, {:unsupported_aos_version, value}}

  defp validate_cycle(0, 0), do: :ok
  defp validate_cycle(value, 0), do: {:error, {:unused_aos_frame_count_cycle_not_zero, value}}
  defp validate_cycle(value, 1) when is_integer(value) and value in 0..15, do: :ok
  defp validate_cycle(value, flag), do: {:error, {:invalid_aos_frame_count_cycle, value, flag}}

  defp validate_bit(value, _field) when value in [0, 1], do: :ok
  defp validate_bit(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  defp validate_remaining_size(rest, expected) do
    if byte_size(rest) == expected,
      do: :ok,
      else: {:error, {:invalid_aos_frame_body_length, byte_size(rest), expected}}
  end

  defp split_body(rest, insert_octets, data_octets, ocf_octets) do
    <<insert_zone::binary-size(^insert_octets), data_field::binary-size(^data_octets),
      ocf::binary-size(^ocf_octets)>> = rest

    {:ok, insert_zone, data_field, ocf}
  end

  defp split_frames(binary, frame_size) do
    count = div(byte_size(binary), frame_size)
    complete_size = count * frame_size
    <<complete::binary-size(^complete_size), rest::binary>> = binary
    {for(<<frame::binary-size(^frame_size) <- complete>>, do: frame), rest}
  end
end
