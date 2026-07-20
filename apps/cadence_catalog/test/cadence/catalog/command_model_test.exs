defmodule Cadence.Catalog.CommandModelTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.{
    Argument,
    ArgumentType,
    Definition,
    EncodingEntry,
    EncodingLayout,
    MatchCriteria,
    OperationalMetadata,
    Snapshot,
    TransmissionConstraint,
    Verifier
  }

  test "snapshot normalizes nested canonical command catalog definitions" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "command-snapshot-alpha",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        artifact_id: "artifact-alpha",
        import_run_id: "import-run-alpha",
        importer_key: "xtce",
        snapshot_name: "Mission Alpha Commands",
        snapshot_version: "1.0.0",
        argument_types: [
          %{
            argument_type_id: "arg-type-mode",
            snapshot_id: "command-snapshot-alpha",
            name: "ModeArgType",
            base_type: "enumerated",
            encoding: %{
              encoding_type: "integer",
              size_bits: 8,
              byte_order: "big_endian",
              signed: false
            },
            enumerations: [
              %{value: 0, label: "SAFE"},
              %{value: 1, label: "SCIENCE"}
            ]
          }
        ],
        arguments: [
          %{
            argument_id: "arg-mode",
            snapshot_id: "command-snapshot-alpha",
            name: "mode",
            argument_type_ref: "arg-type-mode",
            required: true,
            default_value: 1,
            hazardous_values: [3]
          }
        ],
        encoding_layouts: [
          %{
            layout_id: "layout-main",
            snapshot_id: "command-snapshot-alpha",
            name: "Main Layout",
            layout_kind: "space_packet",
            apid: 77,
            opcode: 9,
            opcode_size_bits: 8,
            entries: [
              %{
                layout_entry_id: "entry-mode",
                entry_kind: "argument_ref",
                argument_ref: "arg-mode",
                bit_offset: 8,
                display_order: 1
              }
            ]
          }
        ],
        command_definitions: [
          %{
            command_id: "cmd-set-mode",
            snapshot_id: "command-snapshot-alpha",
            name: "SET_MODE",
            display_name: "Set Mode",
            encoding_layout_ref: "layout-main",
            arguments: ["arg-mode"],
            default_argument_values: %{"arg-mode" => 1},
            fixed_argument_values: %{"header" => 170},
            transmission_constraints: [
              %{
                constraint_id: "constraint-mode",
                name: "Subsystem Ready",
                constraint_type: "precondition",
                criteria: %{
                  criteria_type: "comparison",
                  subject_ref: "telemetry:subsystem.ready",
                  comparison: "equal",
                  value: true
                }
              }
            ],
            verifiers: [
              %{
                verifier_id: "verifier-complete",
                name: "Mode Accepted",
                phase: "completion",
                success_criteria: %{
                  criteria_type: "comparison",
                  subject_ref: "telemetry:subsystem.mode",
                  comparison: "equal",
                  value: 1
                },
                timeout_ms: 5_000,
                severity: "warning"
              }
            ],
            operational_metadata: %{
              significance: "critical",
              critical: true,
              hazardous: false,
              subsystem: "ADCS",
              preferred_uplink_service: "cop1"
            },
            provenance: %{
              artifact_id: "artifact-alpha",
              import_run_id: "import-run-alpha",
              importer_key: "xtce",
              source_ref: "meta_command:SET_MODE"
            }
          }
        ]
      })

    assert snapshot.snapshot_id == "command-snapshot-alpha"
    assert snapshot.artifact_id == "artifact-alpha"
    assert snapshot.import_run_id == "import-run-alpha"

    assert [%ArgumentType{argument_type_id: "arg-type-mode", base_type: :enumerated}] =
             snapshot.argument_types

    assert [%Argument{argument_id: "arg-mode", argument_type_id: "arg-type-mode"}] =
             snapshot.arguments

    assert [
             %EncodingLayout{
               layout_id: "layout-main",
               layout_kind: :space_packet,
               entries: [%EncodingEntry{argument_id: "arg-mode", bit_offset: 8}]
             }
           ] = snapshot.encoding_layouts

    assert [
             %Definition{
               command_id: "cmd-set-mode",
               encoding_layout_id: "layout-main",
               argument_ids: ["arg-mode"],
               transmission_constraints: [%TransmissionConstraint{name: "Subsystem Ready"}],
               verifiers: [%Verifier{name: "Mode Accepted", phase: :completion}],
               operational_metadata: %OperationalMetadata{
                 significance: :critical,
                 subsystem: "ADCS",
                 preferred_uplink_service: "cop1"
               }
             }
           ] = snapshot.command_definitions
  end

  test "match criteria recursively normalize compound command conditions" do
    criteria =
      MatchCriteria.new(%{
        criteria_type: "compound",
        operator: "or",
        conditions: [
          %{
            criteria_type: "comparison",
            subject_ref: "telemetry:subsystem.ready",
            comparison: "equal",
            value: true
          },
          %{
            criteria_type: "compound",
            operator: "and",
            conditions: [
              %{
                criteria_type: "comparison",
                subject_ref: "telemetry:mode",
                comparison: "greater_equal",
                value: 1
              },
              %{
                criteria_type: "comparison",
                subject_ref: "telemetry:mode",
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

  test "argument type definitions normalize nested type and encoding information" do
    argument_type =
      ArgumentType.new(%{
        argument_type_id: "arg-type-structured",
        snapshot_id: "command-snapshot-alpha",
        name: "StructuredArgType",
        base_type: "aggregate",
        aggregate_members: [
          %{name: "enabled", argument_type_id: "arg-type-bool"},
          %{name: "count", argument_type_id: "arg-type-count", initial_value: 0}
        ],
        enumerations: [
          %{value: 0, label: "OFF"},
          %{value: 1, label: "ON", description: "system enabled"}
        ],
        array_shape: %{
          element_argument_type_id: "arg-type-byte",
          dimensions: [16],
          dynamic_dimension_refs: ["arg-count"]
        },
        encoding: %{
          encoding_type: "binary",
          size_bits: 128,
          byte_order: "big_endian"
        }
      })

    assert argument_type.base_type == :aggregate
    assert Enum.map(argument_type.aggregate_members, & &1.name) == ["enabled", "count"]
    assert Enum.map(argument_type.enumerations, & &1.label) == ["OFF", "ON"]
    assert argument_type.array_shape.element_argument_type_id == "arg-type-byte"
    assert argument_type.array_shape.dynamic_dimension_refs == ["arg-count"]
    assert argument_type.encoding.encoding_type == :binary
  end
end
