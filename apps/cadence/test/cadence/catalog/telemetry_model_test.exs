defmodule Cadence.Catalog.TelemetryModelTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Catalog.Telemetry.{
    CalibrationAlgorithm,
    MatchCriteria,
    Packet,
    PacketEntry,
    Point,
    Snapshot,
    Type
  }

  test "snapshot normalizes nested telemetry catalog definitions" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "snapshot-alpha",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        artifact_id: "artifact-alpha",
        import_run_id: "import-run-alpha",
        importer_key: "xtce",
        snapshot_name: "Mission Alpha Telemetry",
        snapshot_version: "1.0.0",
        units: [
          %{
            unit_id: "unit-c",
            snapshot_id: "snapshot-alpha",
            name: "Celsius",
            symbol: "C"
          }
        ],
        calibration_algorithms: [
          %{
            algorithm_id: "alg-temp",
            snapshot_id: "snapshot-alpha",
            name: "temperature_poly",
            algorithm_type: "polynomial",
            polynomial_coefficients: [0.0, 0.25]
          }
        ],
        types: [
          %{
            type_id: "type-temp",
            snapshot_id: "snapshot-alpha",
            name: "TemperatureType",
            base_type: "integer",
            encoding: %{
              encoding_type: "integer",
              size_bits: 16,
              byte_order: "big_endian",
              signed: false
            },
            default_calibration_algorithm: "alg-temp",
            valid_range_min: 0,
            valid_range_max: 1023
          }
        ],
        points: [
          %{
            point_id: "point-temp",
            snapshot_id: "snapshot-alpha",
            name: "temp_c",
            display_name: "Temperature",
            type_ref: "type-temp",
            unit_ref: "unit-c",
            significance: "warning"
          }
        ],
        packets: [
          %{
            packet_id: "packet-hk",
            snapshot_id: "snapshot-alpha",
            name: "HK_PACKET",
            apid: 42,
            match_criteria: %{
              criteria_type: "compound",
              operator: "and",
              conditions: [
                %{
                  criteria_type: "comparison",
                  subject_ref: "apid",
                  comparison: "equal",
                  value: 42
                },
                %{
                  criteria_type: "range",
                  subject_ref: "packet_type",
                  comparison: "in_range",
                  range_min: 1,
                  range_max: 2
                }
              ]
            },
            entries: [
              %{
                packet_entry_id: "entry-temp",
                entry_kind: "point_ref",
                point_ref: "point-temp",
                bit_offset: 0,
                display_order: 1
              }
            ]
          }
        ]
      })

    assert snapshot.snapshot_id == "snapshot-alpha"
    assert [%{unit_id: "unit-c"}] = snapshot.units
    assert [%CalibrationAlgorithm{algorithm_id: "alg-temp"}] = snapshot.calibration_algorithms

    assert [%Type{type_id: "type-temp", default_calibration_algorithm_id: "alg-temp"}] =
             snapshot.types

    assert [%Point{point_id: "point-temp", type_id: "type-temp", unit_id: "unit-c"}] =
             snapshot.points

    assert [
             %Packet{
               packet_id: "packet-hk",
               match_criteria: %MatchCriteria{criteria_type: :compound, operator: :and},
               entries: [%PacketEntry{point_id: "point-temp", bit_offset: 0}]
             }
           ] = snapshot.packets
  end

  test "match criteria recursively normalize compound conditions" do
    criteria =
      MatchCriteria.new(%{
        criteria_type: "compound",
        operator: "or",
        conditions: [
          %{criteria_type: "comparison", subject_ref: "apid", comparison: "equal", value: 7},
          %{
            criteria_type: "compound",
            operator: "and",
            conditions: [
              %{
                criteria_type: "comparison",
                subject_ref: "vcid",
                comparison: "greater_equal",
                value: 1
              },
              %{
                criteria_type: "comparison",
                subject_ref: "vcid",
                comparison: "less_equal",
                value: 3
              }
            ]
          }
        ]
      })

    assert criteria.criteria_type == :compound
    assert criteria.operator == :or
    assert Enum.map(criteria.conditions, & &1.criteria_type) == [:comparison, :compound]

    assert Enum.at(criteria.conditions, 1).conditions |> Enum.map(& &1.comparison) == [
             :greater_equal,
             :less_equal
           ]
  end

  test "type definitions normalize complex nested type information" do
    type_definition =
      Type.new(%{
        type_id: "type-mode",
        snapshot_id: "snapshot-alpha",
        name: "ModeType",
        base_type: "aggregate",
        aggregate_members: [
          %{name: "enabled", type_id: "type-bool"},
          %{name: "count", type_id: "type-count", initial_value: 0}
        ],
        enumerations: [
          %{value: 0, label: "OFF"},
          %{value: 1, label: "ON", description: "system enabled"}
        ],
        array_shape: %{
          element_type_id: "type-byte",
          dimensions: [16],
          dynamic_dimension_refs: ["point-count"]
        }
      })

    assert type_definition.base_type == :aggregate
    assert Enum.map(type_definition.aggregate_members, & &1.name) == ["enabled", "count"]
    assert Enum.map(type_definition.enumerations, & &1.label) == ["OFF", "ON"]
    assert type_definition.array_shape.element_type_id == "type-byte"
    assert type_definition.array_shape.dynamic_dimension_refs == ["point-count"]
  end
end
