defmodule Cadence.CCSDS.GenerativeConformanceTest do
  use ExUnit.Case, async: false

  import Bitwise

  alias Cadence.CCSDS.ChannelCoding.{BCH, CLTU, Configuration, LDPC, Randomizer}
  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.EncapsulationPacket
  alias Cadence.CCSDS.EncapsulationPacket.Codec, as: EncapsulationPacketCodec
  alias Cadence.CCSDS.SDLP.AOS.Configuration, as: AOSConfiguration
  alias Cadence.CCSDS.SDLP.AOS.FrameCodec, as: AOSFrameCodec
  alias Cadence.CCSDS.SDLP.TM.FrameCodec, as: TMFrameCodec
  alias Cadence.CCSDS.SDLP.USLP.Configuration, as: USLPConfiguration
  alias Cadence.CCSDS.SDLP.USLP.FrameCodec, as: USLPFrameCodec
  alias Cadence.CCSDS.SDLS.{ApplyRequest, Channel, ProcessRequest}
  alias Cadence.CCSDS.SDLS.Provider, as: SDLSProvider
  alias Cadence.CCSDS.SDLS.SecurityAssociation
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec
  alias Cadence.CCSDS.TC.TransferFrame
  alias Cadence.CCSDS.TestSupport.DeterministicGenerator, as: Generator
  alias Cadence.CCSDS.TestSupport.SDLSTestCryptoProvider

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

  test "seeded fixed-length AOS content types and optional fields round-trip" do
    final_state =
      Enum.reduce(1..@cases, Generator.seed(@seed + 5), fn case_number, state ->
        {frame, configuration, state} = aos_frame(state)
        context = context(:aos_transfer_frame, case_number)
        options = [configuration: configuration]

        encoded = expect_ok(AOSFrameCodec.encode(frame, options), context)

        decoded =
          case AOSFrameCodec.decode(encoded, options) do
            {:ok, [decoded], <<>>} -> decoded
            result -> flunk_result(result, context)
          end

        assert_equal(decoded.scid, frame.scid, context)
        assert_equal(decoded.vcid, frame.vcid, context)
        assert_equal(decoded.frame_seq, frame.frame_seq, context)
        assert_equal(decoded.payload_octets, frame.payload_octets, context)
        assert_equal(decoded.ocf, frame.ocf, context)
        assert_equal(decoded.meta.insert_zone, frame.meta.insert_zone || <<>>, context)
        assert_equal(decoded.meta.replay_flag, frame.meta.replay_flag, context)

        assert_equal(
          decoded.meta.vc_frame_count_cycle,
          frame.meta.vc_frame_count_cycle,
          context
        )

        state
      end)

    assert is_tuple(final_state)
  end

  test "seeded fixed- and variable-length USLP Version-4 frames round-trip" do
    final_state =
      Enum.reduce(1..@cases, Generator.seed(@seed + 6), fn case_number, state ->
        {frame, configuration, state} = uslp_frame(state)
        context = context(:uslp_transfer_frame, case_number)
        options = [configuration: configuration]

        encoded = expect_ok(USLPFrameCodec.encode(frame, options), context)

        decoded =
          case USLPFrameCodec.decode(encoded, options) do
            {:ok, [decoded], <<>>} -> decoded
            result -> flunk_result(result, context)
          end

        assert_equal(decoded.scid, frame.scid, context)
        assert_equal(decoded.vcid, frame.vcid, context)
        assert_equal(decoded.map_id, frame.map_id, context)
        assert_equal(decoded.frame_seq, frame.frame_seq, context)
        assert_equal(decoded.payload_octets, frame.payload_octets, context)
        assert_equal(decoded.ocf, frame.ocf, context)
        assert_equal(decoded.meta.qos, frame.meta.qos, context)
        assert_equal(decoded.meta.construction_rule, frame.meta.construction_rule, context)
        state
      end)

    assert is_tuple(final_state)
  end

  test "seeded adaptive Encapsulation Packets and streaming boundaries round-trip" do
    final_state =
      Enum.reduce(1..@cases, Generator.seed(@seed + 7), fn case_number, state ->
        {protocol_id, state} = Generator.member(state, [0, 1, 2, 3, 4, 7])
        {user_defined, state} = Generator.integer(state, 0, 15)
        {data_octets, state} = Generator.integer(state, 1, 1_024)
        {data, state} = Generator.binary(state, data_octets)
        context = context(:encapsulation_packet, case_number)

        packet =
          EncapsulationPacket.new(
            protocol_id: protocol_id,
            user_defined: user_defined,
            data: data
          )

        encoded = expect_ok(EncapsulationPacketCodec.encode(packet), context)
        decoded = expect_ok(EncapsulationPacketCodec.decode(encoded), context)
        assert_equal(decoded.protocol_id, protocol_id, context)
        assert_equal(decoded.user_defined, user_defined, context)
        assert_equal(decoded.data, data, context)

        assert_equal(
          expect_ok(EncapsulationPacketCodec.encode(decoded), context),
          encoded,
          context
        )

        {split, state} = Generator.integer(state, 0, byte_size(encoded) - 1)
        <<prefix::binary-size(^split), suffix::binary>> = encoded

        assert_result(
          EncapsulationPacketCodec.decode_prefix(prefix),
          {:incomplete, prefix},
          context
        )

        assert_result(
          EncapsulationPacketCodec.decode_prefix(prefix <> suffix),
          {:ok, decoded, <<>>},
          context
        )

        state
      end)

    assert is_tuple(final_state)
  end

  test "seeded algorithm-neutral SDLS authentication and anti-replay state round-trip" do
    provider = sdls_provider()

    {final_provider, final_generator} =
      Enum.reduce(
        1..@cases,
        {provider, Generator.seed(@seed + 8)},
        fn case_number, {provider, generator} ->
          {frame_prefix, generator} = Generator.binary(generator, 6)
          {data_octets, generator} = Generator.integer(generator, 0, 256)
          {data, generator} = Generator.binary(generator, data_octets)
          context = context(:sdls_authentication, case_number)

          request = %ApplyRequest{
            channel: sdls_channel(),
            service: :map_packet,
            frame_prefix: frame_prefix,
            data: data
          }

          {applied, sender} =
            expect_ok3(SDLSProvider.apply_security(request, provider), context)

          process = %ProcessRequest{
            channel: request.channel,
            service: request.service,
            frame_prefix: request.frame_prefix,
            secured_payload: applied.payload
          }

          {processed, receiver} =
            expect_ok3(SDLSProvider.process_security(process, sender), context)

          assert_equal(processed.data, data, context)
          assert_equal(processed.verification.code, :no_failure, context)
          {receiver, generator}
        end
      )

    assert %SDLSProvider{} = final_provider
    assert is_tuple(final_generator)
  end

  test "seeded arbitrary malformed inputs never crash wire decoders" do
    aos_configuration =
      AOSConfiguration.new!(
        frame_size: 32,
        scid: 1,
        vcid: 1,
        frame_header_error_control?: true,
        fecf?: true,
        maximum_packet_octets: 128
      )

    uslp_configuration =
      USLPConfiguration.new!(
        frame_type: :variable,
        frame_size: 128,
        scid: 1,
        vcid: 1,
        map_id: 1,
        data_field_content: :mapa_sdu
      )

    final_state =
      Enum.reduce(1..@cases, Generator.seed(@seed + 4), fn case_number, state ->
        {octets, state} = Generator.integer(state, 0, 128)
        {input, state} = Generator.binary(state, octets)
        context = context(:malformed_input, case_number)

        assert_tuple(SpacePacketCodec.decode_prefix(input), context)
        assert_tuple(EncapsulationPacketCodec.decode_prefix(input), context)
        assert_tuple(TransferFrame.decode(input, frame_size: 128), context)
        assert_tuple(TMFrameCodec.decode_detailed(input, frame_size: 32), context)

        assert_tuple(
          AOSFrameCodec.decode_detailed(input, configuration: aos_configuration),
          context
        )

        assert_tuple(
          USLPFrameCodec.decode_detailed(input, configuration: uslp_configuration),
          context
        )

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

  defp sdls_provider do
    association =
      SecurityAssociation.new!(
        spi: 0x4567,
        channels: [sdls_channel()],
        service_type: :authentication,
        active?: true,
        sequence_number_length: 4,
        mac_length: 8,
        authentication_algorithm: :test_hash,
        authentication_key_ref: :generative_key,
        authentication_mask: :binary.copy(<<0xFF>>, 1_024),
        sequence_number: 0,
        sequence_window: 4,
        sequence_number_source: :sequence_number
      )

    {:ok, provider} = SDLSProvider.init([association], SDLSTestCryptoProvider)
    provider
  end

  defp sdls_channel do
    Channel.new!(
      physical_channel: "generative",
      protocol: :tc,
      transfer_frame_version: 0,
      scid: 1,
      vcid: 1,
      map_id: 1
    )
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

  defp aos_frame(state) do
    {scid, state} = Generator.integer(state, 0, 1023)
    {vcid, state} = Generator.integer(state, 0, 62)
    {vcfc, state} = Generator.integer(state, 0, 0xFFFFFF)
    {replay, state} = Generator.integer(state, 0, 1)
    {cycle_use?, state} = Generator.boolean(state)

    {cycle, state} = aos_cycle(state, cycle_use?)

    {content, state} = Generator.member(state, [:m_pdu, :b_pdu, :vca_sdu])
    {fhec?, state} = Generator.boolean(state)
    {fecf?, state} = Generator.boolean(state)
    {ocf?, state} = Generator.boolean(state)
    {insert_octets, state} = Generator.integer(state, 0, 4)
    {payload_octets, state} = Generator.integer(state, 1, 128)
    {payload, state} = Generator.binary(state, payload_octets)
    {insert, state} = Generator.binary(state, insert_octets)
    {ocf, state} = aos_ocf(state, ocf?)

    fields = %{
      scid: scid,
      vcid: vcid,
      vcfc: vcfc,
      replay: replay,
      cycle_use?: cycle_use?,
      cycle: cycle,
      content: content,
      fhec?: fhec?,
      fecf?: fecf?,
      ocf?: ocf?,
      insert_octets: insert_octets,
      payload_octets: payload_octets,
      payload: payload,
      insert: insert,
      ocf: ocf
    }

    configuration = aos_configuration(fields)

    meta =
      %{
        vcfc: fields.vcfc,
        replay_flag: fields.replay,
        vc_frame_count_cycle_use_flag: bool_bit(fields.cycle_use?),
        vc_frame_count_cycle: fields.cycle,
        insert_zone: optional_binary(fields.insert)
      }
      |> Map.merge(aos_content_meta(fields.content))

    frame = %LinkFrame{
      profile: :aos,
      scid: fields.scid,
      vcid: fields.vcid,
      frame_seq: fields.vcfc,
      payload_octets: fields.payload,
      quality: :good,
      ocf: fields.ocf,
      meta: meta
    }

    {frame, configuration, state}
  end

  defp aos_configuration(fields) do
    {versions, maximum} = aos_packet_parameters(fields.content)

    AOSConfiguration.new!(
      frame_size: aos_frame_size(fields),
      scid: fields.scid,
      vcid: fields.vcid,
      frame_header_error_control?: fields.fhec?,
      insert_zone_length: fields.insert_octets,
      fecf?: fields.fecf?,
      data_field_content: fields.content,
      ocf?: fields.ocf?,
      maximum_packet_octets: maximum,
      valid_packet_version_numbers: versions
    )
  end

  defp aos_frame_size(fields) do
    6 + optional_octets(fields.fhec?, 2) + fields.insert_octets +
      aos_pdu_header_octets(fields.content) + fields.payload_octets +
      optional_octets(fields.ocf?, 4) + optional_octets(fields.fecf?, 2)
  end

  defp aos_cycle(state, true), do: Generator.integer(state, 0, 15)
  defp aos_cycle(state, false), do: {0, state}
  defp aos_ocf(state, true), do: Generator.binary(state, 4)
  defp aos_ocf(state, false), do: {nil, state}
  defp aos_packet_parameters(:m_pdu), do: {[0], 128}
  defp aos_packet_parameters(_content), do: {[], nil}
  defp aos_content_meta(:m_pdu), do: %{first_header_pointer: 0}
  defp aos_content_meta(:b_pdu), do: %{bitstream_data_pointer: 0x3FFF}
  defp aos_content_meta(:vca_sdu), do: %{}
  defp aos_pdu_header_octets(content) when content in [:m_pdu, :b_pdu], do: 2
  defp aos_pdu_header_octets(:vca_sdu), do: 0
  defp optional_octets(true, octets), do: octets
  defp optional_octets(false, _octets), do: 0
  defp optional_binary(<<>>), do: nil
  defp optional_binary(binary), do: binary
  defp bool_bit(true), do: 1
  defp bool_bit(false), do: 0

  defp uslp_frame(state) do
    {frame_type, state} = Generator.member(state, [:fixed, :variable])
    {scid, state} = Generator.integer(state, 0, 65_535)
    {vcid, state} = Generator.integer(state, 0, 62)
    {map_id, state} = Generator.integer(state, 0, 15)
    {source_destination, state} = Generator.member(state, [:source, :destination])
    {qos, state} = Generator.member(state, [:sequence_controlled, :expedited])
    {count_octets, state} = Generator.integer(state, 0, 7)
    {count, state} = uslp_count(state, count_octets)
    {fecf?, state} = Generator.boolean(state)
    {ocf?, state} = Generator.boolean(state)
    {insert_octets, state} = uslp_insert_octets(state, frame_type)
    {payload_octets, state} = Generator.integer(state, 1, 128)
    {payload, state} = Generator.binary(state, payload_octets)
    {insert, state} = Generator.binary(state, insert_octets)
    {ocf, state} = aos_ocf(state, ocf?)

    rule = if(frame_type == :fixed, do: :start_access_sdu, else: :unsegmented)
    pointer = if(frame_type == :fixed, do: payload_octets - 1, else: nil)
    primary_octets = 7 + count_octets
    tfdf_octets = if(frame_type == :fixed, do: 3, else: 1)

    frame_size =
      primary_octets + insert_octets + tfdf_octets + payload_octets +
        optional_octets(ocf?, 4) + optional_octets(fecf?, 2)

    configuration =
      USLPConfiguration.new!(
        frame_type: frame_type,
        frame_size: frame_size,
        scid: scid,
        vcid: vcid,
        map_id: map_id,
        source_destination: source_destination,
        insert_zone_length: insert_octets,
        fecf?: fecf?,
        ocf?: ocf?,
        sequence_count_octets: count_octets,
        expedited_count_octets: count_octets,
        data_field_content: :mapa_sdu
      )

    frame = %LinkFrame{
      profile: :uslp,
      scid: scid,
      vcid: vcid,
      map_id: map_id,
      frame_seq: count,
      payload_octets: payload,
      quality: :good,
      ocf: ocf,
      meta: %{
        qos: qos,
        vcf_count: count,
        vcf_count_length: count_octets,
        construction_rule: rule,
        tfdf_pointer: pointer,
        insert_zone: optional_binary(insert)
      }
    }

    {frame, configuration, state}
  end

  defp uslp_count(state, 0), do: {nil, state}
  defp uslp_count(state, octets), do: Generator.integer(state, 0, Integer.pow(256, octets) - 1)
  defp uslp_insert_octets(state, :fixed), do: Generator.integer(state, 0, 4)
  defp uslp_insert_octets(state, :variable), do: {0, state}

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
