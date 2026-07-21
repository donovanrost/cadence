defmodule Cadence.CCSDS.SDLP.TM.Reassembly do
  @moduledoc """
  Pure receiving-end TM Virtual Channel reception and Packet extraction.

  Reassembly is independently keyed by GVCID, observes both MCFC and VCFC
  continuity, validates OID PN data when configured, delivers VCA_SDUs with a
  loss flag, and reports resynchronization or discarded partial data as
  protocol-native anomaly evidence.
  """

  @behaviour Cadence.CCSDS.SDLP.Reassembly

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}
  alias Cadence.CCSDS.SDLP.TM.{Configuration, Continuity, OnlyIdleData, SecondaryHeader}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec
  alias Cadence.CCSDS.SpacePacket.Stream

  @default_oid_validation :none
  @default_oid_prefix_bytes 10

  @impl true
  def init(opts) when is_list(opts) do
    with {:ok, configurations} <- normalize_configurations(opts),
         {:ok, oid_validation} <-
           normalize_oid_validation(Keyword.get(opts, :oid_validation, @default_oid_validation)),
         {:ok, oid_prefix_bytes} <-
           normalize_oid_prefix_bytes(
             Keyword.get(opts, :oid_validation_prefix_bytes, @default_oid_prefix_bytes)
           ) do
      {:ok,
       %{
         configurations: configurations,
         continuity: Continuity.init(),
         scid_target_map: Keyword.get(opts, :scid_target_map, %{}),
         default_target_id: Keyword.get(opts, :default_target_id),
         vcid_target_map: Keyword.get(opts, :vcid_target_map, %{}),
         default_vcid_map: Keyword.get(opts, :default_vcid_map, %{}),
         oid_validation: oid_validation,
         oid_validation_prefix_bytes: oid_prefix_bytes,
         oid_lfsr_by_virtual_channel: %{},
         default_sdu_type: normalize_sdu_kind_hint(Keyword.get(opts, :default_sdu_type)),
         max_space_packet_size:
           Keyword.get(opts, :max_space_packet_size, SpacePacket.maximum_size()),
         packet_buffers_by_channel: %{},
         continuation_by_channel: %{}
       }}
    end
  end

  @impl true
  def ingest(%LinkFrame{profile: :tm} = frame, ctx, state) do
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
  def ingest_detailed(%LinkFrame{profile: :tm} = frame, ctx, state)
      when is_map(ctx) and is_map(state) do
    with {:ok, configuration} <- fetch_configuration(frame, state),
         :ok <- validate_managed_frame(frame, configuration),
         {:ok, continuity_report, next_continuity} <-
           Continuity.observe(frame, state.continuity) do
      state = %{state | continuity: next_continuity}

      {loss_sdus, loss_anomalies, state} =
        handle_virtual_channel_loss(frame, ctx, configuration, continuity_report, state)

      case dispatch_frame(frame, ctx, configuration, continuity_report, state) do
        {:ok, sdus, anomalies, final_state} ->
          {:ok, loss_sdus ++ sdus, continuity_report.anomalies ++ loss_anomalies ++ anomalies,
           final_state}

        {:error, reason, anomalies, final_state} ->
          {:error, reason, continuity_report.anomalies ++ loss_anomalies ++ anomalies,
           final_state}
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
      continuation_virtual_channels: map_size(state.continuation_by_channel),
      observed_master_channels: map_size(state.continuity.master_counts),
      observed_virtual_channels: map_size(state.continuity.virtual_counts)
    }
  end

  defp dispatch_frame(frame, ctx, configuration, continuity_report, state) do
    case frame_content(frame, configuration) do
      :vca_sdu ->
        sdu = build_vca_sdu(frame, ctx, continuity_report, state)
        {:ok, [sdu], [], clear_packet_state(state, channel_key(frame))}

      :packets ->
        if space_packet_mode?(state, configuration) do
          extract_space_packets(frame, ctx, configuration, continuity_report, state)
        else
          extract_opaque_segments(frame, ctx, continuity_report, state)
        end
    end
  end

  defp extract_space_packets(frame, ctx, configuration, continuity_report, state) do
    key = channel_key(frame)
    fhp = Map.get(frame.meta, :fhp)
    data_field = frame.payload_octets

    cond do
      fhp == 2046 ->
        handle_oid(frame, key, state)

      fhp == 2047 ->
        continue_without_packet_start(frame, ctx, configuration, continuity_report, key, state)

      is_integer(fhp) and fhp >= 0 and fhp < byte_size(data_field) ->
        process_pointed_data_field(
          frame,
          ctx,
          configuration,
          continuity_report,
          key,
          fhp,
          state
        )

      true ->
        {:error, {:invalid_fhp, fhp}, [], clear_packet_state(state, key)}
    end
  end

  defp process_pointed_data_field(frame, ctx, configuration, continuity_report, key, fhp, state) do
    <<prefix::binary-size(^fhp), suffix::binary>> = frame.payload_octets
    entry = Map.get(state.packet_buffers_by_channel, key)

    {continued_packets, continuation_anomalies, state} =
      finish_continuation(entry, prefix, frame, configuration, key, state)

    case extract_packet_stream(suffix, nil, frame, configuration, key, state) do
      {:ok, new_packets, extraction_anomalies, next_state} ->
        packets = continued_packets ++ new_packets
        anomalies = continuation_anomalies ++ extraction_anomalies

        packet_delivery_result(
          packets,
          frame,
          ctx,
          continuity_report,
          state,
          anomalies,
          next_state
        )

      {:error, reason, extraction_anomalies, next_state} ->
        {:error, reason, continuation_anomalies ++ extraction_anomalies, next_state}
    end
  end

  defp finish_continuation(nil, <<>>, _frame, _configuration, _key, state),
    do: {[], [], state}

  defp finish_continuation(nil, prefix, frame, _configuration, _key, state) do
    anomaly =
      reassembly_anomaly(:orphan_packet_continuation, frame, %{
        discarded_octets: byte_size(prefix)
      })

    {[], [anomaly], state}
  end

  defp finish_continuation(entry, prefix, frame, configuration, key, state) do
    combined = entry.bytes <> prefix

    case extract_packet_stream(combined, entry, frame, configuration, key, state) do
      {:ok, packets, anomalies, next_state} ->
        case Map.get(next_state.packet_buffers_by_channel, key) do
          nil ->
            {packets, anomalies, next_state}

          remaining ->
            mismatch =
              reassembly_anomaly(:first_header_pointer_resynchronization, frame, %{
                discarded_octets: byte_size(remaining.bytes),
                indicated_packet_start: byte_size(prefix)
              })

            {packets, anomalies ++ [mismatch], clear_packet_state(next_state, key)}
        end

      {:error, reason, anomalies, next_state} ->
        anomaly = reassembly_anomaly(:continuation_decode_failed, frame, %{reason: reason})
        {[], anomalies ++ [anomaly], clear_packet_state(next_state, key)}
    end
  end

  defp continue_without_packet_start(frame, ctx, configuration, continuity_report, key, state) do
    case Map.get(state.packet_buffers_by_channel, key) do
      nil ->
        anomaly =
          reassembly_anomaly(:orphan_packet_continuation, frame, %{
            discarded_octets: byte_size(frame.payload_octets)
          })

        {:ok, [], [anomaly], state}

      entry ->
        combined = entry.bytes <> frame.payload_octets

        case extract_packet_stream(combined, entry, frame, configuration, key, state) do
          {:ok, packets, anomalies, next_state} ->
            {packets, boundary_anomalies, next_state} =
              enforce_no_packet_start_boundary(packets, frame, key, anomalies, next_state)

            packet_delivery_result(
              packets,
              frame,
              ctx,
              continuity_report,
              state,
              boundary_anomalies,
              next_state
            )

          {:error, reason, anomalies, next_state} ->
            {:error, reason, anomalies, next_state}
        end
    end
  end

  defp enforce_no_packet_start_boundary(packets, frame, key, anomalies, state) do
    remaining = Map.get(state.packet_buffers_by_channel, key)

    cond do
      length(packets) > 1 ->
        anomaly =
          reassembly_anomaly(:first_header_pointer_resynchronization, frame, %{
            reason: :multiple_packets_with_no_packet_start,
            packet_count: length(packets)
          })

        {[hd(packets)], anomalies ++ [anomaly], clear_packet_state(state, key)}

      packets != [] and remaining ->
        anomaly =
          reassembly_anomaly(:first_header_pointer_resynchronization, frame, %{
            reason: :trailing_octets_after_continued_packet,
            discarded_octets: byte_size(remaining.bytes)
          })

        {packets, anomalies ++ [anomaly], clear_packet_state(state, key)}

      true ->
        {packets, anomalies, state}
    end
  end

  defp packet_delivery_result(
         packets,
         frame,
         ctx,
         continuity_report,
         metadata_state,
         anomalies,
         next_state
       ) do
    case build_packet_sdus(packets, frame, ctx, continuity_report, metadata_state) do
      {:ok, sdus} -> {:ok, sdus, anomalies, next_state}
      {:error, reason} -> {:error, reason, anomalies, next_state}
    end
  end

  defp extract_packet_stream(bytes, prior_entry, frame, configuration, key, state) do
    maximum = maximum_packet_octets(configuration, state)

    case Stream.extract(bytes, max_packet_size: maximum) do
      {:ok, packets, remaining} ->
        packet_records = packet_records(packets, prior_entry, frame)
        next_state = put_packet_remainder(state, key, remaining, packets, prior_entry, frame)
        {:ok, packet_records, [], next_state}

      {:error, reason} ->
        anomaly = reassembly_anomaly(:invalid_space_packet, frame, %{reason: reason})
        {:error, {:invalid_space_packet, reason}, [anomaly], clear_packet_state(state, key)}
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

  defp put_packet_remainder(state, key, <<>>, _packets, _prior_entry, _frame),
    do: clear_packet_state(state, key)

  defp put_packet_remainder(state, key, remaining, packets, prior_entry, frame) do
    consumed_octets = Enum.sum_by(packets, &byte_size/1)
    prior_octets = if(prior_entry, do: byte_size(prior_entry.bytes), else: 0)

    source_frames =
      if consumed_octets < prior_octets and prior_entry do
        Enum.uniq(prior_entry.source_frames ++ [frame.frame_seq])
      else
        [frame.frame_seq]
      end

    entry = %{
      bytes: remaining,
      source_frames: source_frames,
      scid: frame.scid,
      vcid: frame.vcid,
      timestamp: frame.timestamp
    }

    %{state | packet_buffers_by_channel: Map.put(state.packet_buffers_by_channel, key, entry)}
  end

  defp build_packet_sdus(packet_records, frame, ctx, continuity_report, state) do
    packet_records
    |> Enum.reduce_while({:ok, []}, fn packet_record, {:ok, sdus} ->
      reduce_packet_sdu(packet_record, frame, ctx, continuity_report, state, sdus)
    end)
    |> case do
      {:ok, sdus} -> {:ok, Enum.reverse(sdus)}
      {:error, _reason} = error -> error
    end
  end

  defp reduce_packet_sdu(packet_record, frame, ctx, continuity_report, state, sdus) do
    case validate_received_packet_version(packet_record.octets, frame, state) do
      :ok ->
        reduce_valid_packet_sdu(packet_record, frame, ctx, continuity_report, state, sdus)

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp reduce_valid_packet_sdu(packet_record, frame, ctx, continuity_report, state, sdus) do
    case idle_packet?(packet_record.octets) do
      {:ok, true} ->
        {:cont, {:ok, sdus}}

      {:ok, false} ->
        delivery = %{
          octets: packet_record.octets,
          kind: :space_packet,
          quality: :good,
          source_frames: packet_record.source_frames,
          extra_meta: %{}
        }

        {:cont, {:ok, [build_sdu(delivery, frame, ctx, continuity_report, state) | sdus]}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp validate_received_packet_version(_packet, _frame, %{configurations: configurations})
       when map_size(configurations) == 0,
       do: :ok

  defp validate_received_packet_version(<<version::3, _rest::bitstring>>, frame, state) do
    configuration = Map.fetch!(state.configurations, {frame.scid, frame.vcid})

    if version in configuration.valid_packet_version_numbers,
      do: :ok,
      else: {:error, {:invalid_packet_version_number, version}}
  end

  defp idle_packet?(packet) do
    case SpacePacketCodec.decode(packet) do
      {:ok, decoded} -> {:ok, SpacePacket.idle?(decoded)}
      {:error, reason} -> {:error, {:invalid_space_packet, reason}}
    end
  end

  defp handle_oid(frame, key, state) do
    case validate_oid_data_field(frame.payload_octets, key, state) do
      {:ok, next_state} ->
        {:ok, [], [], clear_packet_state(next_state, key)}

      {:error, reason, next_state} ->
        anomaly = reassembly_anomaly(:oid_validation_failed, frame, %{reason: reason})
        {:error, reason, [anomaly], clear_packet_state(next_state, key)}
    end
  end

  defp validate_oid_data_field(_data_field, _key, %{oid_validation: :none} = state),
    do: {:ok, state}

  defp validate_oid_data_field(data_field, key, state) do
    lfsr_state =
      Map.get(state.oid_lfsr_by_virtual_channel, key, OnlyIdleData.initial_state())

    result =
      case state.oid_validation do
        :prefix ->
          OnlyIdleData.validate_prefix(
            data_field,
            state.oid_validation_prefix_bytes,
            lfsr_state
          )

        :strict ->
          OnlyIdleData.validate(data_field, lfsr_state)
      end

    case result do
      {:ok, next_lfsr_state} ->
        {:ok,
         %{
           state
           | oid_lfsr_by_virtual_channel:
               Map.put(state.oid_lfsr_by_virtual_channel, key, next_lfsr_state)
         }}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp extract_opaque_segments(frame, ctx, continuity_report, state) do
    key = channel_key(frame)
    fhp = Map.get(frame.meta, :fhp)

    cond do
      fhp == 2046 ->
        handle_oid(frame, key, state)

      fhp == 2047 and Map.get(state.continuation_by_channel, key, false) ->
        delivery = %{
          octets: frame.payload_octets,
          kind: opaque_sdu_kind(state),
          quality: :good,
          source_frames: [frame.frame_seq],
          extra_meta: %{}
        }

        sdu = build_sdu(delivery, frame, ctx, continuity_report, state)

        {:ok, [sdu], [], state}

      fhp == 2047 ->
        {:ok, [], [], state}

      is_integer(fhp) and fhp >= 0 and fhp < byte_size(frame.payload_octets) ->
        <<_prefix::binary-size(^fhp), suffix::binary>> = frame.payload_octets

        delivery = %{
          octets: suffix,
          kind: opaque_sdu_kind(state),
          quality: :good,
          source_frames: [frame.frame_seq],
          extra_meta: %{}
        }

        sdu = build_sdu(delivery, frame, ctx, continuity_report, state)

        {:ok, [sdu], [],
         %{state | continuation_by_channel: Map.put(state.continuation_by_channel, key, true)}}

      true ->
        {:error, {:invalid_fhp, fhp}, [], state}
    end
  end

  defp build_vca_sdu(frame, ctx, continuity_report, state) do
    extra_meta = %{
      vca_status_fields: Map.get(frame.meta, :vca_status_fields),
      vca_sdu_loss_flag: continuity_report.virtual_channel.loss?,
      verification_status_code: Map.get(ctx, :verification_status_code)
    }

    delivery = %{
      octets: frame.payload_octets,
      kind: :vca_sdu,
      quality: :good,
      source_frames: [frame.frame_seq],
      extra_meta: extra_meta
    }

    build_sdu(delivery, frame, ctx, continuity_report, state)
  end

  defp build_sdu(delivery, frame, ctx, continuity_report, state) do
    meta =
      frame.meta
      |> Map.put(:scid, frame.scid)
      |> Map.put(:vcid, frame.vcid)
      |> Map.put(:continuity, continuity_report)
      |> maybe_put_ocf(frame.ocf)
      |> maybe_put_target_id(target_id(state, frame.scid))
      |> merge_vcid_metadata(vcid_metadata(state, frame.scid, frame.vcid))
      |> Map.merge(delivery.extra_meta)

    %SDUOctets{
      profile: frame.profile,
      scid: frame.scid,
      vcid: frame.vcid,
      map_id: nil,
      direction: Map.get(ctx, :direction, :downlink),
      sdu_kind_hint: delivery.kind,
      octets: delivery.octets,
      quality: delivery.quality,
      source_frames: delivery.source_frames,
      timestamp: frame.timestamp,
      meta: meta
    }
  end

  defp handle_virtual_channel_loss(frame, ctx, configuration, report, state) do
    key = channel_key(frame)
    entry = Map.get(state.packet_buffers_by_channel, key)

    if report.virtual_channel.loss? and entry do
      disposition = if deliver_incomplete?(configuration), do: :delivered, else: :discarded

      anomaly =
        reassembly_anomaly(:partial_packet_on_frame_count_discontinuity, frame, %{
          buffered_octets: byte_size(entry.bytes),
          source_frames: entry.source_frames,
          disposition: disposition,
          continuity: report.virtual_channel
        })

      sdus =
        if disposition == :delivered do
          delivery = %{
            octets: entry.bytes,
            kind: :space_packet,
            quality: :partial,
            source_frames: entry.source_frames,
            extra_meta: %{partial_reason: :frame_count_discontinuity}
          }

          [
            build_sdu(delivery, frame, ctx, report, state)
          ]
        else
          []
        end

      {sdus, [anomaly], clear_packet_state(state, key)}
    else
      {[], [], state}
    end
  end

  defp clear_packet_state(state, key) do
    %{
      state
      | packet_buffers_by_channel: Map.delete(state.packet_buffers_by_channel, key),
        continuation_by_channel: Map.delete(state.continuation_by_channel, key)
    }
  end

  defp fetch_configuration(_frame, %{configurations: configurations})
       when map_size(configurations) == 0,
       do: {:ok, nil}

  defp fetch_configuration(frame, state) do
    case Map.fetch(state.configurations, {frame.scid, frame.vcid}) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:unknown_tm_channel, frame.scid, frame.vcid}}
    end
  end

  defp validate_managed_frame(_frame, nil), do: :ok

  defp validate_managed_frame(frame, configuration) do
    expected_content = configuration.data_field_content
    actual_content = frame_content(frame, nil)
    expected_length = Configuration.maximum_data_field_octets(configuration)

    cond do
      not Configuration.matches?(configuration, frame.scid, frame.vcid) ->
        {:error, {:managed_channel_mismatch, frame.scid, frame.vcid}}

      actual_content != expected_content ->
        {:error, {:data_field_content_mismatch, actual_content, expected_content}}

      byte_size(frame.payload_octets) != expected_length ->
        {:error, {:invalid_data_field_length, byte_size(frame.payload_octets), expected_length}}

      not managed_secondary_header_valid?(frame, configuration) ->
        {:error, :managed_secondary_header_mismatch}

      not managed_ocf_valid?(frame, configuration) ->
        {:error, :managed_ocf_mismatch}

      true ->
        :ok
    end
  end

  defp managed_secondary_header_valid?(frame, configuration) do
    case {Configuration.secondary_header?(configuration), Map.get(frame.meta, :secondary_header)} do
      {false, nil} ->
        true

      {true, %SecondaryHeader{} = header} ->
        SecondaryHeader.encoded_length(header) == configuration.secondary_header_length

      _ ->
        false
    end
  end

  defp managed_ocf_valid?(frame, configuration) do
    case {Configuration.ocf?(configuration), frame.ocf} do
      {false, nil} -> true
      {false, <<>>} -> true
      {true, ocf} when is_binary(ocf) -> byte_size(ocf) == 4
      _ -> false
    end
  end

  defp frame_content(_frame, %Configuration{data_field_content: content}), do: content

  defp frame_content(frame, nil),
    do: if(Map.get(frame.meta, :sync_flag, 0) == 1, do: :vca_sdu, else: :packets)

  defp normalize_configurations(opts) do
    values =
      case {Keyword.get(opts, :configuration), Keyword.get(opts, :configurations)} do
        {nil, nil} -> []
        {%Configuration{} = configuration, nil} -> [configuration]
        {nil, configurations} when is_list(configurations) -> configurations
        _values -> :invalid
      end

    case values do
      :invalid ->
        {:error, :invalid_tm_configurations}

      configurations ->
        index_configuration_plan(configurations)
    end
  end

  defp index_configuration_plan([]), do: {:ok, %{}}

  defp index_configuration_plan(configurations) do
    with :ok <- Configuration.validate_plan(configurations) do
      {:ok, Map.new(configurations, &{Configuration.address(&1), &1})}
    end
  end

  defp maximum_packet_octets(nil, state), do: state.max_space_packet_size
  defp maximum_packet_octets(configuration, _state), do: configuration.maximum_packet_octets

  defp deliver_incomplete?(nil), do: false
  defp deliver_incomplete?(configuration), do: configuration.deliver_incomplete_packets?

  defp space_packet_mode?(_state, %Configuration{data_field_content: :packets}), do: true
  defp space_packet_mode?(state, nil), do: state.default_sdu_type == :space_packet

  defp opaque_sdu_kind(state), do: state.default_sdu_type
  defp channel_key(frame), do: {0, frame.scid, frame.vcid}

  defp reassembly_anomaly(kind, frame, metadata) do
    %{
      anomaly_kind: kind,
      scid: frame.scid,
      vcid: frame.vcid,
      frame_seq: frame.frame_seq,
      metadata: metadata
    }
  end

  defp target_id(state, scid), do: Map.get(state.scid_target_map, scid) || state.default_target_id

  defp vcid_metadata(state, scid, vcid) do
    case Map.get(state.vcid_target_map, scid) do
      nil -> Map.get(state.default_vcid_map, vcid, %{})
      vcid_map -> Map.get(vcid_map, vcid) || Map.get(state.default_vcid_map, vcid, %{})
    end
  end

  defp merge_vcid_metadata(metadata, meta) when map_size(meta) == 0, do: metadata

  defp merge_vcid_metadata(metadata, meta) do
    metadata
    |> maybe_put_metadata(:lane, meta)
    |> maybe_put_metadata(:qos, meta)
  end

  defp maybe_put_metadata(metadata, key, source) do
    case Map.get(source, key) || Map.get(source, Atom.to_string(key)) do
      nil -> metadata
      "" -> metadata
      value -> Map.put(metadata, key, value)
    end
  end

  defp maybe_put_target_id(metadata, nil), do: metadata
  defp maybe_put_target_id(metadata, target_id), do: Map.put(metadata, :target_id, target_id)

  defp maybe_put_ocf(metadata, nil), do: metadata
  defp maybe_put_ocf(metadata, <<>>), do: metadata
  defp maybe_put_ocf(metadata, ocf), do: Map.put(metadata, :ocf, ocf)

  defp normalize_oid_validation(value) when value in [:none, :prefix, :strict], do: {:ok, value}

  defp normalize_oid_validation(value) when is_binary(value) do
    case String.downcase(value) do
      "none" -> {:ok, :none}
      "prefix" -> {:ok, :prefix}
      "strict" -> {:ok, :strict}
      _other -> {:error, {:invalid_oid_validation, value}}
    end
  end

  defp normalize_oid_validation(value), do: {:error, {:invalid_oid_validation, value}}

  defp normalize_oid_prefix_bytes(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp normalize_oid_prefix_bytes(value), do: {:error, {:invalid_oid_prefix_bytes, value}}

  defp normalize_sdu_kind_hint(nil), do: nil
  defp normalize_sdu_kind_hint(:space_packet), do: :space_packet
  defp normalize_sdu_kind_hint(value), do: value
end
