defmodule CCSDS.SDLP.USLP.Reassembly do
  @moduledoc """
  Pure receiving-end USLP MAP and Virtual Channel reception.

  Reception applies QoS-specific frame continuity, fixed-frame FHP/LVO
  processing, variable-frame segment reassembly, Packet Version Number format
  management, octet-stream delivery, protocol-control delivery, continuous OID
  validation, and synchronous OCF/Insert extraction.
  """

  @behaviour CCSDS.SDLP.Reassembly

  alias CCSDS.Core.{LinkFrame, SDUOctets}
  alias CCSDS.Packet.Format, as: PacketFormat
  alias CCSDS.SDLP.USLP.{Configuration, Continuity, OnlyIdleData}

  @impl true
  def init(opts \\ []) when is_list(opts) do
    configurations = Keyword.get(opts, :configurations, [])
    oid_validation = Keyword.get(opts, :oid_validation, :full)

    with :ok <- Configuration.validate_plan(configurations),
         true <- oid_validation in [:none, :full] do
      {:ok,
       %{
         configurations: Map.new(configurations, &{Configuration.physical_address(&1), &1}),
         continuity: Continuity.init(),
         segment_buffers: %{},
         packet_buffers: %{},
         oid_validation: oid_validation,
         oid_lfsr_by_physical_channel: %{}
       }}
    else
      false -> {:error, {:invalid_oid_validation, oid_validation}}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def ingest(%LinkFrame{profile: :uslp} = frame, ctx, state) do
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
  def ingest_detailed(%LinkFrame{profile: :uslp} = frame, ctx, state)
      when is_map(ctx) and is_map(state) do
    with {:ok, configuration} <- fetch_configuration(frame, state),
         :ok <- validate_managed_frame(frame, configuration),
         {:ok, continuity, next_continuity} <- Continuity.observe(frame, state.continuity) do
      state = %{state | continuity: next_continuity}
      {partial, loss_anomalies, state} = handle_loss(frame, configuration, continuity, ctx, state)

      case dispatch(frame, configuration, continuity, ctx, state) do
        {:ok, sdus, anomalies, next_state} ->
          {:ok, partial ++ sdus ++ auxiliary_sdus(frame, configuration, continuity, ctx),
           continuity.anomalies ++ loss_anomalies ++ anomalies, next_state}

        {:error, reason, anomalies, next_state} ->
          {:error, reason, continuity.anomalies ++ loss_anomalies ++ anomalies, next_state}
      end
    else
      {:error, reason} -> {:error, reason, [], state}
    end
  end

  def ingest_detailed(%LinkFrame{profile: profile}, _ctx, state),
    do: {:error, {:invalid_profile, profile}, [], state}

  @spec stats(map()) :: map()
  def stats(state) do
    %{
      buffered_segments: map_size(state.segment_buffers),
      buffered_packets: map_size(state.packet_buffers),
      buffered_octets:
        Enum.sum_by(Map.values(state.segment_buffers), &byte_size(&1.bytes)) +
          Enum.sum_by(Map.values(state.packet_buffers), &byte_size(&1.bytes)),
      observed_virtual_channels: map_size(state.continuity.counts),
      observed_oid_physical_channels: map_size(state.oid_lfsr_by_physical_channel)
    }
  end

  defp dispatch(frame, configuration, continuity, ctx, state) do
    case configuration.data_field_content do
      :packets ->
        receive_packets(frame, configuration, continuity, ctx, state)

      content when content in [:mapa_sdu, :vca_sdu] ->
        receive_access(frame, configuration, continuity, ctx, state)

      :octet_stream ->
        deliver_octet_stream(frame, configuration, continuity, ctx, state)

      :protocol_control ->
        deliver_protocol_control(frame, configuration, continuity, ctx, state)

      :idle_data ->
        validate_oid(frame, configuration, state)
    end
  end

  defp receive_packets(
         frame,
         %Configuration{frame_type: :fixed} = configuration,
         continuity,
         ctx,
         state
       ) do
    pointer = Map.get(frame.meta, :tfdf_pointer)
    key = buffer_key(frame)

    cond do
      pointer == 0xFFFF ->
        continue_fixed_packet(frame, configuration, continuity, ctx, key, state)

      is_integer(pointer) and pointer >= 0 and pointer < byte_size(frame.payload_octets) ->
        <<prefix::binary-size(^pointer), suffix::binary>> = frame.payload_octets

        with {:ok, continued, anomalies, state} <-
               finish_fixed_continuation(prefix, frame, configuration, key, state),
             {:ok, packets, remaining} <- extract_packets(suffix, configuration),
             state <- put_packet_remainder(state, key, remaining, frame) do
          sdus = packet_sdus(continued ++ packets, frame, configuration, continuity, ctx)
          {:ok, sdus, anomalies, state}
        else
          {:error, reason} -> {:error, reason, [], clear_packet(state, key)}
        end

      true ->
        {:error, {:invalid_uslp_first_header_pointer, pointer}, [], clear_packet(state, key)}
    end
  end

  defp receive_packets(frame, configuration, continuity, ctx, state) do
    rule = Map.get(frame.meta, :construction_rule)
    key = buffer_key(frame)

    case rule do
      :unsegmented ->
        case extract_packets(frame.payload_octets, configuration) do
          {:ok, packets, <<>>} ->
            {:ok, packet_sdus(packets, frame, configuration, continuity, ctx), [],
             clear_segment(state, key)}

          {:ok, _packets, remaining} ->
            {:error, {:incomplete_uslp_packet_data, byte_size(remaining)}, [],
             clear_segment(state, key)}

          {:error, reason} ->
            {:error, reason, [], clear_segment(state, key)}
        end

      :start_segment ->
        start_segment(frame, key, state)

      :continue_segment ->
        continue_segment(frame, key, state)

      :last_segment ->
        finish_packet_segment(frame, configuration, continuity, ctx, key, state)

      other ->
        {:error, {:invalid_packet_construction_rule, other}, [], clear_segment(state, key)}
    end
  end

  defp continue_fixed_packet(frame, configuration, continuity, ctx, key, state) do
    case Map.get(state.packet_buffers, key) do
      nil ->
        anomaly =
          anomaly(:orphan_packet_continuation, frame, %{
            discarded_octets: byte_size(frame.payload_octets)
          })

        {:ok, [], [anomaly], state}

      entry ->
        combined = entry.bytes <> frame.payload_octets
        source_frames = add_frame(entry, frame)

        case extract_packets(combined, configuration) do
          {:ok, packets, <<>>} ->
            {:ok, packet_sdus(packets, frame, configuration, continuity, ctx, source_frames), [],
             clear_packet(state, key)}

          {:ok, packets, remaining} ->
            updated = %{bytes: remaining, source_frames: source_frames}
            next_state = %{state | packet_buffers: Map.put(state.packet_buffers, key, updated)}

            {:ok, packet_sdus(packets, frame, configuration, continuity, ctx, source_frames), [],
             next_state}

          {:error, reason} ->
            {:error, reason, [], clear_packet(state, key)}
        end
    end
  end

  defp finish_fixed_continuation(<<>>, frame, _configuration, key, state) do
    case Map.get(state.packet_buffers, key) do
      nil ->
        {:ok, [], [], state}

      entry ->
        anomaly =
          anomaly(:first_header_pointer_resynchronization, frame, %{
            discarded_octets: byte_size(entry.bytes)
          })

        {:ok, [], [anomaly], clear_packet(state, key)}
    end
  end

  defp finish_fixed_continuation(prefix, frame, configuration, key, state) do
    case Map.get(state.packet_buffers, key) do
      nil ->
        anomaly =
          anomaly(:orphan_packet_continuation, frame, %{discarded_octets: byte_size(prefix)})

        {:ok, [], [anomaly], state}

      entry ->
        case extract_packets(entry.bytes <> prefix, configuration) do
          {:ok, packets, <<>>} ->
            {:ok, packets, [], clear_packet(state, key)}

          {:ok, _packets, remaining} ->
            {:error, {:first_header_pointer_did_not_complete_packet, byte_size(remaining)}}

          {:error, _reason} = error ->
            error
        end
    end
  end

  defp finish_packet_segment(frame, configuration, continuity, ctx, key, state) do
    case Map.get(state.segment_buffers, key) do
      nil ->
        anomaly =
          anomaly(:orphan_last_segment, frame, %{
            discarded_octets: byte_size(frame.payload_octets)
          })

        {:ok, [], [anomaly], state}

      entry ->
        bytes = entry.bytes <> frame.payload_octets

        with {:ok, packets, <<>>} <- extract_packets(bytes, configuration),
             true <- length(packets) == 1 do
          source_frames = Enum.uniq(entry.source_frames ++ [frame.frame_seq])
          sdus = packet_sdus(packets, frame, configuration, continuity, ctx, source_frames)
          {:ok, sdus, [], clear_segment(state, key)}
        else
          false ->
            {:error, :segmented_uslp_packet_must_contain_one_packet, [],
             clear_segment(state, key)}

          {:ok, _packets, remaining} ->
            {:error, {:incomplete_segmented_uslp_packet, byte_size(remaining)}, [],
             clear_segment(state, key)}

          {:error, reason} ->
            {:error, reason, [], clear_segment(state, key)}
        end
    end
  end

  defp receive_access(
         frame,
         %Configuration{frame_type: :fixed} = configuration,
         continuity,
         ctx,
         state
       ) do
    rule = Map.get(frame.meta, :construction_rule)
    pointer = Map.get(frame.meta, :tfdf_pointer)
    key = buffer_key(frame)

    cond do
      rule == :start_access_sdu ->
        state = clear_segment(state, key)
        fixed_access_portion(frame, configuration, continuity, ctx, key, pointer, state)

      rule == :continue_access_sdu and Map.has_key?(state.segment_buffers, key) ->
        fixed_access_portion(frame, configuration, continuity, ctx, key, pointer, state)

      rule == :continue_access_sdu ->
        anomaly =
          anomaly(:orphan_access_continuation, frame, %{
            discarded_octets: byte_size(frame.payload_octets)
          })

        {:ok, [], [anomaly], state}

      true ->
        {:error, {:invalid_access_construction_rule, rule}, [], clear_segment(state, key)}
    end
  end

  defp receive_access(frame, configuration, continuity, ctx, state) do
    rule = Map.get(frame.meta, :construction_rule)
    key = buffer_key(frame)

    case rule do
      :unsegmented ->
        {:ok, [access_sdu(frame.payload_octets, frame, configuration, continuity, ctx)], [],
         clear_segment(state, key)}

      :start_segment ->
        start_segment(frame, key, state)

      :continue_segment ->
        continue_segment(frame, key, state)

      :last_segment ->
        finish_access_segment(frame, configuration, continuity, ctx, key, state)

      other ->
        {:error, {:invalid_access_construction_rule, other}, [], clear_segment(state, key)}
    end
  end

  defp fixed_access_portion(frame, configuration, continuity, ctx, key, pointer, state) do
    entry = Map.get(state.segment_buffers, key, %{bytes: <<>>, source_frames: []})

    cond do
      pointer == 0xFFFF ->
        updated = %{
          entry
          | bytes: entry.bytes <> frame.payload_octets,
            source_frames: add_frame(entry, frame)
        }

        {:ok, [], [], %{state | segment_buffers: Map.put(state.segment_buffers, key, updated)}}

      is_integer(pointer) and pointer >= 0 and pointer < byte_size(frame.payload_octets) ->
        valid_octets = pointer + 1
        <<valid::binary-size(^valid_octets), _idle::binary>> = frame.payload_octets
        bytes = entry.bytes <> valid
        source_frames = Enum.uniq(entry.source_frames ++ [frame.frame_seq])
        sdu = access_sdu(bytes, frame, configuration, continuity, ctx, source_frames)
        {:ok, [sdu], [], clear_segment(state, key)}

      true ->
        {:error, {:invalid_uslp_last_valid_octet_pointer, pointer}, [], clear_segment(state, key)}
    end
  end

  defp start_segment(frame, key, state) do
    anomaly =
      case Map.get(state.segment_buffers, key) do
        nil -> []
        entry -> [anomaly(:segment_restart, frame, %{discarded_octets: byte_size(entry.bytes)})]
      end

    entry = %{bytes: frame.payload_octets, source_frames: [frame.frame_seq]}
    {:ok, [], anomaly, %{state | segment_buffers: Map.put(state.segment_buffers, key, entry)}}
  end

  defp continue_segment(frame, key, state) do
    case Map.get(state.segment_buffers, key) do
      nil ->
        anomaly =
          anomaly(:orphan_continuing_segment, frame, %{
            discarded_octets: byte_size(frame.payload_octets)
          })

        {:ok, [], [anomaly], state}

      entry ->
        updated = %{
          entry
          | bytes: entry.bytes <> frame.payload_octets,
            source_frames: add_frame(entry, frame)
        }

        {:ok, [], [], %{state | segment_buffers: Map.put(state.segment_buffers, key, updated)}}
    end
  end

  defp finish_access_segment(frame, configuration, continuity, ctx, key, state) do
    case Map.get(state.segment_buffers, key) do
      nil ->
        anomaly =
          anomaly(:orphan_last_segment, frame, %{
            discarded_octets: byte_size(frame.payload_octets)
          })

        {:ok, [], [anomaly], state}

      entry ->
        bytes = entry.bytes <> frame.payload_octets
        source_frames = Enum.uniq(entry.source_frames ++ [frame.frame_seq])
        sdu = access_sdu(bytes, frame, configuration, continuity, ctx, source_frames)
        {:ok, [sdu], [], clear_segment(state, key)}
    end
  end

  defp deliver_octet_stream(frame, configuration, continuity, ctx, state) do
    if Map.get(frame.meta, :construction_rule) == :octet_stream do
      sdu =
        sdu(
          frame.payload_octets,
          :octet_stream,
          frame,
          configuration,
          continuity,
          ctx,
          [frame.frame_seq],
          %{
            octet_stream_data_loss_flag: continuity.loss?
          }
        )

      {:ok, [sdu], [], state}
    else
      {:error, {:invalid_octet_stream_construction_rule, Map.get(frame.meta, :construction_rule)},
       [], state}
    end
  end

  defp deliver_protocol_control(frame, configuration, continuity, ctx, state) do
    if Map.get(frame.meta, :protocol_control?, false) and
         Map.get(frame.meta, :construction_rule) == :unsegmented do
      sdu =
        sdu(
          frame.payload_octets,
          :protocol_control,
          frame,
          configuration,
          continuity,
          ctx,
          [frame.frame_seq],
          %{
            upid: configuration.upid
          }
        )

      {:ok, [sdu], [], state}
    else
      {:error, :invalid_uslp_protocol_control_frame, [], state}
    end
  end

  defp validate_oid(frame, configuration, state) do
    if state.oid_validation == :none do
      {:ok, [], [], state}
    else
      lfsr =
        Map.get(
          state.oid_lfsr_by_physical_channel,
          configuration.physical_channel,
          OnlyIdleData.initial_state()
        )

      case OnlyIdleData.validate(frame.payload_octets, lfsr) do
        {:ok, next_lfsr} ->
          next_state = %{
            state
            | oid_lfsr_by_physical_channel:
                Map.put(
                  state.oid_lfsr_by_physical_channel,
                  configuration.physical_channel,
                  next_lfsr
                )
          }

          {:ok, [], [], next_state}

        {:error, reason} ->
          {:error, reason, [anomaly(:invalid_only_idle_data, frame, %{reason: reason})], state}
      end
    end
  end

  defp extract_packets(data, configuration), do: do_extract_packets(data, configuration, [])
  defp do_extract_packets(<<>>, _configuration, packets), do: {:ok, Enum.reverse(packets), <<>>}

  defp do_extract_packets(data, configuration, packets) do
    with {:ok, pvn} <- PacketFormat.packet_version_number(data),
         true <-
           pvn in configuration.packet_configuration.valid_packet_version_numbers or
             idle_packet_prefix?(data),
         {:ok, format} <- packet_format(pvn, configuration, data) do
      case PacketFormat.total_packet_octets(data, format) do
        {:ok, octets} when octets > configuration.packet_configuration.maximum_packet_octets ->
          {:error,
           {:packet_size_exceeds_managed_maximum, octets,
            configuration.packet_configuration.maximum_packet_octets}}

        {:ok, octets} when byte_size(data) >= octets ->
          <<packet::binary-size(^octets), rest::binary>> = data
          accumulate_packet(packet, rest, configuration, packets)

        {:ok, _octets} ->
          {:ok, Enum.reverse(packets), data}

        {:error, {:truncated_packet_length_field, _required, _actual}} ->
          {:ok, Enum.reverse(packets), data}

        {:error, _reason} = error ->
          error
      end
    else
      false -> {:error, {:unsupported_packet_version_number, packet_pvn(data)}}
      {:error, _reason} = error -> error
    end
  end

  defp accumulate_packet(packet, rest, configuration, packets) do
    next_packets = if(idle_packet?(packet), do: packets, else: [packet | packets])
    do_extract_packets(rest, configuration, next_packets)
  end

  defp packet_format(0, configuration, data) do
    if idle_packet_prefix?(data),
      do: {:ok, Map.get(configuration.packet_configuration.formats, 0, %PacketFormat{})},
      else: fetch_packet_format(0, configuration)
  end

  defp packet_format(pvn, configuration, _data), do: fetch_packet_format(pvn, configuration)

  defp fetch_packet_format(pvn, configuration) do
    case Map.fetch(configuration.packet_configuration.formats, pvn) do
      {:ok, format} -> {:ok, format}
      :error -> {:error, {:missing_packet_format, pvn}}
    end
  end

  defp idle_packet_prefix?(<<0::3, _type::1, _secondary::1, 0x7FF::11, _rest::bitstring>>),
    do: true

  defp idle_packet_prefix?(_data), do: false
  defp idle_packet?(packet), do: idle_packet_prefix?(packet)
  defp packet_pvn(<<pvn::3, _rest::bitstring>>), do: pvn
  defp packet_pvn(_data), do: :truncated

  defp packet_sdus(packets, frame, configuration, continuity, ctx, source_frames \\ nil) do
    source_frames = source_frames || [frame.frame_seq]

    Enum.map(packets, fn packet ->
      <<pvn::3, _rest::bitstring>> = packet

      sdu(
        packet,
        packet_kind(configuration),
        frame,
        configuration,
        continuity,
        ctx,
        source_frames,
        %{
          packet_version_number: pvn,
          packet_quality_indicator: not continuity.loss?
        }
      )
    end)
  end

  defp packet_kind(%Configuration{packet_service: :virtual_channel}), do: :virtual_channel_packet
  defp packet_kind(%Configuration{}), do: :map_packet

  defp access_sdu(bytes, frame, configuration, continuity, ctx, source_frames \\ nil) do
    kind = if(configuration.data_field_content == :vca_sdu, do: :vca_sdu, else: :mapa_sdu)
    flag = if(kind == :vca_sdu, do: :vca_sdu_loss_flag, else: :mapa_sdu_loss_flag)

    sdu(bytes, kind, frame, configuration, continuity, ctx, source_frames || [frame.frame_seq], %{
      flag => continuity.loss?
    })
  end

  defp auxiliary_sdus(frame, configuration, continuity, ctx) do
    insert = Map.get(frame.meta, :insert_zone)

    []
    |> maybe_auxiliary(insert, :insert, frame, configuration, continuity, ctx, %{
      in_sdu_loss_flag: continuity.loss?
    })
    |> maybe_auxiliary(frame.ocf, :operational_control, frame, configuration, continuity, ctx, %{
      ocf_sdu_loss_flag: continuity.loss?
    })
  end

  defp maybe_auxiliary(sdus, value, _kind, _frame, _configuration, _continuity, _ctx, _meta)
       when value in [nil, <<>>],
       do: sdus

  defp maybe_auxiliary(sdus, value, kind, frame, configuration, continuity, ctx, meta) do
    sdus ++ [sdu(value, kind, frame, configuration, continuity, ctx, [frame.frame_seq], meta)]
  end

  defp sdu(bytes, kind, frame, configuration, continuity, ctx, source_frames, meta) do
    %SDUOctets{
      profile: :uslp,
      scid: frame.scid,
      vcid: frame.vcid,
      map_id: frame.map_id,
      direction: Map.get(ctx, :direction, :downlink),
      sdu_kind_hint: kind,
      octets: bytes,
      quality: if(continuity.loss?, do: :suspect, else: frame.quality),
      source_frames: source_frames,
      timestamp: frame.timestamp,
      meta:
        meta
        |> Map.put(:physical_channel, configuration.physical_channel)
        |> Map.put(:qos, continuity.qos)
        |> Map.put(:verification_status_code, Map.get(ctx, :verification_status_code))
    }
  end

  defp handle_loss(_frame, _configuration, %{loss?: false}, _ctx, state), do: {[], [], state}

  defp handle_loss(frame, configuration, continuity, ctx, state) do
    key = buffer_key(frame)
    packet_entry = Map.get(state.packet_buffers, key)
    segment_entry = Map.get(state.segment_buffers, key)
    entry = packet_entry || segment_entry

    partial =
      if entry && configuration.data_field_content == :packets &&
           configuration.packet_configuration.deliver_incomplete? do
        [
          sdu(
            entry.bytes,
            packet_kind(configuration),
            frame,
            configuration,
            continuity,
            ctx,
            entry.source_frames,
            %{
              packet_quality_indicator: false,
              incomplete?: true
            }
          )
        ]
      else
        []
      end

    anomalies =
      if entry do
        [
          anomaly(:partial_sdu_discarded_on_frame_loss, frame, %{
            discarded_octets: byte_size(entry.bytes)
          })
        ]
      else
        []
      end

    {partial, anomalies, state |> clear_packet(key) |> clear_segment(key)}
  end

  defp fetch_configuration(frame, state) do
    physical = Map.get(frame.meta, :physical_channel, "default")

    case Map.fetch(state.configurations, {physical, frame.scid, frame.vcid, frame.map_id}) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:unknown_uslp_channel, physical, frame.scid, frame.vcid, frame.map_id}}
    end
  end

  defp validate_managed_frame(frame, configuration) do
    with true <- frame.scid == configuration.scid,
         true <- frame.vcid == configuration.vcid,
         true <- frame.map_id == configuration.map_id,
         true <- Map.get(frame.meta, :upid) == configuration.upid do
      :ok
    else
      false -> {:error, :uslp_frame_managed_parameter_mismatch}
    end
  end

  defp buffer_key(frame) do
    {Map.get(frame.meta, :physical_channel, "default"), frame.scid, frame.vcid, frame.map_id,
     Map.get(frame.meta, :qos)}
  end

  defp put_packet_remainder(state, key, <<>>, _frame), do: clear_packet(state, key)

  defp put_packet_remainder(state, key, remaining, frame) do
    entry = %{bytes: remaining, source_frames: [frame.frame_seq]}
    %{state | packet_buffers: Map.put(state.packet_buffers, key, entry)}
  end

  defp clear_packet(state, key),
    do: %{state | packet_buffers: Map.delete(state.packet_buffers, key)}

  defp clear_segment(state, key),
    do: %{state | segment_buffers: Map.delete(state.segment_buffers, key)}

  defp add_frame(entry, frame), do: Enum.uniq(entry.source_frames ++ [frame.frame_seq])

  defp anomaly(kind, frame, metadata) do
    %{
      anomaly_kind: kind,
      scid: frame.scid,
      vcid: frame.vcid,
      map_id: frame.map_id,
      frame_seq: frame.frame_seq,
      metadata: metadata
    }
  end
end
