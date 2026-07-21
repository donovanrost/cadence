defmodule Cadence.CCSDS.NormativeVectorsTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.ChannelCoding.{BCH, CLTU, Configuration, LDPC, Randomizer}
  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.EncapsulationPacket
  alias Cadence.CCSDS.EncapsulationPacket.Codec, as: EncapsulationPacketCodec
  alias Cadence.CCSDS.EncapsulationPacket.Configuration, as: EncapsulationConfiguration
  alias Cadence.CCSDS.FrameErrorControl
  alias Cadence.CCSDS.SDLP.AOS.BPDU
  alias Cadence.CCSDS.SDLP.AOS.Configuration, as: AOSConfiguration
  alias Cadence.CCSDS.SDLP.AOS.FrameCodec, as: AOSFrameCodec
  alias Cadence.CCSDS.SDLP.AOS.FrameHeaderErrorControl
  alias Cadence.CCSDS.SDLP.AOS.MPDU
  alias Cadence.CCSDS.SDLP.AOS.OnlyIdleData, as: AOSOnlyIdleData
  alias Cadence.CCSDS.SDLP.TM.{FrameCodec, OnlyIdleData, SecondaryHeader}
  alias Cadence.CCSDS.SDLP.USLP.Configuration, as: USLPConfiguration
  alias Cadence.CCSDS.SDLP.USLP.FrameCodec, as: USLPFrameCodec
  alias Cadence.CCSDS.SDLP.USLP.OnlyIdleData, as: USLPOnlyIdleData
  alias Cadence.CCSDS.SDLS.{Channel, SecurityAssociation, SecurityHeader}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec
  alias Cadence.CCSDS.TC.{SegmentHeader, TransferFrame}
  alias Cadence.CCSDS.TestSupport.NormativeVectors
  alias Cadence.CCSDS.Time.CDS
  alias Cadence.CCSDS.Time.CDS.Codec, as: CDSCodec
  alias Cadence.CCSDS.Time.CDS.Configuration, as: CDSConfiguration
  alias Cadence.CCSDS.Time.CUC
  alias Cadence.CCSDS.Time.CUC.Codec, as: CUCCodec
  alias Cadence.CCSDS.Time.CUC.Configuration, as: CUCConfiguration
  alias Cadence.CCSDS.Transport.COP1.{CLCW, ControlCommand}

  test "corpus has complete, unique, and auditable provenance" do
    corpus = NormativeVectors.corpus()
    assert corpus.schema_version == 1
    assert map_size(corpus.sources) == 9
    assert length(corpus.vectors) >= 44

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

  test "matches all four Encapsulation Packet header derivations" do
    configuration = EncapsulationConfiguration.new!(valid_extended_protocol_ids: [5])

    for vector <- NormativeVectors.vectors_for(:encapsulation_packet) do
      packet =
        EncapsulationPacket.new(%{
          protocol_id: vector.parameters.protocol_id,
          protocol_id_extension: Map.get(vector.parameters, :protocol_id_extension),
          user_defined: Map.get(vector.parameters, :user_defined, 0),
          data: hex(vector.parameters.data_hex),
          header_octets: vector.parameters.header_octets
        })

      expected = hex(vector.expected_hex)

      assert {:ok, ^expected} =
               EncapsulationPacketCodec.encode(packet, configuration: configuration)

      assert {:ok, decoded} =
               EncapsulationPacketCodec.decode(expected, configuration: configuration)

      assert decoded.protocol_id == packet.protocol_id
      assert decoded.protocol_id_extension == packet.protocol_id_extension
      assert decoded.user_defined == packet.user_defined
      assert decoded.data == packet.data
      assert decoded.header_octets == packet.header_octets
    end
  end

  test "matches the CUC P-field and T-field derivations" do
    for vector <- NormativeVectors.vectors_for(:cuc_time_code) do
      parameters = vector.parameters

      configuration =
        CUCConfiguration.new!(
          epoch: parameters.epoch,
          coarse_octets: parameters.coarse_octets,
          fine_octets: parameters.fine_octets,
          mission_bits: parameters.mission_bits
        )

      value =
        CUC.new!(
          coarse_time: parameters.coarse_time,
          fine_time: parameters.fine_time,
          configuration: configuration
        )

      expected = hex(vector.expected_hex)
      assert {:ok, ^expected} = CUCCodec.encode(value)
      assert {:ok, ^value} = CUCCodec.decode(expected)
    end
  end

  test "matches the CDS P-field and T-field derivations" do
    for vector <- NormativeVectors.vectors_for(:cds_time_code) do
      parameters = vector.parameters

      configuration =
        CDSConfiguration.new!(
          epoch: parameters.epoch,
          day_octets: parameters.day_octets,
          submillisecond_octets: parameters.submillisecond_octets
        )

      value =
        CDS.new!(
          day_count: parameters.day_count,
          milliseconds_of_day: parameters.milliseconds_of_day,
          submilliseconds: parameters.submilliseconds,
          configuration: configuration
        )

      expected = hex(vector.expected_hex)
      assert {:ok, ^expected} = CDSCodec.encode(value)
      assert {:ok, ^value} = CDSCodec.decode(expected)
    end
  end

  test "matches the SDLS TC and TM baseline Security Header derivations" do
    for vector <- NormativeVectors.vectors_for(:sdls_security_header) do
      parameters = vector.parameters

      association =
        sdls_association(
          parameters.profile,
          parameters.spi,
          parameters.iv_octets,
          parameters.sequence_octets,
          parameters.pad_length_octets
        )

      header = %SecurityHeader{
        spi: parameters.spi,
        initialization_vector: hex(parameters.iv_hex),
        sequence_number: parameters.sequence_number,
        pad_length: 0
      }

      expected = hex(vector.expected_hex)
      assert {:ok, ^expected} = SecurityHeader.encode(header, association)
      assert {:ok, ^header, <<>>, ^expected} = SecurityHeader.decode_prefix(expected, association)
    end
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

  test "matches AOS issue-5 header, FHEC, M_PDU, B_PDU, and OID derivations" do
    frame_vector = NormativeVectors.vector!("aos-issue-5-primary-header-layout")
    parameters = frame_vector.parameters

    configuration =
      AOSConfiguration.new!(
        frame_size: byte_size(hex(frame_vector.expected_hex)),
        scid: parameters.scid,
        vcid: parameters.vcid,
        data_field_content: :vca_sdu
      )

    frame = %LinkFrame{
      profile: :aos,
      scid: parameters.scid,
      vcid: parameters.vcid,
      frame_seq: parameters.vcfc,
      payload_octets: hex(parameters.payload_hex),
      quality: :good,
      meta: %{
        vcfc: parameters.vcfc,
        replay_flag: parameters.replay_flag,
        vc_frame_count_cycle_use_flag: parameters.cycle_use_flag,
        vc_frame_count_cycle: parameters.cycle
      }
    }

    expected_frame = hex(frame_vector.expected_hex)
    assert {:ok, ^expected_frame} = AOSFrameCodec.encode(frame, configuration: configuration)

    fhec = NormativeVectors.vector!("aos-frame-header-error-control")

    assert {:ok, encoded_fhec} =
             FrameHeaderErrorControl.encode(
               fhec.parameters.protected_header,
               fhec.parameters.signaling
             )

    assert <<encoded_fhec::16>> == hex(fhec.expected_hex)

    mpdu = NormativeVectors.vector!("aos-mpdu-layout")

    assert {:ok, encoded_mpdu} =
             MPDU.encode(%MPDU{
               first_header_pointer: mpdu.parameters.first_header_pointer,
               packet_zone: hex(mpdu.parameters.packet_zone_hex)
             })

    assert encoded_mpdu == hex(mpdu.expected_hex)

    bpdu = NormativeVectors.vector!("aos-bpdu-layout")

    assert {:ok, encoded_bpdu} =
             BPDU.encode(%BPDU{
               bitstream_data_pointer: bpdu.parameters.bitstream_data_pointer,
               data_zone: hex(bpdu.parameters.data_zone_hex)
             })

    assert encoded_bpdu == hex(bpdu.expected_hex)

    oid = NormativeVectors.vector!("aos-oid-annex-d-prefix")
    expected_oid = hex(oid.expected_hex)
    assert {^expected_oid, _state} = AOSOnlyIdleData.take(oid.parameters.octets)
  end

  test "matches USLP Version-4, truncated-frame, and annex-H OID vectors" do
    vector = NormativeVectors.vector!("uslp-version-4-frame-layout")
    parameters = vector.parameters

    configuration =
      USLPConfiguration.new!(
        frame_type: :variable,
        frame_size: 64,
        scid: parameters.scid,
        vcid: parameters.vcid,
        map_id: parameters.map_id,
        source_destination: parameters.source_destination,
        sequence_count_octets: parameters.count_octets,
        expedited_count_octets: 1,
        data_field_content: :mapa_sdu
      )

    frame = %LinkFrame{
      profile: :uslp,
      scid: parameters.scid,
      vcid: parameters.vcid,
      map_id: parameters.map_id,
      frame_seq: parameters.count,
      payload_octets: hex(parameters.payload_hex),
      quality: :good,
      meta: %{
        qos: parameters.qos,
        construction_rule: parameters.construction_rule,
        upid: parameters.upid
      }
    }

    expected = hex(vector.expected_hex)
    assert {:ok, ^expected} = USLPFrameCodec.encode(frame, configuration: configuration)
    assert {:ok, [decoded], <<>>} = USLPFrameCodec.decode(expected, configuration: configuration)
    assert decoded.payload_octets == frame.payload_octets
    assert decoded.frame_seq == frame.frame_seq

    truncated = NormativeVectors.vector!("uslp-truncated-frame-layout")
    truncated_parameters = truncated.parameters

    truncated_configuration =
      USLPConfiguration.new!(
        frame_type: :variable,
        frame_size: 32,
        scid: truncated_parameters.scid,
        vcid: truncated_parameters.vcid,
        map_id: truncated_parameters.map_id,
        data_field_content: :mapa_sdu,
        truncated_frame_length: byte_size(hex(truncated.expected_hex))
      )

    truncated_frame = %LinkFrame{
      profile: :uslp,
      scid: truncated_parameters.scid,
      vcid: truncated_parameters.vcid,
      map_id: truncated_parameters.map_id,
      payload_octets: hex(truncated_parameters.payload_hex),
      quality: :good,
      meta: %{truncated?: true, qos: :expedited}
    }

    expected_truncated = hex(truncated.expected_hex)

    assert {:ok, ^expected_truncated} =
             USLPFrameCodec.encode(truncated_frame, configuration: truncated_configuration)

    oid = NormativeVectors.vector!("uslp-oid-annex-h-prefix")
    expected_oid = hex(oid.expected_hex)
    assert {^expected_oid, _state} = USLPOnlyIdleData.take(oid.parameters.octets)
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

  defp sdls_association(:tc, spi, _iv_octets, sequence_octets, pad_octets) do
    SecurityAssociation.new!(
      spi: spi,
      channels: [sdls_channel(:tc, 0, 1)],
      service_type: :authentication,
      sequence_number_length: sequence_octets,
      pad_length_length: pad_octets,
      mac_length: 16,
      authentication_algorithm: :cmac,
      authentication_key_ref: :normative_vector,
      authentication_mask: :binary.copy(<<0xFF>>, 128),
      sequence_number: 0,
      sequence_window: 10,
      sequence_number_source: :sequence_number
    )
  end

  defp sdls_association(:tm, spi, iv_octets, _sequence_octets, pad_octets) do
    SecurityAssociation.new!(
      spi: spi,
      channels: [sdls_channel(:tm, 0, nil)],
      service_type: :authenticated_encryption,
      initialization_vector_length: iv_octets,
      pad_length_length: pad_octets,
      mac_length: 16,
      authentication_algorithm: :gcm,
      authentication_key_ref: :normative_vector,
      authentication_mask: :binary.copy(<<0xFF>>, 128),
      sequence_number: 0,
      sequence_window: 10,
      sequence_number_source: :initialization_vector,
      encryption_algorithm: :gcm,
      encryption_key_ref: :normative_vector,
      initialization_vector: <<0::96>>
    )
  end

  defp sdls_channel(protocol, transfer_frame_version, map_id) do
    Channel.new!(
      physical_channel: "normative",
      protocol: protocol,
      transfer_frame_version: transfer_frame_version,
      scid: 1,
      vcid: 1,
      map_id: map_id
    )
  end

  defp hex(value), do: NormativeVectors.decode_hex!(value)
end
