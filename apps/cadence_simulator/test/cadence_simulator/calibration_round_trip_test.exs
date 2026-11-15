defmodule CadenceSimulator.CalibrationRoundTripTest do
  @moduledoc """
  Acceptance for calibration (#92 (c)): the simulator encodes ENGINEERING values by reversing each
  item's conversion, and Cadence's decom calibrates the raw values back. What comes out is what the
  simulator meant. The field definitions here carry the calibration exactly as a contract-3
  telemetry plan does (the catalog's own conversions, lowered by domain's mission-model change).
  """
  use ExUnit.Case, async: true

  alias Cadence.ApplicationDispatch.WorkItem
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}
  alias Cadence.Telemetry.Handlers.DefinitionBoundTelemetryHandler
  alias CadenceSimulator.PacketEncoder

  @catalog """
  packets:
    - name: THERM
      apid: 12
      items:
        - name: temp_sensor_00
          bit_offset: 0
          bit_size: 16
          data_type: uint
          endianness: big
          conversion:
            type: polynomial
            coefficients: [-40.0, 0.01]
        - name: thermal_mode
          bit_offset: 16
          bit_size: 8
          data_type: uint
          endianness: big
          conversion:
            type: state_table
            states:
              0: "SAFE"
              1: "NOMINAL"
              2: "HEATING"
  """

  @definition PacketDefinition.new(%{
                packet_definition_id: "semantic:container:therm",
                mission_id: "mission-round-trip",
                packet_name: "THERM",
                apid: 12,
                fields: [
                  FieldDefinition.new(%{
                    field_id: "temp",
                    name: "temp_sensor_00",
                    offset_bits: 0,
                    size_bits: 16,
                    calibrator: %{type: :polynomial, coefficients: [-40.0, 0.01]}
                  }),
                  FieldDefinition.new(%{
                    field_id: "mode",
                    name: "thermal_mode",
                    offset_bits: 16,
                    size_bits: 8,
                    enumerations: [
                      %{value: 0, label: "SAFE"},
                      %{value: 1, label: "NOMINAL"},
                      %{value: 2, label: "HEATING"}
                    ]
                  })
                ]
              })

  for {temperature, mode} <- [{21.5, "NOMINAL"}, {-12.25, "HEATING"}, {0.0, "SAFE"}] do
    test "#{temperature} °C and #{mode} survive encode (reverse-converted) and decom (calibrated)" do
      {:ok, encoder} = PacketEncoder.load_string(@catalog)

      {:ok, [{"THERM", packet}]} =
        PacketEncoder.encode_with_sequence(
          encoder,
          "SIM-1",
          %{
            "THERM.temp_sensor_00" => unquote(temperature),
            "THERM.thermal_mode" => unquote(mode)
          },
          fn _apid -> 0 end
        )

      # The CCSDS primary header is 6 octets; decom reads the packet data field after it.
      <<_header::binary-size(6), packet_data::binary>> = packet

      {:ok, samples} =
        DefinitionBoundTelemetryHandler.handle(record(packet_data), %WorkItem{
          binding_rule_id: "rule",
          handler_configuration: @definition
        })

      samples = Map.new(samples, &{&1.point_name, &1})

      assert_in_delta samples["THERM.temp_sensor_00"].engineering_value,
                      unquote(temperature),
                      0.01

      assert is_integer(samples["THERM.temp_sensor_00"].raw_value)
      assert samples["THERM.thermal_mode"].engineering_value == unquote(mode)
      assert is_integer(samples["THERM.thermal_mode"].raw_value)
      assert Enum.all?(Map.values(samples), &(&1.quality_state == :good))
    end
  end

  defp record(packet_data) do
    %PacketRecord{
      packet_id: "packet-round-trip",
      evidence_id: "evidence-round-trip",
      mission_id: "mission-round-trip",
      spacecraft_id: "sc-1",
      protocol_family: :space_packet,
      packet_kind: :space_packet,
      apid: 12,
      sequence_flags: 3,
      sequence_count: 0,
      secondary_header?: false,
      packet_data: packet_data,
      receipt_time: ~U[2026-11-15 12:00:00.000000Z],
      provenance: %{}
    }
  end
end
