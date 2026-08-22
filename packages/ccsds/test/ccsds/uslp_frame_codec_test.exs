defmodule CCSDS.USLPFrameCodecTest do
  use ExUnit.Case, async: true

  alias CCSDS.Core.LinkFrame
  alias CCSDS.SDLP.USLP.{Configuration, FrameCodec}

  test "round-trips a variable Version-4 frame with a seven-octet counter and OCF" do
    configuration =
      Configuration.new!(
        physical_channel: "proximity",
        frame_type: :variable,
        frame_size: 512,
        scid: 0xABCD,
        vcid: 0x2A,
        map_id: 0xD,
        source_destination: :destination,
        ocf?: true,
        sequence_count_octets: 7,
        expedited_count_octets: 2,
        data_field_content: :mapa_sdu
      )

    frame = %LinkFrame{
      profile: :uslp,
      scid: 0xABCD,
      vcid: 0x2A,
      map_id: 0xD,
      frame_seq: 0x01020304050607,
      payload_octets: <<1, 2, 3, 4>>,
      quality: :good,
      ocf: <<0xDE, 0xAD, 0xBE, 0xEF>>,
      meta: %{qos: :sequence_controlled, construction_rule: :unsegmented}
    }

    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)
    assert <<0b1100::4, 0xABCD::16, 1::1, 0x2A::6, 0xD::4, 0::1, _rest::binary>> = encoded
    assert byte_size(encoded) == 7 + 7 + 1 + 4 + 4

    assert {:ok, [decoded], <<>>} = FrameCodec.decode(encoded, configuration: configuration)
    assert decoded.payload_octets == frame.payload_octets
    assert decoded.frame_seq == frame.frame_seq
    assert decoded.ocf == frame.ocf
    assert decoded.meta.qos == :sequence_controlled
    assert decoded.meta.source_destination == :destination
    assert decoded.meta.vcf_count_length == 7
  end

  test "round-trips fixed frames with Insert Zone, pointer and FECF" do
    configuration =
      Configuration.new!(
        frame_type: :fixed,
        frame_size: 32,
        scid: 12,
        vcid: 3,
        map_id: 4,
        insert_zone_length: 2,
        fecf?: true,
        sequence_count_octets: 1,
        expedited_count_octets: 1
      )

    # 8-byte primary + 2 insert + 3 TFDF header + 17 data + 2 FECF
    frame = %LinkFrame{
      profile: :uslp,
      scid: 12,
      vcid: 3,
      map_id: 4,
      frame_seq: 7,
      payload_octets: :binary.copy(<<0xAA>>, 17),
      quality: :good,
      meta: %{
        qos: :sequence_controlled,
        construction_rule: :packets_spanning_frames,
        tfdf_pointer: 0xFFFF,
        insert_zone: <<1, 2>>
      }
    }

    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)
    assert byte_size(encoded) == 32
    assert {:ok, [decoded], <<>>} = FrameCodec.decode(encoded, configuration: configuration)
    assert decoded.payload_octets == frame.payload_octets
    assert decoded.meta.insert_zone == <<1, 2>>
    assert decoded.meta.tfdf_pointer == 0xFFFF
    assert is_integer(decoded.meta.fecf)

    <<prefix::binary-size(20), byte, suffix::binary>> = encoded
    corrupt = prefix <> <<Bitwise.bxor(byte, 1)>> <> suffix

    assert {:ok, [], [%{metadata: %{reason: {:invalid_fecf, _, _}}}], <<>>} =
             FrameCodec.decode_detailed(corrupt, configuration: configuration)
  end

  test "round-trips normative truncated frames without length, count, OCF, Insert, or FECF" do
    configuration =
      Configuration.new!(
        frame_type: :variable,
        frame_size: 64,
        scid: 0x1234,
        vcid: 5,
        map_id: 6,
        data_field_content: :mapa_sdu,
        truncated_frame_length: 12
      )

    frame = %LinkFrame{
      profile: :uslp,
      scid: 0x1234,
      vcid: 5,
      map_id: 6,
      payload_octets: <<1, 2, 3, 4, 5, 6, 7>>,
      quality: :good,
      meta: %{truncated?: true, qos: :expedited}
    }

    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)
    assert <<0b1100::4, 0x1234::16, 0::1, 5::6, 6::4, 1::1, 7::3, 5::5, _::binary>> = encoded
    assert byte_size(encoded) == 12

    assert {:ok, [decoded], <<>>} = FrameCodec.decode(encoded, configuration: configuration)
    assert decoded.frame_seq == nil
    assert decoded.payload_octets == frame.payload_octets
    assert decoded.meta.truncated?
    assert decoded.meta.qos == :expedited
  end

  test "managed decoding routes concatenated variable frames by MAP" do
    first =
      Configuration.new!(
        physical_channel: "forward",
        frame_type: :variable,
        frame_size: 128,
        scid: 3,
        vcid: 4,
        map_id: 1,
        valid_map_ids: [1, 2],
        data_field_content: :mapa_sdu
      )

    second = %{first | map_id: 2}

    first_frame = link_frame(first, <<1>>, 1)
    second_frame = link_frame(second, <<2, 3>>, 2)

    assert {:ok, first_wire} = FrameCodec.encode(first_frame, configuration: first)
    assert {:ok, second_wire} = FrameCodec.encode(second_frame, configuration: second)

    assert {:ok, decoded, [], <<>>} =
             FrameCodec.decode_managed(first_wire <> second_wire, [first, second])

    assert Enum.map(decoded, &{&1.frame.map_id, &1.frame.payload_octets}) == [
             {1, <<1>>},
             {2, <<2, 3>>}
           ]
  end

  test "preserves partial non-truncated primary headers for streaming" do
    configuration =
      Configuration.new!(
        frame_type: :variable,
        frame_size: 64,
        scid: 1,
        vcid: 2,
        map_id: 3,
        data_field_content: :mapa_sdu
      )

    frame = link_frame(configuration, <<1, 2, 3>>, 0)
    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)

    for size <- 0..(byte_size(encoded) - 1) do
      prefix = binary_part(encoded, 0, size)

      assert {:ok, [], [], ^prefix} =
               FrameCodec.decode_detailed(prefix, configuration: configuration)
    end
  end

  defp link_frame(configuration, payload, count) do
    %LinkFrame{
      profile: :uslp,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: configuration.map_id,
      frame_seq: count,
      payload_octets: payload,
      quality: :good,
      meta: %{qos: :sequence_controlled, construction_rule: :unsegmented}
    }
  end
end
