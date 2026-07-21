defmodule Cadence.CCSDS.TC.Service.PacketConfigurationTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec
  alias Cadence.CCSDS.TC.Service.{PacketConfiguration, PacketFormat}

  test "validates and extracts blocked Space Packets by their standard length fields" do
    packet_1 = space_packet(1, <<1>>)
    packet_2 = space_packet(2, <<2, 3, 4>>)
    configuration = packet_configuration()

    assert :ok = PacketConfiguration.validate_packet(packet_1, 0, configuration)

    assert {:ok,
            [
              %{octets: ^packet_1, packet_version_number: 0, quality: :complete},
              %{octets: ^packet_2, packet_version_number: 0, quality: :complete}
            ]} = PacketConfiguration.extract(packet_1 <> packet_2, configuration)
  end

  test "uses managed formats for non-Space-Packet PVNs" do
    format = %PacketFormat{
      packet_version_number: 1,
      minimum_packet_octets: 2,
      length_field_offset_bits: 3,
      length_field_bits: 5,
      length_adjustment: 1
    }

    assert {:ok, configuration} =
             PacketConfiguration.new(
               valid_packet_version_numbers: [1],
               maximum_packet_octets: 32,
               formats: %{1 => format}
             )

    packet = <<1::3, 1::5, 0xAA>>
    assert :ok = PacketConfiguration.validate_packet(packet, 1, configuration)

    assert {:ok, [%{octets: ^packet, packet_version_number: 1, quality: :complete}]} =
             PacketConfiguration.extract(packet, configuration)
  end

  test "reports or delivers an incomplete final Packet according to management" do
    complete = space_packet(1, <<1, 2>>)
    <<partial::binary-size(7), _rest::binary>> = complete

    assert {:error, {:incomplete_packet, 8, 7}} =
             PacketConfiguration.extract(partial, packet_configuration())

    assert {:ok, deliver_partial} =
             PacketConfiguration.new(maximum_packet_octets: 64, deliver_incomplete?: true)

    assert {:ok, [%{octets: ^partial, packet_version_number: 0, quality: :partial}]} =
             PacketConfiguration.extract(partial, deliver_partial)
  end

  test "rejects a request PVN that differs from the Packet header" do
    packet = space_packet(1, <<1>>)

    assert {:error, {:packet_version_mismatch, 0, 1}} =
             PacketConfiguration.validate_packet(packet, 1, packet_configuration())
  end

  defp packet_configuration do
    {:ok, configuration} = PacketConfiguration.new(maximum_packet_octets: 64)
    configuration
  end

  defp space_packet(sequence_count, data) do
    packet = %SpacePacket{
      version: 0,
      packet_type: :command,
      secondary_header?: false,
      apid: 100,
      sequence_flag: :unsegmented,
      sequence_count: sequence_count,
      data: data
    }

    {:ok, encoded} = Codec.encode(packet)
    encoded
  end
end
