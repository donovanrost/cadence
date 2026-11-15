defmodule Cadence.Telemetry.Handlers.CalibratedDecomTest do
  @moduledoc """
  Decom applies each field's calibration (#92 (c)): the raw value stays as decoded, the engineering
  value is calibrated, the identity still hashes the raw value, and provenance says what
  calibrated it.
  """
  use ExUnit.Case, async: true

  alias Cadence.ApplicationDispatch.WorkItem
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}
  alias Cadence.Telemetry.Handlers.DefinitionBoundTelemetryHandler, as: Handler

  @mission "mission-calibration"

  defp definition(temperature_attrs, mode_attrs) do
    PacketDefinition.new(%{
      packet_definition_id: "semantic:container:hk",
      mission_id: @mission,
      packet_name: "HK",
      apid: 42,
      fields: [
        FieldDefinition.new(
          Map.merge(
            %{field_id: "temp", name: "temp_sensor_00", offset_bits: 0, size_bits: 16},
            temperature_attrs
          )
        ),
        FieldDefinition.new(
          Map.merge(
            %{field_id: "mode", name: "sc_mode", offset_bits: 16, size_bits: 8},
            mode_attrs
          )
        )
      ]
    })
  end

  # temp_sensor_00 = 6000 counts, sc_mode = 4.
  defp record do
    %PacketRecord{
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      mission_id: @mission,
      spacecraft_id: "sc-1",
      protocol_family: :space_packet,
      packet_kind: :space_packet,
      apid: 42,
      sequence_flags: 3,
      sequence_count: 9,
      secondary_header?: false,
      packet_data: <<6000::16, 4::8>>,
      source_time: nil,
      receipt_time: ~U[2026-11-15 12:00:00.000000Z],
      provenance: %{}
    }
  end

  defp decom(definition) do
    {:ok, samples} =
      Handler.handle(record(), %WorkItem{
        binding_rule_id: "rule-1",
        handler_configuration: definition
      })

    Map.new(samples, &{&1.point_name, &1})
  end

  test "a polynomial field's engineering value is calibrated; an enumerated field reads its label" do
    samples =
      decom(
        definition(
          %{calibrator: %{type: :polynomial, coefficients: [-40.0, 0.01]}},
          %{enumerations: [%{value: 0, label: "SAFE"}, %{value: 4, label: "NOMINAL"}]}
        )
      )

    assert %{raw_value: 6000, engineering_value: 20.0, quality_state: :good} =
             samples["HK.temp_sensor_00"]

    assert samples["HK.temp_sensor_00"].provenance.calibration ==
             %{"kind" => "polynomial", "coefficients" => [-40.0, 0.01]}

    assert %{raw_value: 4, engineering_value: "NOMINAL", quality_state: :good} =
             samples["HK.sc_mode"]
  end

  test "calibration doesn't change a sample's identity (it hashes the raw value)" do
    calibrated =
      decom(
        definition(
          %{calibrator: %{type: :polynomial, coefficients: [-40.0, 0.01]}},
          %{enumerations: [%{value: 4, label: "NOMINAL"}]}
        )
      )

    plain = decom(definition(%{}, %{}))

    for point <- ["HK.temp_sensor_00", "HK.sc_mode"] do
      assert calibrated[point].sample_id == plain[point].sample_id
    end
  end

  test "a contract-2 definition (no calibration) keeps engineering = raw and adds no provenance" do
    samples = decom(definition(%{}, %{}))

    assert %{raw_value: 6000, engineering_value: 6000, quality_state: :good} =
             samples["HK.temp_sensor_00"]

    refute Map.has_key?(samples["HK.temp_sensor_00"].provenance, :calibration)
  end

  test "an undefined state is kept raw with quality suspect and says why" do
    samples = decom(definition(%{}, %{enumerations: [%{value: 0, label: "SAFE"}]}))

    assert %{engineering_value: 4, quality_state: :suspect} = samples["HK.sc_mode"]
    assert samples["HK.sc_mode"].provenance.calibration["reason"] == "state_not_defined"
  end
end
