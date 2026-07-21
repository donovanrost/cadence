defmodule Cadence.CCSDS.NormativeVectorsTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.ChannelCoding.{BCH, CLTU, Configuration, LDPC, Randomizer}
  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.FrameErrorControl
  alias Cadence.CCSDS.SDLP.TM.{FrameCodec, OnlyIdleData, SecondaryHeader}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec
  alias Cadence.CCSDS.TC.{SegmentHeader, TransferFrame}
  alias Cadence.CCSDS.TestSupport.NormativeVectors
  alias Cadence.CCSDS.Transport.COP1.{CLCW, ControlCommand}

  test "corpus has complete, unique, and auditable provenance" do
    corpus = NormativeVectors.corpus()
    assert corpus.schema_version == 1
    assert map_size(corpus.sources) == 4
    assert length(corpus.vectors) >= 20

    ids = Enum.map(corpus.vectors, & &1.id)
    assert Enum.uniq(ids) == ids

    for {_id, source} <- corpus.sources do
      assert source.url =~ "https://ccsds.org/"
      assert source.sha256 =~ ~r/^[0-9a-f]{64}$/
      assert source.issue =~ "CCSDS"
    end

    for vector <- corpus.vectors do
      assert vector.classification in Map.keys(corpus.classifications)
      assert Map.has_key?(corpus.sources, vector.source)
      assert is_binary(vector.locator) and vector.locator != ""
      assert is_binary(vector.expected_hex)
      assert {:ok, _binary} = Base.decode16(vector.expected_hex, case: :mixed)
    end
  end

  test "matches the published TM Only Idle Data sequence" do
    vector = NormativeVectors.vector!("tm-oid-annex-d-prefix")
    expected = hex(vector.expected_hex)

    assert {^expected, _state} = OnlyIdleData.take(vector.parameters.octets)
  end

  test "matches the derived TM transfer-frame and secondary-header vectors" do
    frame_vector = NormativeVectors.vector!("tm-primary-header-layout")
    parameters = frame_vector.parameters

    frame = %LinkFrame{
      profile: :tm,
      scid: parameters.scid,
      vcid: parameters.vcid,
      frame_seq: parameters.vcfc,
      payload_octets: hex(parameters.payload_hex),
      quality: :good,
      meta: %{mcfc: parameters.mcfc, vcfc: parameters.vcfc, fhp: parameters.fhp}
    }

    expected = hex(frame_vector.expected_hex)
    assert {:ok, ^expected} = FrameCodec.encode(frame, frame_size: byte_size(expected))

    secondary_vector = NormativeVectors.vector!("tm-secondary-header-layout")

    assert {:ok, secondary_header} =
             SecondaryHeader.new(hex(secondary_vector.parameters.data_hex))

    assert {:ok, encoded} = SecondaryHeader.encode(secondary_header)
    assert encoded == hex(secondary_vector.expected_hex)
  end

  test "matches the derived Space Packet vector" do
    vector = NormativeVectors.vector!("space-packet-primary-header-layout")
    parameters = vector.parameters

    packet =
      SpacePacket.new(%{
        packet_type: parameters.packet_type,
        secondary_header?: parameters.secondary_header?,
        apid: parameters.apid,
        sequence_flag: parameters.sequence_flag,
        sequence_count: parameters.sequence_count,
        data: hex(parameters.data_hex)
      })

    expected = hex(vector.expected_hex)
    assert {:ok, ^expected} = Codec.encode(packet)
    assert {:ok, ^packet} = Codec.decode(expected)
  end

  test "matches the BCH derivations and every published LDPC generator base row" do
    for vector <- NormativeVectors.vectors_for(:bch_codeword) do
      information = hex(vector.parameters.information_hex)
      expected = hex(vector.expected_hex)
      assert {:ok, ^expected} = BCH.encode(information)
    end

    for vector <- NormativeVectors.vectors_for(:ldpc_generator_row) do
      %{code: code, row: row} = vector.parameters
      information_bits = LDPC.information_octets(code) * 8
      information = <<0::size(row - 1), 1::1, 0::size(information_bits - row)>>
      expected_parity = hex(vector.expected_hex)

      assert {:ok, <<^information::binary, ^expected_parity::binary>>} =
               LDPC.encode(information, code)
    end
  end

  test "matches the published TC randomizer and CLTU constants" do
    randomizer = NormativeVectors.vector!("tc-randomizer-first-40-bits")
    assert Randomizer.sequence(randomizer.parameters.octets) == hex(randomizer.expected_hex)

    bch_configuration = Configuration.new!()
    assert {:ok, bch, _metadata} = CLTU.encode(<<0::56>>, bch_configuration)

    assert_constant(bch, :prefix, "tc-bch-cltu-start")
    assert_constant(bch, :suffix, "tc-bch-cltu-tail")

    ldpc_configuration = Configuration.new!(code: :ldpc_128_64)
    assert {:ok, ldpc, _metadata} = CLTU.encode(<<0::64>>, ldpc_configuration)

    assert_constant(ldpc, :prefix, "tc-ldpc-cltu-start")
    assert_constant(ldpc, :suffix, "tc-ldpc-128-cltu-tail")
  end

  test "matches TC transfer-frame, Segment Header, FECF, control-command, and CLCW vectors" do
    frame_vector = NormativeVectors.vector!("tc-transfer-frame-primary-header-layout")
    frame_parameters = frame_vector.parameters

    frame = %TransferFrame{
      version: 0,
      bypass_flag: frame_parameters.bypass_flag,
      control_command_flag: frame_parameters.control_command_flag,
      spare: 0,
      scid: frame_parameters.scid,
      vcid: frame_parameters.vcid,
      frame_seq: frame_parameters.frame_seq,
      payload: hex(frame_parameters.payload_hex)
    }

    expected_frame = hex(frame_vector.expected_hex)
    assert {:ok, ^expected_frame} = TransferFrame.encode(frame, frame_size: 12)

    segment_vector = NormativeVectors.vector!("tc-segment-header-layout")

    segment = %SegmentHeader{
      sequence_flag: segment_vector.parameters.sequence_flag,
      map_id: segment_vector.parameters.map_id
    }

    expected_segment = hex(segment_vector.expected_hex)
    assert {:ok, ^expected_segment} = SegmentHeader.encode(segment)

    fecf_vector = NormativeVectors.vector!("tc-fecf-derived-check")
    input = hex(fecf_vector.parameters.input_hex)
    expected_fecf = hex(fecf_vector.expected_hex)
    assert FrameErrorControl.append(input) == input <> expected_fecf

    for vector <- NormativeVectors.vectors_for(:cop1_control_command) do
      expected = hex(vector.expected_hex)
      assert {:ok, ^expected} = ControlCommand.encode(vector.parameters.command)
    end

    clcw_vector = NormativeVectors.vector!("tc-clcw-layout")
    clcw = CLCW.new(Map.merge(clcw_vector.parameters, %{control_word_type: 0, version: 0}))
    expected_clcw = hex(clcw_vector.expected_hex)
    assert {:ok, ^expected_clcw} = CLCW.encode(clcw)
  end

  defp assert_constant(binary, side, vector_id) do
    expected = vector_id |> NormativeVectors.vector!() |> Map.fetch!(:expected_hex) |> hex()
    size = byte_size(expected)

    actual =
      case side do
        :prefix -> binary_part(binary, 0, size)
        :suffix -> binary_part(binary, byte_size(binary) - size, size)
      end

    assert actual == expected
  end

  defp hex(value), do: NormativeVectors.decode_hex!(value)
end
