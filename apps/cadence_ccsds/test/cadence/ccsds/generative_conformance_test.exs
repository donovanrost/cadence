defmodule Cadence.CCSDS.GenerativeConformanceTest do
  use ExUnit.Case, async: false

  import Bitwise

  alias Cadence.CCSDS.ChannelCoding.{BCH, CLTU, Configuration, LDPC, Randomizer}
  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.TM.FrameCodec, as: TMFrameCodec
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec
  alias Cadence.CCSDS.TC.TransferFrame
  alias Cadence.CCSDS.TestSupport.DeterministicGenerator, as: Generator

  @seed String.to_integer(System.get_env("CCSDS_GENERATIVE_SEED", "20260720"))
  @cases String.to_integer(System.get_env("CCSDS_GENERATIVE_CASES", "512"))

  @moduletag timeout: 120_000

  test "seeded Space Packet fields and streaming boundaries round-trip" do
    {_packets, state} =
      Enum.map_reduce(1..@cases, Generator.seed(@seed), fn case_number, state ->
        {packet, state} = space_packet(state)
        context = context(:space_packet, case_number)

        encoded = expect_ok(SpacePacketCodec.encode(packet), context)
        assert_result(SpacePacketCodec.decode(encoded), {:ok, packet}, context)

        {split, state} = Generator.integer(state, 0, byte_size(encoded) - 1)
        <<prefix::binary-size(^split), suffix::binary>> = encoded

        assert_result(SpacePacketCodec.decode_prefix(prefix), {:incomplete, prefix}, context)

        assert_result(
          SpacePacketCodec.decode_prefix(prefix <> suffix),
          {:ok, packet, <<>>},
          context
        )

        {encoded, state}
      end)

    assert is_tuple(state)
  end

  test "seeded variable-length TC transfer frames round-trip with and without FECF" do
    final_state =
      Enum.reduce(1..@cases, Generator.seed(@seed + 1), fn case_number, state ->
        {frame, fecf?, maximum_frame_size, state} = tc_frame(state)
        context = context(:tc_transfer_frame, case_number)
        options = [frame_size: maximum_frame_size, fecf: fecf?]

        encoded = expect_ok(TransferFrame.encode(frame, options), context)
        decoded = expect_single(TransferFrame.decode(encoded, options), context)

        assert_equal(decoded.version, frame.version, context)
        assert_equal(decoded.bypass_flag, frame.bypass_flag, context)
        assert_equal(decoded.control_command_flag, frame.control_command_flag, context)
        assert_equal(decoded.scid, frame.scid, context)
        assert_equal(decoded.vcid, frame.vcid, context)
        assert_equal(decoded.frame_seq, frame.frame_seq, context)
        assert_equal(decoded.payload, frame.payload, context)
        assert_equal(not is_nil(decoded.fecf), fecf?, context)
        state
      end)

    assert is_tuple(final_state)
  end

  test "seeded fixed-length Packet and VCA TM frames round-trip" do
    final_state =
      Enum.reduce(1..@cases, Generator.seed(@seed + 2), fn case_number, state ->
        {frame, options, state} = tm_frame(state)
        context = context(:tm_transfer_frame, case_number)

        encoded = expect_ok(TMFrameCodec.encode(frame, options), context)

        decoded =
          case TMFrameCodec.decode(encoded, options) do
            {:ok, [decoded], <<>>} -> decoded
            result -> flunk_result(result, context)
          end

        assert_equal(decoded.scid, frame.scid, context)
        assert_equal(decoded.vcid, frame.vcid, context)
        assert_equal(decoded.frame_seq, frame.frame_seq, context)
        assert_equal(decoded.payload_octets, frame.payload_octets, context)
        assert_equal(decoded.meta.mcfc, frame.meta.mcfc, context)
        assert_equal(decoded.meta.sync_flag, frame.meta.sync_flag, context)
        assert_equal(decoded.ocf, frame.ocf, context)
        state
      end)

    assert is_tuple(final_state)
  end

  test "seeded randomizer, BCH, LDPC, and CLTU properties hold" do
    final_state =
      Enum.reduce(1..@cases, Generator.seed(@seed + 3), fn case_number, state ->
        context = context(:channel_coding, case_number)
        {random_octets, state} = Generator.integer(state, 0, 256)
        {random_input, state} = Generator.binary(state, random_octets)

        assert_equal(
          random_input |> Randomizer.apply() |> Randomizer.apply(),
          random_input,
          context
        )

        {bch_information, state} = Generator.binary(state, BCH.information_octets())
        bch_codeword = expect_ok(BCH.encode(bch_information), context)
        {bch_bit, state} = Generator.integer(state, 0, 62)
        corrupted_bch = flip_bit(bch_codeword, bch_bit)

        case BCH.decode(corrupted_bch, :correct) do
          {:ok, ^bch_information, %{status: :corrected, corrected_bit: ^bch_bit}} -> :ok
          result -> flunk_result(result, context)
        end

        {ldpc_code, state} = Generator.member(state, [:ldpc_128_64, :ldpc_512_256])
        {ldpc_information, state} = Generator.binary(state, LDPC.information_octets(ldpc_code))
        ldpc_codeword = expect_ok(LDPC.encode(ldpc_information, ldpc_code), context)
        {ldpc_bit, state} = Generator.integer(state, 0, bit_size(ldpc_codeword) - 1)
        corrupted_ldpc = flip_bit(ldpc_codeword, ldpc_bit)

        case LDPC.decode(corrupted_ldpc, ldpc_code) do
          {:ok, ^ldpc_information, %{status: :corrected, corrected_bit: ^ldpc_bit}} -> :ok
          result -> flunk_result(result, context)
        end

        {configuration, state} = channel_configuration(state)
        {data_octets, state} = Generator.integer(state, 1, 128)
        {data, state} = Generator.binary(state, data_octets)

        {cltu, _metadata} = expect_ok3(CLTU.encode(data, configuration), context)

        case CLTU.decode(cltu, configuration, expected_data_octets: byte_size(data)) do
          {:ok, %{data: ^data, quality: %{status: :clean, fill_valid?: true}}} -> :ok
          result -> flunk_result(result, context)
        end

        state
      end)

    assert is_tuple(final_state)
  end

  test "seeded arbitrary malformed inputs never crash wire decoders" do
    final_state =
      Enum.reduce(1..@cases, Generator.seed(@seed + 4), fn case_number, state ->
        {octets, state} = Generator.integer(state, 0, 128)
        {input, state} = Generator.binary(state, octets)
        context = context(:malformed_input, case_number)

        assert_tuple(SpacePacketCodec.decode_prefix(input), context)
        assert_tuple(TransferFrame.decode(input, frame_size: 128), context)
        assert_tuple(TMFrameCodec.decode_detailed(input, frame_size: 32), context)

        assert_tuple(
          CLTU.decode(input, Configuration.new!(), expected_data_octets: 1),
          context
        )

        state
      end)

    assert is_tuple(final_state)
  end

  defp space_packet(state) do
    {packet_type, state} = Generator.member(state, [:telemetry, :command])
    {secondary_header?, state} = Generator.boolean(state)
    {apid, state} = Generator.integer(state, 0, 0x7FF)

    {sequence_flag, state} =
      Generator.member(state, [:continuation, :first, :last, :unsegmented])

    {sequence_count, state} = Generator.integer(state, 0, 0x3FFF)
    {data_octets, state} = Generator.integer(state, 1, 512)
    {data, state} = Generator.binary(state, data_octets)

    packet =
      SpacePacket.new(%{
        packet_type: packet_type,
        secondary_header?: secondary_header? and apid != SpacePacket.idle_apid(),
        apid: apid,
        sequence_flag: sequence_flag,
        sequence_count: sequence_count,
        data: data
      })

    {packet, state}
  end

  defp tc_frame(state) do
    {type, state} = Generator.member(state, [{0, 0}, {1, 0}, {1, 1}])
    {bypass_flag, control_command_flag} = type
    {scid, state} = Generator.integer(state, 0, 1023)
    {vcid, state} = Generator.integer(state, 0, 63)
    {frame_seq, state} = Generator.integer(state, 0, 255)
    {fecf?, state} = Generator.boolean(state)
    {payload_octets, state} = Generator.integer(state, 1, 256)
    {payload, state} = Generator.binary(state, payload_octets)
    maximum_frame_size = 5 + payload_octets + if(fecf?, do: 2, else: 0)

    frame = %TransferFrame{
      version: 0,
      bypass_flag: bypass_flag,
      control_command_flag: control_command_flag,
      spare: 0,
      scid: scid,
      vcid: vcid,
      frame_seq: frame_seq,
      payload: payload
    }

    {frame, fecf?, maximum_frame_size, state}
  end

  defp tm_frame(state) do
    {scid, state} = Generator.integer(state, 0, 1023)
    {vcid, state} = Generator.integer(state, 0, 7)
    {mcfc, state} = Generator.integer(state, 0, 255)
    {vcfc, state} = Generator.integer(state, 0, 255)
    {fecf?, state} = Generator.boolean(state)
    {ocf?, state} = Generator.boolean(state)
    {vca?, state} = Generator.boolean(state)
    {payload_octets, state} = Generator.integer(state, 1, 256)
    {payload, state} = Generator.binary(state, payload_octets)
    {ocf, state} = if(ocf?, do: Generator.binary(state, 4), else: {nil, state})

    {meta, state} =
      if vca? do
        {packet_order_flag, state} = Generator.integer(state, 0, 1)
        {segment_length_id, state} = Generator.integer(state, 0, 3)
        {fhp, state} = Generator.integer(state, 0, 2047)

        {%{
           mcfc: mcfc,
           vcfc: vcfc,
           sync_flag: 1,
           packet_order_flag: packet_order_flag,
           segment_length_id: segment_length_id,
           fhp: fhp,
           ocf_flag: if(ocf?, do: 1, else: 0)
         }, state}
      else
        {fhp, state} = Generator.integer(state, 0, 2047)

        {%{
           mcfc: mcfc,
           vcfc: vcfc,
           sync_flag: 0,
           packet_order_flag: 0,
           segment_length_id: 3,
           fhp: fhp,
           ocf_flag: if(ocf?, do: 1, else: 0)
         }, state}
      end

    frame_size = 6 + payload_octets + if(ocf?, do: 4, else: 0) + if(fecf?, do: 2, else: 0)

    frame = %LinkFrame{
      profile: :tm,
      scid: scid,
      vcid: vcid,
      frame_seq: vcfc,
      payload_octets: payload,
      quality: :good,
      ocf: ocf,
      meta: meta
    }

    {frame, [frame_size: frame_size, fecf: fecf?], state}
  end

  defp channel_configuration(state) do
    {code, state} = Generator.member(state, [:bch, :ldpc_128_64, :ldpc_512_256])

    case code do
      :bch ->
        {randomize?, state} = Generator.boolean(state)
        {Configuration.new!(code: :bch, randomize?: randomize?), state}

      :ldpc_128_64 ->
        {tail?, state} = Generator.boolean(state)
        {Configuration.new!(code: :ldpc_128_64, ldpc_tail?: tail?), state}

      :ldpc_512_256 ->
        {Configuration.new!(code: :ldpc_512_256), state}
    end
  end

  defp flip_bit(binary, wire_bit) do
    <<prefix::bitstring-size(^wire_bit), bit::1, suffix::bitstring>> = binary
    <<prefix::bitstring, bxor(bit, 1)::1, suffix::bitstring>>
  end

  defp expect_ok({:ok, value}, _context), do: value
  defp expect_ok(result, context), do: flunk_result(result, context)

  defp expect_ok3({:ok, first, second}, _context), do: {first, second}
  defp expect_ok3(result, context), do: flunk_result(result, context)

  defp expect_single({:ok, [value], <<>>}, _context), do: value
  defp expect_single(result, context), do: flunk_result(result, context)

  defp assert_result(actual, expected, context) do
    unless actual == expected do
      flunk("#{context}: expected #{inspect(expected)}, got #{inspect(actual)}")
    end
  end

  defp assert_equal(actual, expected, context), do: assert_result(actual, expected, context)

  defp assert_tuple(value, context) do
    unless is_tuple(value), do: flunk("#{context}: expected tuple result, got #{inspect(value)}")
  end

  defp flunk_result(result, context), do: flunk("#{context}: unexpected #{inspect(result)}")
  defp context(subject, case_number), do: "#{subject} seed=#{@seed} case=#{case_number}"
end
