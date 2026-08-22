defmodule Cadence.CCSDS.SDLP.TM.ReassemblyTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.TM.{Configuration, Reassembly, Segmentation}

  test "extracts SDU octets from a single frame payload" do
    {:ok, state} = Reassembly.init([])

    frame = %LinkFrame{
      profile: :tm,
      scid: 1,
      vcid: 2,
      map_id: nil,
      frame_seq: 10,
      payload_octets: <<0xAA, 0xBB, 0xCC>>,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: %{fhp: 0}
    }

    assert {:ok, [sdu], _state} = Reassembly.ingest(frame, %{direction: :downlink}, state)
    assert sdu.octets == <<0xAA, 0xBB, 0xCC>>
    assert sdu.scid == 1
    assert sdu.vcid == 2
  end

  test "reassembles a space packet that spans multiple frames" do
    {:ok, state} = Reassembly.init(default_sdu_type: :space_packet)

    payload = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
    packet_id = 0
    seq_control = 0
    length = byte_size(payload) - 1
    packet = <<packet_id::16, seq_control::16, length::16>> <> payload

    <<segment1::binary-size(10), segment2::binary>> = packet

    frame1 = %LinkFrame{
      profile: :tm,
      scid: 1,
      vcid: 2,
      map_id: nil,
      frame_seq: 10,
      payload_octets: segment1,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: %{fhp: 0}
    }

    frame2 = %LinkFrame{
      profile: :tm,
      scid: 1,
      vcid: 2,
      map_id: nil,
      frame_seq: 11,
      payload_octets: segment2,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: %{fhp: 2047}
    }

    assert {:ok, [], state} = Reassembly.ingest(frame1, %{direction: :downlink}, state)
    assert {:ok, [sdu], _state} = Reassembly.ingest(frame2, %{direction: :downlink}, state)
    assert sdu.octets == packet
  end

  test "rejects a packet whose declared size exceeds the managed maximum" do
    {:ok, state} =
      Reassembly.init(default_sdu_type: :space_packet, max_space_packet_size: 12)

    frame = %LinkFrame{
      profile: :tm,
      scid: 1,
      vcid: 2,
      map_id: nil,
      frame_seq: 10,
      payload_octets: <<0, 1, 0xC0, 0, 0, 10>>,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: %{fhp: 0}
    }

    assert {:error, {:invalid_space_packet, {:packet_size_exceeds_managed_maximum, 17, 12}},
            next_state} =
             Reassembly.ingest(frame, %{direction: :downlink}, state)

    assert next_state.packet_buffers_by_channel == %{}
  end

  test "reports VC and MC continuity independently and discards a partial packet on loss" do
    packet = build_space_packet(1, :binary.copy(<<1>>, 10))
    <<first_part::binary-size(10), _rest::binary>> = packet
    replacement = build_space_packet(2, <<9, 8, 7, 6>>)

    {:ok, state} = Reassembly.init(default_sdu_type: :space_packet)

    assert {:ok, [], [], state} =
             Reassembly.ingest_detailed(
               frame(1, 2, 0, 10, 0, first_part),
               %{direction: :downlink},
               state
             )

    assert {:ok, [sdu], anomalies, _state} =
             Reassembly.ingest_detailed(
               frame(1, 2, 1, 12, 0, replacement),
               %{direction: :downlink},
               state
             )

    assert sdu.octets == replacement
    assert Enum.any?(anomalies, &(&1.anomaly_kind == :virtual_channel_frame_count_discontinuity))

    assert Enum.any?(
             anomalies,
             &(&1.anomaly_kind == :partial_packet_on_frame_count_discontinuity and
                 &1.metadata.disposition == :discarded)
           )

    refute Enum.any?(anomalies, &(&1.anomaly_kind == :master_channel_frame_count_discontinuity))
  end

  test "delivers an incomplete packet when that managed option is enabled" do
    assert {:ok, configuration} =
             Configuration.new(
               frame_size: 16,
               scid: 3,
               vcid: 1,
               maximum_packet_octets: 128,
               deliver_incomplete_packets?: true
             )

    packet = build_space_packet(1, :binary.copy(<<1>>, 10))
    <<first_part::binary-size(10), _rest::binary>> = packet
    replacement = build_space_packet(2, <<9, 8, 7, 6>>)
    {:ok, state} = Reassembly.init(configuration: configuration)

    assert {:ok, [], [], state} =
             Reassembly.ingest_detailed(frame(3, 1, 0, 20, 0, first_part), %{}, state)

    assert {:ok, [partial, complete], anomalies, _state} =
             Reassembly.ingest_detailed(frame(3, 1, 1, 22, 0, replacement), %{}, state)

    assert partial.quality == :partial
    assert partial.octets == first_part
    assert partial.meta.partial_reason == :frame_count_discontinuity
    assert complete.quality == :good
    assert complete.octets == replacement

    assert Enum.any?(
             anomalies,
             &(&1.anomaly_kind == :partial_packet_on_frame_count_discontinuity and
                 &1.metadata.disposition == :delivered)
           )
  end

  test "does not collide identical VCIDs from different spacecraft" do
    packet = build_space_packet(4, :binary.copy(<<4>>, 10))
    <<first_part::binary-size(10), second_part::binary>> = packet
    other_packet = build_space_packet(5, <<1, 2, 3, 4>>)
    {:ok, state} = Reassembly.init(default_sdu_type: :space_packet)

    assert {:ok, [], state} =
             Reassembly.ingest(frame(1, 2, 0, 7, 0, first_part), %{}, state)

    assert {:ok, [other], state} =
             Reassembly.ingest(frame(2, 2, 90, 30, 0, other_packet), %{}, state)

    assert other.octets == other_packet

    assert {:ok, [completed], _state} =
             Reassembly.ingest(frame(1, 2, 1, 8, 2047, second_part), %{}, state)

    assert completed.octets == packet
    assert completed.source_frames == [7, 8]
  end

  test "delivers one VCA_SDU per frame with a VCFC-derived loss flag" do
    assert {:ok, configuration} =
             Configuration.new(
               frame_size: 12,
               scid: 8,
               vcid: 6,
               data_field_content: :vca_sdu,
               valid_packet_version_numbers: [],
               maximum_packet_octets: nil
             )

    {:ok, state} = Reassembly.init(configuration: configuration)
    first = frame(8, 6, 10, 4, 0x1234, <<1, 2, 3, 4, 5, 6>>, sync_flag: 1)
    second = frame(8, 6, 11, 6, 0x2ABC, <<7, 8, 9, 10, 11, 12>>, sync_flag: 1)

    assert {:ok, [first_sdu], [], state} = Reassembly.ingest_detailed(first, %{}, state)
    refute first_sdu.meta.vca_sdu_loss_flag
    assert first_sdu.meta.vca_status_fields == 0x1234

    assert {:ok, [second_sdu], anomalies, _state} =
             Reassembly.ingest_detailed(second, %{}, state)

    assert second_sdu.sdu_kind_hint == :vca_sdu
    assert second_sdu.meta.vca_sdu_loss_flag
    assert second_sdu.meta.vca_status_fields == 0x2ABC
    assert Enum.any?(anomalies, &(&1.anomaly_kind == :virtual_channel_frame_count_discontinuity))
  end

  test "validates continuous OID PN state across frames" do
    {:ok, segmentation} = Segmentation.init([])
    context = %{frame_size: 16, scid: 9, vcid: 2}
    {:ok, first, segmentation} = Segmentation.only_idle(context, segmentation)
    {:ok, second, _segmentation} = Segmentation.only_idle(context, segmentation)
    {:ok, state} = Reassembly.init(default_sdu_type: :space_packet, oid_validation: :strict)

    assert {:ok, [], state} = Reassembly.ingest(first, %{}, state)
    assert {:ok, [], _state} = Reassembly.ingest(second, %{}, state)

    <<prefix::binary-size(3), byte, suffix::binary>> = second.payload_octets
    corrupt = %{second | payload_octets: prefix <> <<Bitwise.bxor(byte, 1)>> <> suffix}
    {:ok, fresh_state} = Reassembly.init(default_sdu_type: :space_packet, oid_validation: :strict)
    assert {:ok, [], fresh_state} = Reassembly.ingest(first, %{}, fresh_state)

    assert {:error, {:oid_pn_mismatch, %{offset: 3}}, _state} =
             Reassembly.ingest(corrupt, %{}, fresh_state)
  end

  defp frame(scid, vcid, mcfc, vcfc, fhp_or_status, payload, opts \\ []) do
    sync_flag = Keyword.get(opts, :sync_flag, 0)

    meta =
      if sync_flag == 1 do
        %{
          mcfc: mcfc,
          vcfc: vcfc,
          sync_flag: 1,
          data_field_content: :vca_sdu,
          vca_status_fields: fhp_or_status
        }
      else
        %{
          mcfc: mcfc,
          vcfc: vcfc,
          sync_flag: 0,
          packet_order_flag: 0,
          segment_length_id: 3,
          fhp: fhp_or_status
        }
      end

    %LinkFrame{
      profile: :tm,
      scid: scid,
      vcid: vcid,
      frame_seq: vcfc,
      payload_octets: payload,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: meta
    }
  end

  defp build_space_packet(sequence_count, data) do
    <<0::3, 0::1, 0::1, 42::11, 3::2, sequence_count::14, byte_size(data) - 1::16, data::binary>>
  end
end
