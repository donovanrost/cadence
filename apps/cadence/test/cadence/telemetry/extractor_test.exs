defmodule Cadence.Telemetry.ExtractorTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.{Extractor, PacketDefinition}

  test "decodes little-endian integer and float fields" do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_name: "THERM",
        apid: 42,
        fields: [
          %{
            name: "counter",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint,
            byte_order: :little_endian
          },
          %{
            name: "temperature_c",
            offset_bits: 16,
            size_bits: 32,
            data_type: :float,
            byte_order: :little_endian
          }
        ]
      })

    packet_data = <<500::little-unsigned-integer-size(16), 12.5::little-float-32>>

    assert {:ok, [{counter_field, 500}, {temperature_field, 12.5}]} =
             Extractor.extract(packet_data, packet_definition)

    assert counter_field.byte_order == :little_endian
    assert temperature_field.byte_order == :little_endian
  end

  test "rejects little-endian multi-byte fields that are not byte-aligned" do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_name: "THERM",
        apid: 42,
        fields: [
          %{
            name: "counter",
            offset_bits: 4,
            size_bits: 16,
            data_type: :uint,
            byte_order: :little_endian
          }
        ]
      })

    assert {:error, {"counter", {:little_endian_requires_byte_alignment, 4, 16}}} =
             Extractor.extract(<<0, 0, 0>>, packet_definition)
  end
end
