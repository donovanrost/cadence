defmodule Cadence.CCSDS.EncapsulationPacketTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.EncapsulationPacket
  alias Cadence.CCSDS.EncapsulationPacket.{Codec, Configuration, Idle, Stream}
  alias Cadence.CCSDS.EncapsulationPacket.Service.{Provider, Request}
  alias Cadence.CCSDS.TC.Service.{PacketConfiguration, PacketFormat}

  test "encodes and decodes all four standard header sizes" do
    vectors = [
      {EncapsulationPacket.new(protocol_id: 0), 1, hex("E0")},
      {EncapsulationPacket.new(protocol_id: 1, data: hex("AABBCC")), 2, hex("E505AABBCC")},
      {EncapsulationPacket.new(
         protocol_id: 6,
         protocol_id_extension: 5,
         user_defined: 10,
         data: hex("1122")
       ), 4, hex("FAA500061122")},
      {EncapsulationPacket.new(protocol_id: 7, user_defined: 3, data: hex("AA")), 8,
       hex("FF30000000000009AA")}
    ]

    configuration = Configuration.new!(valid_extended_protocol_ids: [5])

    for {packet, header_octets, expected} <- vectors do
      assert {:ok, ^expected} =
               Codec.encode(packet,
                 configuration: configuration,
                 header_octets: header_octets
               )

      assert {:ok, decoded} = Codec.decode(expected, configuration: configuration)
      assert decoded.protocol_id == packet.protocol_id
      assert decoded.protocol_id_extension == packet.protocol_id_extension
      assert decoded.user_defined == packet.user_defined
      assert decoded.data == packet.data
      assert decoded.header_octets == header_octets
      assert {:ok, ^expected} = Codec.encode(decoded, configuration: configuration)
    end
  end

  test "adaptive encoding selects the smallest legal header" do
    assert_header(EncapsulationPacket.new(protocol_id: 0), 1)
    assert_header(EncapsulationPacket.new(protocol_id: 1, data: <<0::253*8>>), 2)
    assert_header(EncapsulationPacket.new(protocol_id: 1, data: <<0::254*8>>), 4)
    assert_header(EncapsulationPacket.new(protocol_id: 1, data: <<0::65_531*8>>), 4)
    assert_header(EncapsulationPacket.new(protocol_id: 1, data: <<0::65_532*8>>), 8)
  end

  test "streaming decoder preserves incomplete input and extracts complete packets" do
    {:ok, first} = Codec.encode(EncapsulationPacket.new(protocol_id: 1, data: <<1, 2, 3>>))
    {:ok, second} = Codec.encode(EncapsulationPacket.new(protocol_id: 4, data: <<4, 5>>))
    <<prefix::binary-size(3), suffix::binary>> = second

    assert {:ok, [decoded], ^prefix} = Stream.decode(first <> prefix)
    assert decoded.data == <<1, 2, 3>>

    assert {:ok, [decoded_first, decoded_second], <<>>} = Stream.decode(first <> prefix <> suffix)
    assert decoded_first.data == <<1, 2, 3>>
    assert decoded_second.data == <<4, 5>>
  end

  test "builds exact-size idle packets with a managed repeating pattern" do
    for size <- [1, 2, 255, 256, 65_535, 65_536] do
      assert {:ok, encoded} = Idle.encode(size, pattern: <<0xAA, 0x55>>)
      assert byte_size(encoded) == size
      assert {:ok, decoded} = Codec.decode(encoded)
      assert EncapsulationPacket.idle?(decoded)
    end
  end

  test "rejects reserved fields, invalid empty data, and malformed lengths" do
    assert {:error, :empty_data_requires_idle_protocol_id} =
             Codec.encode(EncapsulationPacket.new(protocol_id: 1))

    assert {:error, :one_octet_header_requires_idle_protocol_id} = Codec.decode(hex("E4"))

    assert {:error, {:unexpected_extended_protocol_id, 5}} =
             Codec.decode(hex("E6A50004"))

    assert {:error, {:invalid_field, :ccsds_defined, 1}} =
             Codec.encode(
               EncapsulationPacket.new(
                 protocol_id: 1,
                 ccsds_defined: 1,
                 data: <<1>>,
                 header_octets: 8
               )
             )

    assert {:error, {:invalid_encapsulation_packet_length, 1, 2}} = Codec.decode(hex("E501"))
    assert {:error, {:truncated_packet, 5, 3}} = Codec.decode(hex("E505AA"))
  end

  test "request and indication primitives preserve the SDLP channel boundary" do
    assert {:ok, provider} = Provider.init()

    request = %Request{
      data_unit: <<1, 2, 3>>,
      sdlp_channel: {:uslp, "return-1"},
      protocol_id: 4,
      meta: %{request_id: 9}
    }

    assert {:ok, encoded, ^provider} = Provider.request(request, provider)

    assert {:ok, indication, ^provider} =
             Provider.ingest(encoded, request.sdlp_channel, provider, %{frame_id: 10})

    assert indication.data_unit == request.data_unit
    assert indication.sdlp_channel == request.sdlp_channel
    assert indication.protocol_id == request.protocol_id
    assert indication.meta == %{frame_id: 10}
  end

  test "managed Packet Services delimit adaptive PVN-7 packets" do
    {:ok, space_packet} =
      Cadence.CCSDS.SpacePacket.Codec.encode(%Cadence.CCSDS.SpacePacket{
        version: 0,
        packet_type: :telemetry,
        secondary_header?: false,
        apid: 1,
        sequence_flag: :unsegmented,
        sequence_count: 2,
        data: <<1>>
      })

    {:ok, short} = Codec.encode(EncapsulationPacket.new(protocol_id: 1, data: <<2>>))

    {:ok, long} =
      Codec.encode(EncapsulationPacket.new(protocol_id: 4, user_defined: 3, data: <<3, 4>>))

    assert {:ok, configuration} =
             PacketConfiguration.new(
               valid_packet_version_numbers: [0, 7],
               maximum_packet_octets: 64,
               formats: %{
                 0 => PacketFormat.space_packet(),
                 7 => PacketFormat.encapsulation_packet()
               }
             )

    assert :ok = PacketConfiguration.validate_packet(short, 7, configuration)

    assert {:ok, extracted} =
             PacketConfiguration.extract(space_packet <> short <> long, configuration)

    assert Enum.map(extracted, &{&1.packet_version_number, &1.octets}) == [
             {0, space_packet},
             {7, short},
             {7, long}
           ]
  end

  defp assert_header(packet, expected_header_octets) do
    assert {:ok, encoded} = Codec.encode(packet)
    assert {:ok, decoded} = Codec.decode(encoded)
    assert decoded.header_octets == expected_header_octets
  end

  defp hex(value), do: Base.decode16!(value)
end
