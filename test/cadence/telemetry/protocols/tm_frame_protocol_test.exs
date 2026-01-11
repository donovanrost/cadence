defmodule Cadence.Protocols.CCSDS.TMFrameProtocolTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Cadence.Protocols.CCSDS.TMFrameProtocol

  @frame_size 32
  @payload_size 4

  test "extracts a single CCSDS packet and metadata from a TM frame" do
    packet = build_ccsds_packet(@payload_size, 100)
    frame = build_tm_frame(packet, fhp: 0, frame_size: @frame_size, scid: 42, vcid: 3)

    state =
      TMFrameProtocol.new(
        frame_size: @frame_size,
        scid_target_map: %{42 => "SAT-42"}
      )

    {:ok, [packet_out], state} = TMFrameProtocol.read_data(frame, state)
    {packet_out, metadata, _state} = TMFrameProtocol.read_packet(packet_out, %{}, state)

    assert packet_out == packet
    assert metadata.scid == 42
    assert metadata.vcid == 3
    assert metadata.target_id == "SAT-42"
    assert metadata.fhp == 0
  end

  test "extracts multiple packets from a single frame" do
    packet1 = build_ccsds_packet(4, 100)
    packet2 = build_ccsds_packet(6, 101)
    frame = build_tm_frame(packet1 <> packet2, fhp: 0, frame_size: 40, scid: 7, vcid: 1)

    state = TMFrameProtocol.new(frame_size: 40, scid_target_map: %{7 => "SAT-7"})

    {:ok, packets, state} = TMFrameProtocol.read_data(frame, state)
    assert length(packets) == 2

    {out1, metadata1, state} = TMFrameProtocol.read_packet(Enum.at(packets, 0), %{}, state)
    {out2, metadata2, _state} = TMFrameProtocol.read_packet(Enum.at(packets, 1), %{}, state)

    assert out1 == packet1
    assert out2 == packet2
    assert metadata1.target_id == "SAT-7"
    assert metadata2.target_id == "SAT-7"
  end

  test "drops idle packets from frame output" do
    packet = build_ccsds_packet(4, 100)
    frame = build_tm_frame(packet, fhp: 0, frame_size: 26, scid: 5, vcid: 1)

    state = TMFrameProtocol.new(frame_size: 26, scid_target_map: %{5 => "SAT-5"})

    {:ok, packets, state} = TMFrameProtocol.read_data(frame, state)
    assert packets == [packet]

    {packet_out, metadata, _state} = TMFrameProtocol.read_packet(packet, %{}, state)
    assert packet_out == packet
    assert metadata.target_id == "SAT-5"
  end

  test "drops OID frames and clears partial buffers" do
    data_field_size = 20
    frame = build_tm_frame(build_idle_padding(data_field_size), fhp: 2046, frame_size: 26)

    state = TMFrameProtocol.new(frame_size: 26)
    state = %{state | partial_by_vcid: %{0 => <<1, 2, 3>>}}

    {:stop, state} = TMFrameProtocol.read_data(frame, state)
    assert state.partial_by_vcid == %{}
  end

  test "accepts OID frames with PN prefix validation enabled" do
    data_field = oid_pn_bytes(20, 0xFFFFFFFF) |> elem(0)
    frame = build_tm_frame(data_field, fhp: 2046, frame_size: 26, vcid: 2)

    state = TMFrameProtocol.new(frame_size: 26, oid_validation: :prefix)

    {:stop, state} = TMFrameProtocol.read_data(frame, state)
    assert Map.has_key?(state.oid_lfsr_by_vcid, 2)
  end

  test "drops OID frames with PN mismatch in strict mode" do
    data_field = :binary.copy(<<0>>, 20)
    frame = build_tm_frame(data_field, fhp: 2046, frame_size: 26, vcid: 1)

    state = TMFrameProtocol.new(frame_size: 26, oid_validation: :strict)

    {:stop, state} = TMFrameProtocol.read_data(frame, state)
    assert state.oid_lfsr_by_vcid == %{}
  end

  test "reassembles a packet spanning two frames" do
    packet = build_ccsds_packet(20, 102)

    frame_size = 26
    data_field_size = frame_size - 6

    {part1, part2} = split_binary(packet, data_field_size)

    frame1 = build_tm_frame(part1, fhp: 0, frame_size: frame_size, scid: 9, vcid: 2)

    padding = build_idle_packet(data_field_size - byte_size(part2))
    frame2_payload = part2 <> padding

    frame2 =
      build_tm_frame(frame2_payload,
        fhp: byte_size(part2),
        frame_size: frame_size,
        scid: 9,
        vcid: 2
      )

    state = TMFrameProtocol.new(frame_size: 26, scid_target_map: %{9 => "SAT-9"})

    {:stop, state} = TMFrameProtocol.read_data(frame1, state)

    {:ok, [packet_out], state} = TMFrameProtocol.read_data(frame2, state)

    {packet_out, metadata, _state} = TMFrameProtocol.read_packet(packet_out, %{}, state)

    assert packet_out == packet
    assert metadata.target_id == "SAT-9"
    assert metadata.fhp == byte_size(part2)
  end

  defp build_ccsds_packet(payload_size, apid) do
    payload = :binary.copy(<<0xAB>>, payload_size)
    packet_length = payload_size - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      0::14,
      packet_length::16,
      payload::binary
    >>
  end

  defp build_tm_frame(payload, opts) do
    frame_size = Keyword.fetch!(opts, :frame_size)
    scid = Keyword.get(opts, :scid, 0)
    vcid = Keyword.get(opts, :vcid, 0)
    fhp = Keyword.get(opts, :fhp, 0)

    ocf_flag = 0
    sec_hdr_flag = 0
    sync_flag = 0
    packet_order_flag = 0
    segment_len_id = 3

    mcfc = 0
    vcfc = 0

    primary_header =
      <<
        0::2,
        scid::10,
        vcid::3,
        ocf_flag::1,
        mcfc::8,
        vcfc::8,
        sec_hdr_flag::1,
        sync_flag::1,
        packet_order_flag::1,
        segment_len_id::2,
        fhp::11
      >>

    data_field_size = frame_size - 6

    if byte_size(payload) > data_field_size do
      raise ArgumentError, "payload size exceeds frame data field"
    end

    padding = data_field_size - byte_size(payload)
    primary_header <> payload <> build_idle_padding(padding)
  end

  defp build_idle_padding(0), do: <<>>

  defp build_idle_padding(padding_size) when padding_size < 7 do
    raise ArgumentError, "padding too small for idle packet: #{padding_size} bytes"
  end

  defp build_idle_padding(padding_size) do
    build_idle_packet(padding_size)
  end

  defp build_idle_packet(size) do
    payload_size = size - 6
    packet_length = payload_size - 1
    payload = :binary.copy(<<0>>, payload_size)

    <<
      0::3,
      0::1,
      0::1,
      0x7FF::11,
      3::2,
      0::14,
      packet_length::16,
      payload::binary
    >>
  end

  defp split_binary(binary, size) do
    <<head::binary-size(size), tail::binary>> = binary
    {head, tail}
  end

  defp oid_pn_bytes(length, lfsr_state) do
    {bits, next_state} = generate_oid_bits(length * 8, lfsr_state)

    bytes =
      bits
      |> Enum.chunk_every(8)
      |> Enum.map(fn chunk ->
        Enum.reduce(chunk, 0, fn bit, acc -> (acc <<< 1) ||| bit end)
      end)
      |> :binary.list_to_bin()

    {bytes, next_state}
  end

  defp generate_oid_bits(count, lfsr_state) do
    Enum.reduce(1..count, {[], lfsr_state}, fn _, {acc, state} ->
      {bit, next_state} = next_oid_bit(state)
      {[bit | acc], next_state}
    end)
    |> then(fn {bits, next_state} -> {Enum.reverse(bits), next_state} end)
  end

  defp next_oid_bit(state) do
    output = (state >>> 31) &&& 1
    feedback =
      output
      |> bxor((state >>> 21) &&& 1)
      |> bxor((state >>> 1) &&& 1)
      |> bxor(state &&& 1)
    next_state = ((state <<< 1) &&& 0xFFFFFFFF) ||| feedback
    {output, next_state}
  end
end
