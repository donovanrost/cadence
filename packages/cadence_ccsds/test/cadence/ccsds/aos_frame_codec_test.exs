defmodule Cadence.CCSDS.SDLP.AOS.FrameCodecTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.AOS.{Configuration, FrameCodec}

  test "round-trips the issue-5 SCID, FHEC, Insert, M_PDU, OCF, and FECF" do
    configuration = configuration()

    frame = %LinkFrame{
      profile: :aos,
      scid: 0x321,
      vcid: 5,
      frame_seq: 0xA0B0C0,
      payload_octets: :binary.copy(<<0xAA>>, Configuration.payload_octets(configuration)),
      quality: :good,
      ocf: <<1, 2, 3, 4>>,
      meta: %{
        vcfc: 0xA0B0C0,
        replay_flag: 1,
        vc_frame_count_cycle_use_flag: 1,
        vc_frame_count_cycle: 9,
        insert_zone: <<0xCA, 0xFE>>,
        first_header_pointer: 0
      }
    }

    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)
    assert byte_size(encoded) == configuration.frame_size

    assert {:ok, [decoded], <<>>} = FrameCodec.decode(encoded, configuration: configuration)
    assert decoded.scid == 0x321
    assert decoded.vcid == 5
    assert decoded.meta.vcfc == 0xA0B0C0
    assert decoded.meta.vc_frame_count_cycle == 9
    assert decoded.meta.insert_zone == <<0xCA, 0xFE>>
    assert decoded.meta.first_header_pointer == 0
    assert decoded.ocf == <<1, 2, 3, 4>>
    assert decoded.meta.frame_header_error_control_status == :clean
  end

  test "uses FHEC to repair a protected header symbol before validating FECF" do
    configuration = configuration()
    frame = frame(configuration)
    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)
    <<first, rest::binary>> = encoded
    corrupted = <<Bitwise.bxor(first, 0x10), rest::binary>>

    assert {:ok, [decoded], [], <<>>} =
             FrameCodec.decode_detailed(corrupted, configuration: configuration)

    assert decoded.frame.scid == frame.scid
    assert decoded.frame.meta.frame_header_error_control_status == :corrected
    assert length(decoded.frame.meta.corrected_header_symbols) == 1
  end

  test "routes a mixed-VC physical stream after FHEC correction" do
    packet_configuration =
      Configuration.new!(
        frame_size: 24,
        scid: 0x321,
        vcid: 5,
        valid_vcids: [5, 6, 63],
        frame_header_error_control?: true,
        maximum_packet_octets: 128
      )

    access_configuration =
      Configuration.new!(
        frame_size: 24,
        scid: 0x321,
        vcid: 6,
        valid_vcids: [5, 6, 63],
        frame_header_error_control?: true,
        data_field_content: :vca_sdu
      )

    packet_frame = %LinkFrame{
      profile: :aos,
      scid: 0x321,
      vcid: 5,
      frame_seq: 1,
      payload_octets: :binary.copy(<<1>>, Configuration.payload_octets(packet_configuration)),
      quality: :good,
      meta: %{
        vcfc: 1,
        vc_frame_count_cycle_use_flag: 0,
        vc_frame_count_cycle: 0,
        replay_flag: 0,
        first_header_pointer: 0
      }
    }

    access_frame = %LinkFrame{
      profile: :aos,
      scid: 0x321,
      vcid: 6,
      frame_seq: 2,
      payload_octets: :binary.copy(<<2>>, Configuration.payload_octets(access_configuration)),
      quality: :good,
      meta: %{
        vcfc: 2,
        vc_frame_count_cycle_use_flag: 0,
        vc_frame_count_cycle: 0,
        replay_flag: 0
      }
    }

    assert {:ok, first} = FrameCodec.encode(packet_frame, configuration: packet_configuration)
    assert {:ok, second} = FrameCodec.encode(access_frame, configuration: access_configuration)
    <<byte, first_rest::binary>> = first
    corrected_on_route = <<Bitwise.bxor(byte, 0x10), first_rest::binary>>

    assert {:ok, [first_evidence, second_evidence], [], <<0xAA>>} =
             FrameCodec.decode_managed(
               corrected_on_route <> second <> <<0xAA>>,
               [packet_configuration, access_configuration]
             )

    assert first_evidence.frame.vcid == 5
    assert first_evidence.frame.meta.frame_header_error_control_status == :corrected
    assert second_evidence.frame.vcid == 6
  end

  defp frame(configuration) do
    %LinkFrame{
      profile: :aos,
      scid: 0x321,
      vcid: 5,
      frame_seq: 7,
      payload_octets: :binary.copy(<<0x55>>, Configuration.payload_octets(configuration)),
      quality: :good,
      ocf: <<0, 0, 0, 1>>,
      meta: %{
        vcfc: 7,
        replay_flag: 0,
        vc_frame_count_cycle_use_flag: 0,
        vc_frame_count_cycle: 0,
        insert_zone: <<1, 2>>,
        first_header_pointer: 0
      }
    }
  end

  defp configuration do
    Configuration.new!(
      frame_size: 32,
      scid: 0x321,
      vcid: 5,
      frame_header_error_control?: true,
      insert_zone_length: 2,
      fecf?: true,
      ocf?: true
    )
  end
end
