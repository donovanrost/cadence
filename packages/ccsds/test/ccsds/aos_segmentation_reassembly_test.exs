defmodule CCSDS.SDLP.AOS.SegmentationReassemblyTest do
  use ExUnit.Case, async: true

  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.AOS.{Configuration, FrameCodec, Reassembly, Segmentation}

  test "packs, encodes, decodes, and reassembles Packets across M_PDUs" do
    configuration =
      Configuration.new!(
        physical_channel: "ka",
        frame_size: 32,
        scid: 600,
        vcid: 7,
        frame_header_error_control?: true,
        insert_zone_length: 2,
        fecf?: true,
        ocf?: true,
        maximum_packet_octets: 128
      )

    packet = space_packet(12, :binary.copy(<<0xAB>>, 20))
    sdu = sdu(:space_packet, packet, configuration)
    context = %{configuration: configuration, insert_zone: <<1, 2>>, ocf: <<3, 4, 5, 6>>}
    {:ok, segmentation} = Segmentation.init([])

    assert {:ok, frames, _segmentation} =
             Segmentation.segment(sdu, context, segmentation)

    assert length(frames) > 1

    decoded =
      Enum.map(frames, fn frame ->
        assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)
        assert {:ok, [decoded], <<>>} = FrameCodec.decode(encoded, configuration: configuration)
        decoded
      end)

    {:ok, reassembly} = Reassembly.init(configuration: configuration)

    {_auxiliary, packets, _state} =
      Enum.reduce(decoded, {[], [], reassembly}, fn frame, {auxiliary, packets, state} ->
        assert {:ok, sdus, _anomalies, next_state} =
                 Reassembly.ingest_detailed(frame, %{direction: :downlink}, state)

        {new_packets, new_auxiliary} = Enum.split_with(sdus, &(&1.sdu_kind_hint == :space_packet))
        {auxiliary ++ new_auxiliary, packets ++ new_packets, next_state}
      end)

    assert Enum.map(packets, & &1.octets) == [packet]
    assert hd(packets).source_frames == [0, 1]
  end

  test "segments Bitstream Data by bit count and delivers loss metadata" do
    configuration =
      Configuration.new!(
        frame_size: 16,
        scid: 20,
        vcid: 2,
        data_field_content: :b_pdu
      )

    source = <<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 1, 2, 3, 0x80>>
    sdu = sdu(:bitstream, source, configuration, %{valid_bits: 73})
    {:ok, segmentation} = Segmentation.init([])

    assert {:ok, [first, second], _state} =
             Segmentation.segment(sdu, %{configuration: configuration}, segmentation)

    assert first.meta.bitstream_data_pointer == 0x3FFF
    assert second.meta.bitstream_data_pointer == 8

    {:ok, reassembly} = Reassembly.init(configuration: configuration)
    assert {:ok, [first_sdu], [], reassembly} = Reassembly.ingest_detailed(first, %{}, reassembly)
    assert {:ok, [second_sdu], [], _state} = Reassembly.ingest_detailed(second, %{}, reassembly)
    assert first_sdu.meta.valid_bits == 64
    assert second_sdu.meta.valid_bits == 9
    refute first_sdu.meta.bitstream_data_loss_flag
    refute second_sdu.meta.bitstream_data_loss_flag
  end

  test "delivers one fixed VCA_SDU and continuous OID state" do
    access =
      Configuration.new!(
        physical_channel: "s-band",
        frame_size: 14,
        scid: 9,
        vcid: 4,
        valid_vcids: [4, 63],
        data_field_content: :vca_sdu
      )

    oid =
      Configuration.new!(
        physical_channel: "s-band",
        frame_size: 14,
        scid: 9,
        vcid: 63,
        valid_vcids: [4, 63],
        data_field_content: :idle_data
      )

    {:ok, segmentation} = Segmentation.init([])
    access_sdu = sdu(:vca_sdu, :binary.copy(<<7>>, 8), access)

    assert {:ok, [access_frame], segmentation} =
             Segmentation.segment(access_sdu, %{configuration: access}, segmentation)

    assert {:ok, first_oid, segmentation} =
             Segmentation.only_idle(%{configuration: oid}, segmentation)

    assert {:ok, second_oid, _segmentation} =
             Segmentation.only_idle(%{configuration: oid}, segmentation)

    {:ok, reassembly} =
      Reassembly.init(configurations: [access, oid], oid_validation: :strict)

    assert {:ok, [delivered], [], reassembly} =
             Reassembly.ingest_detailed(access_frame, %{}, reassembly)

    assert delivered.octets == access_sdu.octets
    refute delivered.meta.vca_sdu_loss_flag
    assert {:ok, [], [], reassembly} = Reassembly.ingest_detailed(first_oid, %{}, reassembly)
    assert {:ok, [], [], _state} = Reassembly.ingest_detailed(second_oid, %{}, reassembly)
  end

  defp sdu(kind, data, configuration, meta \\ %{}) do
    %SDUOctets{
      profile: :aos,
      scid: configuration.scid,
      vcid: configuration.vcid,
      direction: :downlink,
      sdu_kind_hint: kind,
      octets: data,
      quality: :good,
      source_frames: [],
      meta: meta
    }
  end

  defp space_packet(sequence_count, data) do
    <<0::3, 0::1, 0::1, 42::11, 3::2, sequence_count::14, byte_size(data) - 1::16, data::binary>>
  end
end
