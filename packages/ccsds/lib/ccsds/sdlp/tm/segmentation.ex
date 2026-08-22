defmodule CCSDS.SDLP.TM.Segmentation do
  @moduledoc """
  Pure sending-end TM Virtual Channel generation.

  Packet streams are packed into fixed-size Transfer Frame Data Fields and
  completed with standards-shaped Idle Packets. When fewer than seven octets
  remain, the Idle Packet is allowed to spill into the next frame as required
  by CCSDS 132.0-B-3. VCA_SDUs occupy exactly one managed data field. Master
  and Virtual Channel counters, and OID PN state, are independent by channel.
  """

  @behaviour CCSDS.SDLP.Segmentation

  alias CCSDS.Core.{LinkFrame, SDUOctets}
  alias CCSDS.FrameErrorControl

  alias CCSDS.SDLP.TM.{Configuration, FrameCodec, OnlyIdleData, SecondaryHeader}
  alias CCSDS.SpacePacket
  alias CCSDS.SpacePacket.Idle
  alias CCSDS.SpacePacket.Stream

  @primary_header_size 6
  @ocf_size 4
  @min_idle_packet_size 7

  @impl true
  def init(opts) when is_list(opts) do
    initial_mcfc = Keyword.get(opts, :mcfc, 0)
    initial_vcfc = Keyword.get(opts, :vcfc, 0)

    with :ok <- validate_counter(initial_mcfc, :mcfc),
         :ok <- validate_counter(initial_vcfc, :vcfc) do
      {:ok,
       %{
         initial_mcfc: initial_mcfc,
         initial_vcfc: initial_vcfc,
         mcfc: initial_mcfc,
         vcfc: initial_vcfc,
         mcfc_by_master_channel: %{},
         vcfc_by_virtual_channel: %{},
         oid_lfsr_by_virtual_channel: %{},
         idle_padding_cache: %{}
       }}
    end
  end

  @impl true
  def segment(%SDUOctets{profile: :tm} = sdu, ctx, state) when is_map(ctx) and is_map(state) do
    with {:ok, frame_context} <- build_frame_context(sdu, ctx),
         :ok <- validate_sdu_kind(sdu, frame_context) do
      segment_for_content(sdu, frame_context, state)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def segment(%SDUOctets{profile: profile}, _ctx, state),
    do: {:error, {:invalid_profile, profile}, state}

  def segment(_sdu, _ctx, state), do: {:error, :invalid_sdu, state}

  @spec segment_encode(SDUOctets.t(), map(), term(), keyword()) ::
          {:ok, iodata(), term()} | {:error, term(), term()}
  def segment_encode(%SDUOctets{profile: :tm} = sdu, ctx, state, opts)
      when is_map(ctx) and is_list(opts) do
    with {:ok, frames, next_state} <- segment(sdu, ctx, state),
         {:ok, frame_context} <- build_frame_context(sdu, ctx),
         {:ok, encoded} <- encode_frames(frames, frame_context, opts) do
      {:ok, encoded, next_state}
    else
      {:error, reason, _next_state} -> {:error, reason, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  def segment_encode(%SDUOctets{profile: profile}, _ctx, state, _opts),
    do: {:error, {:invalid_profile, profile}, state}

  @doc """
  Generates one OID Transfer Frame for a managed Packet Virtual Channel.
  """
  @spec only_idle(map(), map()) :: {:ok, LinkFrame.t(), map()} | {:error, term(), map()}
  def only_idle(ctx, state) when is_map(ctx) and is_map(state) do
    placeholder = %SDUOctets{
      profile: :tm,
      scid: Map.get(ctx, :scid),
      vcid: Map.get(ctx, :vcid),
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: <<>>,
      quality: :good,
      source_frames: [],
      meta: %{}
    }

    with {:ok, frame_context} <- build_frame_context(placeholder, ctx),
         :ok <- require_packet_channel(frame_context) do
      address = virtual_channel_key(frame_context)

      lfsr_state =
        Map.get(state.oid_lfsr_by_virtual_channel, address, OnlyIdleData.initial_state())

      {payload, next_lfsr_state} = OnlyIdleData.take(frame_context.max_payload, lfsr_state)
      {frame, next_state} = build_frame(payload, 2046, frame_context, state, %{})

      final_state = %{
        next_state
        | oid_lfsr_by_virtual_channel:
            Map.put(next_state.oid_lfsr_by_virtual_channel, address, next_lfsr_state)
      }

      {:ok, frame, final_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @spec only_idle_encode(map(), map(), keyword()) ::
          {:ok, binary(), map()} | {:error, term(), map()}
  def only_idle_encode(ctx, state, opts \\ []) when is_map(ctx) and is_list(opts) do
    with {:ok, frame, next_state} <- only_idle(ctx, state),
         placeholder = %SDUOctets{profile: :tm, scid: frame.scid, vcid: frame.vcid, meta: %{}},
         {:ok, frame_context} <- build_frame_context(placeholder, ctx),
         {:ok, encoded} <- FrameCodec.encode(frame, codec_options(frame_context, opts)) do
      {:ok, encoded, next_state}
    else
      {:error, reason, _next_state} -> {:error, reason, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp segment_for_content(sdu, %{data_field_content: :packets} = context, state) do
    with {:ok, packet_offsets} <- validate_packet_stream(sdu.octets, context),
         {:ok, framed_stream, start_offsets, next_state} <-
           complete_packet_stream(sdu.octets, packet_offsets, context, state) do
      frames = build_packet_frames(framed_stream, start_offsets, context, next_state)
      {:ok, elem(frames, 0), elem(frames, 1)}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp segment_for_content(sdu, %{data_field_content: :vca_sdu} = context, state) do
    actual = byte_size(sdu.octets)

    if actual == context.max_payload do
      status_fields = Map.get(sdu.meta, :vca_status_fields, 0)

      {frame, next_state} =
        build_frame(sdu.octets, 0, context, state, %{vca_status_fields: status_fields})

      {:ok, [frame], next_state}
    else
      {:error, {:vca_sdu_length_mismatch, actual, context.max_payload}, state}
    end
  end

  defp validate_packet_stream(<<>>, _context), do: {:error, :empty_packet_stream}

  defp validate_packet_stream(packet_stream, %{configuration: nil}) do
    case packet_offsets(packet_stream, SpacePacket.maximum_size()) do
      {:ok, offsets} -> {:ok, offsets}
      {:error, _reason} -> {:ok, [0]}
    end
  end

  defp validate_packet_stream(packet_stream, %{configuration: configuration}) do
    with {:ok, packets, <<>>} <-
           Stream.extract(packet_stream, max_packet_size: configuration.maximum_packet_octets),
         :ok <- validate_packet_versions(packets, configuration.valid_packet_version_numbers) do
      {:ok, cumulative_offsets(packets)}
    else
      {:ok, _packets, rest} -> {:error, {:incomplete_packet_stream, byte_size(rest)}}
      {:error, reason} -> {:error, {:invalid_packet_stream, reason}}
    end
  end

  defp packet_offsets(packet_stream, maximum_packet_octets) do
    case Stream.extract(packet_stream, max_packet_size: maximum_packet_octets) do
      {:ok, packets, <<>>} -> {:ok, cumulative_offsets(packets)}
      {:ok, _packets, rest} -> {:error, {:incomplete_packet_stream, byte_size(rest)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cumulative_offsets(packets) do
    packets
    |> Enum.reduce({[], 0}, fn packet, {offsets, offset} ->
      {[offset | offsets], offset + byte_size(packet)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp validate_packet_versions(packets, valid_versions) do
    invalid =
      Enum.find_value(packets, fn
        <<version::3, _rest::bitstring>> -> if(version in valid_versions, do: nil, else: version)
        _packet -> :invalid
      end)

    if is_nil(invalid), do: :ok, else: {:error, {:invalid_packet_version_number, invalid}}
  end

  defp complete_packet_stream(packet_stream, offsets, context, state) do
    padding_size = Integer.mod(-byte_size(packet_stream), context.max_payload)

    cond do
      padding_size == 0 ->
        {:ok, packet_stream, offsets, state}

      padding_size >= @min_idle_packet_size ->
        {idle_packet, next_state} = idle_packet(padding_size, state)
        {:ok, packet_stream <> idle_packet, offsets ++ [byte_size(packet_stream)], next_state}

      spill_idle_size(padding_size, context.max_payload) <= SpacePacket.maximum_size() ->
        idle_size = spill_idle_size(padding_size, context.max_payload)
        {idle_packet, next_state} = idle_packet(idle_size, state)
        {:ok, packet_stream <> idle_packet, offsets ++ [byte_size(packet_stream)], next_state}

      true ->
        {:error, {:idle_packet_spill_exceeds_maximum, context.max_payload, padding_size}}
    end
  end

  defp spill_idle_size(padding_size, max_payload) do
    additional_frames = ceil_div(@min_idle_packet_size - padding_size, max_payload)
    padding_size + additional_frames * max_payload
  end

  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)

  defp idle_packet(size, %{idle_padding_cache: cache} = state) do
    case Map.fetch(cache, size) do
      {:ok, packet} ->
        {packet, state}

      :error ->
        packet = Idle.encode!(size)
        {packet, %{state | idle_padding_cache: Map.put(cache, size, packet)}}
    end
  end

  defp build_packet_frames(stream, packet_start_offsets, context, state) do
    max_payload = context.max_payload
    chunks = for <<chunk::binary-size(^max_payload) <- stream>>, do: chunk

    Enum.with_index(chunks)
    |> Enum.reduce({[], state}, fn {payload, index}, {frames, current_state} ->
      frame_start = index * context.max_payload
      fhp = first_header_pointer(packet_start_offsets, frame_start, context.max_payload)
      {frame, next_state} = build_frame(payload, fhp, context, current_state, %{})
      {[frame | frames], next_state}
    end)
    |> then(fn {frames, next_state} -> {Enum.reverse(frames), next_state} end)
  end

  defp first_header_pointer(offsets, frame_start, frame_length) do
    frame_end = frame_start + frame_length

    case Enum.find(offsets, &(&1 >= frame_start and &1 < frame_end)) do
      nil -> 2047
      packet_start -> packet_start - frame_start
    end
  end

  defp build_frame(payload, fhp, context, state, extra_meta) do
    {mcfc, vcfc} = current_counters(state, context)
    sync_flag = if(context.data_field_content == :packets, do: 0, else: 1)
    vca_status_fields = Map.get(extra_meta, :vca_status_fields)

    status_meta =
      if sync_flag == 1 do
        %{sync_flag: 1, vca_status_fields: vca_status_fields, fhp: fhp}
      else
        %{sync_flag: 0, packet_order_flag: 0, segment_length_id: 3, fhp: fhp}
      end

    meta =
      %{
        mcfc: mcfc,
        vcfc: vcfc,
        ocf_flag: if(present_binary?(context.ocf), do: 1, else: 0),
        secondary_header_flag: if(context.secondary_header, do: 1, else: 0),
        secondary_header: context.secondary_header,
        data_field_content: context.data_field_content,
        fecf_present: context.fecf?
      }
      |> Map.merge(status_meta)
      |> Map.merge(extra_meta)

    frame = %LinkFrame{
      profile: :tm,
      scid: context.scid,
      vcid: context.vcid,
      map_id: nil,
      frame_seq: vcfc,
      payload_octets: payload,
      quality: :good,
      ocf: context.ocf,
      timestamp: context.timestamp,
      meta: meta
    }

    {frame, increment_counters(state, context, mcfc, vcfc)}
  end

  defp current_counters(state, context) do
    master_key = master_channel_key(context)
    virtual_key = virtual_channel_key(context)

    {
      Map.get(state.mcfc_by_master_channel, master_key, state.initial_mcfc),
      Map.get(state.vcfc_by_virtual_channel, virtual_key, state.initial_vcfc)
    }
  end

  defp increment_counters(state, context, mcfc, vcfc) do
    next_mcfc = increment_counter(mcfc)
    next_vcfc = increment_counter(vcfc)

    %{
      state
      | mcfc: next_mcfc,
        vcfc: next_vcfc,
        mcfc_by_master_channel:
          Map.put(state.mcfc_by_master_channel, master_channel_key(context), next_mcfc),
        vcfc_by_virtual_channel:
          Map.put(state.vcfc_by_virtual_channel, virtual_channel_key(context), next_vcfc)
    }
  end

  defp master_channel_key(context), do: {0, context.scid}
  defp virtual_channel_key(context), do: {0, context.scid, context.vcid}
  defp increment_counter(value), do: Integer.mod(value + 1, 256)

  defp encode_frames(frames, context, opts) do
    Enum.reduce_while(frames, {:ok, []}, fn frame, {:ok, encoded} ->
      case FrameCodec.encode(frame, codec_options(context, opts)) do
        {:ok, bytes} -> {:cont, {:ok, [bytes | encoded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, encoded |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _reason} = error -> error
    end
  end

  defp codec_options(%{configuration: %Configuration{} = configuration}, opts) do
    Keyword.put(opts, :configuration, configuration)
  end

  defp codec_options(context, opts) do
    opts
    |> Keyword.put(:frame_size, context.frame_size)
    |> Keyword.put(:secondary_header_length, context.secondary_header_length)
    |> Keyword.put(:ocf_length, context.ocf_length)
    |> Keyword.put(:fecf, context.fecf?)
  end

  defp build_frame_context(sdu, %{configuration: %Configuration{} = configuration} = ctx) do
    with :ok <- Configuration.validate(configuration),
         :ok <- validate_sdu_address(sdu, configuration.scid, configuration.vcid),
         {:ok, secondary_header} <- normalize_secondary_header(sdu, ctx),
         :ok <- validate_managed_secondary_header(secondary_header, configuration),
         {:ok, ocf} <- normalize_ocf(ctx),
         :ok <- validate_managed_ocf(ocf, configuration) do
      {:ok,
       %{
         configuration: configuration,
         frame_size: configuration.frame_size,
         max_payload: Configuration.maximum_data_field_octets(configuration),
         scid: configuration.scid,
         vcid: configuration.vcid,
         fecf?: configuration.fecf?,
         data_field_content: configuration.data_field_content,
         secondary_header: secondary_header,
         secondary_header_length: configuration.secondary_header_length,
         ocf: ocf,
         ocf_length: if(Configuration.ocf?(configuration), do: @ocf_size, else: 0),
         timestamp: sdu.timestamp
       }}
    end
  end

  defp build_frame_context(sdu, ctx) do
    frame_size = Map.get(ctx, :frame_size)
    scid = sdu.scid || Map.get(ctx, :scid, 0)
    vcid = sdu.vcid || Map.get(ctx, :vcid, 0)
    fecf? = Map.get(ctx, :fecf, false)
    data_field_content = Map.get(ctx, :data_field_content, infer_content(sdu.sdu_kind_hint))

    with :ok <- validate_frame_size(frame_size),
         :ok <- validate_address(scid, vcid),
         :ok <- validate_fecf_presence(fecf?),
         :ok <- validate_content(data_field_content),
         {:ok, secondary_header} <- normalize_secondary_header(sdu, ctx),
         {:ok, secondary_header_length} <- legacy_secondary_header_length(secondary_header, ctx),
         {:ok, ocf} <- normalize_ocf(ctx),
         {:ok, ocf_length} <- legacy_ocf_length(ocf, ctx),
         max_payload =
           frame_size - @primary_header_size - secondary_header_length - ocf_length -
             fecf_length_bytes(fecf?),
         :ok <- validate_payload_capacity(max_payload, data_field_content) do
      {:ok,
       %{
         configuration: nil,
         frame_size: frame_size,
         max_payload: max_payload,
         scid: scid,
         vcid: vcid,
         fecf?: fecf?,
         data_field_content: data_field_content,
         secondary_header: secondary_header,
         secondary_header_length: secondary_header_length,
         ocf: ocf,
         ocf_length: ocf_length,
         timestamp: sdu.timestamp
       }}
    end
  end

  defp normalize_secondary_header(sdu, ctx) do
    value = Map.get(ctx, :secondary_header, Map.get(sdu.meta || %{}, :secondary_header))

    case value do
      nil ->
        {:ok, nil}

      %SecondaryHeader{} = header ->
        case SecondaryHeader.encode(header) do
          {:ok, _encoded} -> {:ok, header}
          {:error, _reason} = error -> error
        end

      data when is_binary(data) ->
        SecondaryHeader.new(data)

      other ->
        {:error, {:invalid_secondary_header, other}}
    end
  end

  defp legacy_secondary_header_length(nil, ctx) do
    case Map.get(ctx, :secondary_header_length, 0) do
      0 -> {:ok, 0}
      length -> {:error, {:missing_managed_secondary_header, length}}
    end
  end

  defp legacy_secondary_header_length(%SecondaryHeader{} = header, ctx) do
    actual = SecondaryHeader.encoded_length(header)
    expected = Map.get(ctx, :secondary_header_length, actual)

    if actual == expected,
      do: {:ok, actual},
      else: {:error, {:secondary_header_length_mismatch, actual, expected}}
  end

  defp normalize_ocf(ctx) do
    case Map.get(ctx, :ocf) do
      nil -> {:ok, nil}
      <<>> -> {:ok, nil}
      ocf when is_binary(ocf) -> {:ok, ocf}
      value -> {:error, {:invalid_ocf, value}}
    end
  end

  defp legacy_ocf_length(nil, ctx) do
    case Map.get(ctx, :ocf_length, 0) do
      0 -> {:ok, 0}
      _length -> {:ok, 0}
    end
  end

  defp legacy_ocf_length(ocf, ctx) do
    actual = byte_size(ocf)
    expected = Map.get(ctx, :ocf_length, actual)

    if actual == expected,
      do: {:ok, actual},
      else: {:error, {:invalid_ocf_length, actual, expected}}
  end

  defp validate_managed_secondary_header(nil, %Configuration{} = configuration) do
    if Configuration.secondary_header?(configuration),
      do: {:error, :missing_managed_secondary_header},
      else: :ok
  end

  defp validate_managed_secondary_header(%SecondaryHeader{} = header, configuration) do
    actual = SecondaryHeader.encoded_length(header)

    cond do
      not Configuration.secondary_header?(configuration) ->
        {:error, :unexpected_secondary_header}

      actual != configuration.secondary_header_length ->
        {:error,
         {:secondary_header_length_mismatch, actual, configuration.secondary_header_length}}

      true ->
        :ok
    end
  end

  defp validate_managed_ocf(nil, configuration) do
    if Configuration.ocf?(configuration), do: {:error, :missing_ocf}, else: :ok
  end

  defp validate_managed_ocf(ocf, configuration) do
    cond do
      not Configuration.ocf?(configuration) -> {:error, :unexpected_ocf}
      byte_size(ocf) != @ocf_size -> {:error, {:invalid_ocf_length, byte_size(ocf), @ocf_size}}
      true -> :ok
    end
  end

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %{data_field_content: :packets})
       when hint in [nil, :space_packet, :virtual_channel_packet],
       do: :ok

  defp validate_sdu_kind(%SDUOctets{sdu_kind_hint: hint}, %{data_field_content: :vca_sdu})
       when hint in [:vca_sdu, :virtual_channel_access],
       do: :ok

  defp validate_sdu_kind(sdu, context),
    do: {:error, {:sdu_kind_mismatch, sdu.sdu_kind_hint, context.data_field_content}}

  defp require_packet_channel(%{data_field_content: :packets}), do: :ok
  defp require_packet_channel(context), do: {:error, {:oid_forbidden, context.data_field_content}}

  defp infer_content(hint) when hint in [:vca_sdu, :virtual_channel_access], do: :vca_sdu
  defp infer_content(_hint), do: :packets

  defp validate_sdu_address(sdu, scid, vcid) do
    if (is_nil(sdu.scid) or sdu.scid == scid) and (is_nil(sdu.vcid) or sdu.vcid == vcid),
      do: :ok,
      else: {:error, {:managed_channel_mismatch, sdu.scid, sdu.vcid}}
  end

  defp validate_address(scid, vcid)
       when is_integer(scid) and scid in 0..1023 and is_integer(vcid) and vcid in 0..7,
       do: :ok

  defp validate_address(scid, vcid), do: {:error, {:invalid_tm_address, scid, vcid}}

  defp validate_frame_size(frame_size)
       when is_integer(frame_size) and frame_size > @primary_header_size,
       do: :ok

  defp validate_frame_size(frame_size), do: {:error, {:invalid_frame_size, frame_size}}

  defp validate_content(content) when content in [:packets, :vca_sdu], do: :ok
  defp validate_content(content), do: {:error, {:invalid_data_field_content, content}}

  defp validate_payload_capacity(capacity, :packets) when capacity > 0, do: :ok

  defp validate_payload_capacity(capacity, :vca_sdu) when capacity > 0, do: :ok

  defp validate_payload_capacity(capacity, content),
    do: {:error, {:data_field_too_small, content, capacity}}

  defp validate_fecf_presence(value) when is_boolean(value), do: :ok
  defp validate_fecf_presence(value), do: {:error, {:invalid_fecf_presence, value}}

  defp fecf_length_bytes(true), do: FrameErrorControl.size()
  defp fecf_length_bytes(false), do: 0

  defp validate_counter(value, _field) when is_integer(value) and value in 0..255, do: :ok
  defp validate_counter(value, field), do: {:error, {:invalid_counter, field, value}}

  defp present_binary?(value), do: is_binary(value) and byte_size(value) > 0
end
