defmodule Cadence.Catalog.CommandCompilerTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.{
    Compiler,
    Compiler.ConstraintPlan,
    Compiler.OperationalBinding,
    Compiler.Result,
    Compiler.RuntimeDefinition,
    Compiler.VerifierPlan,
    Snapshot
  }

  test "compiles supported canonical command definitions into runtime artifacts" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "command-snapshot-alpha",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        artifact_id: "artifact-alpha",
        import_run_id: "import-run-alpha",
        importer_key: "xtce",
        snapshot_name: "Mission Alpha Commands",
        argument_types: [
          %{
            argument_type_id: "arg-type-mode",
            snapshot_id: "command-snapshot-alpha",
            name: "ModeType",
            base_type: :enumerated,
            encoding: %{encoding_type: :integer, size_bits: 8, signed: false},
            enumerations: [%{value: 0, label: "SAFE"}, %{value: 1, label: "SCIENCE"}]
          }
        ],
        arguments: [
          %{
            argument_id: "arg-mode",
            snapshot_id: "command-snapshot-alpha",
            name: "mode",
            argument_type_ref: "arg-type-mode",
            required: true,
            default_value: 1
          }
        ],
        encoding_layouts: [
          %{
            layout_id: "layout-main",
            snapshot_id: "command-snapshot-alpha",
            name: "Main Layout",
            layout_kind: :space_packet,
            apid: 77,
            opcode: 9,
            opcode_size_bits: 8,
            entries: [
              %{
                layout_entry_id: "entry-header",
                entry_kind: :fixed_value,
                fixed_value: 170,
                fixed_value_size_bits: 8,
                bit_offset: 0,
                display_order: 0
              },
              %{
                layout_entry_id: "entry-mode",
                entry_kind: :argument_ref,
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
            description: "Set subsystem mode",
            encoding_layout_ref: "layout-main",
            arguments: ["arg-mode"],
            default_argument_values: %{"arg-mode" => 1},
            fixed_argument_values: %{"header" => 170},
            transmission_constraints: [
              %{
                constraint_id: "constraint-ready",
                name: "Subsystem Ready",
                constraint_type: :precondition,
                criteria: %{
                  criteria_type: :comparison,
                  subject_ref: "telemetry:subsystem.ready",
                  comparison: :equal,
                  value: true
                }
              }
            ],
            verifiers: [
              %{
                verifier_id: "verifier-mode",
                name: "Mode Accepted",
                phase: :completion,
                success_criteria: %{
                  criteria_type: :comparison,
                  subject_ref: "telemetry:subsystem.mode",
                  comparison: :equal,
                  value: 1
                },
                timeout_ms: 5_000,
                severity: :warning
              }
            ],
            operational_metadata: %{
              significance: :critical,
              critical: true,
              subsystem: "ADCS",
              preferred_uplink_service: "cop1"
            }
          }
        ]
      })

    assert %Result{
             runtime_definitions: [runtime_definition],
             constraint_plans: [constraint_plan],
             verifier_plans: [verifier_plan],
             operational_bindings: [operational_binding],
             diagnostics: []
           } = Compiler.compile(snapshot)

    assert %RuntimeDefinition{} = runtime_definition
    assert runtime_definition.command_id == "cmd-set-mode"
    assert runtime_definition.layout_id == "layout-main"
    assert runtime_definition.layout_kind == :space_packet
    assert runtime_definition.apid == 77
    assert runtime_definition.opcode == 9
    assert Enum.map(runtime_definition.argument_specs, & &1.argument_id) == ["arg-mode"]

    assert Enum.map(
             runtime_definition.encoding_steps,
             &{&1.step_kind, &1.bit_offset, &1.size_bits}
           ) == [
             {:fixed_value, 0, 8},
             {:argument_ref, 8, 8}
           ]

    assert %ConstraintPlan{} = constraint_plan
    assert constraint_plan.command_id == "cmd-set-mode"
    assert constraint_plan.constraint_id == "constraint-ready"
    assert constraint_plan.criteria.subject_ref == "telemetry:subsystem.ready"

    assert %VerifierPlan{} = verifier_plan
    assert verifier_plan.command_id == "cmd-set-mode"
    assert verifier_plan.verifier_id == "verifier-mode"
    assert verifier_plan.phase == :completion

    assert %OperationalBinding{} = operational_binding
    assert operational_binding.command_id == "cmd-set-mode"
    assert operational_binding.significance == :critical
    assert operational_binding.preferred_uplink_service == "cop1"
    assert operational_binding.apid == 77
    assert operational_binding.opcode == 9
  end

  test "emits diagnostics and skips commands that current runtime cannot compile" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "command-snapshot-beta",
        mission_id: "mission-alpha",
        artifact_id: "artifact-beta",
        import_run_id: "import-run-beta",
        importer_key: "xtce",
        snapshot_name: "Unsupported Commands",
        argument_types: [
          %{
            argument_type_id: "arg-type-array",
            snapshot_id: "command-snapshot-beta",
            name: "ArrayType",
            base_type: :array,
            encoding: %{encoding_type: :binary, size_bits: 128}
          }
        ],
        arguments: [
          %{
            argument_id: "arg-array",
            snapshot_id: "command-snapshot-beta",
            name: "payload",
            argument_type_ref: "arg-type-array"
          }
        ],
        encoding_layouts: [
          %{
            layout_id: "layout-nested",
            snapshot_id: "command-snapshot-beta",
            name: "Nested Layout",
            entries: [
              %{
                layout_entry_id: "entry-nested",
                entry_kind: :nested_layout_ref,
                nested_layout_ref: "other-layout",
                bit_offset: 0
              }
            ]
          }
        ],
        command_definitions: [
          %{
            command_id: "cmd-no-layout",
            snapshot_id: "command-snapshot-beta",
            name: "NO_LAYOUT"
          },
          %{
            command_id: "cmd-unsupported-arg",
            snapshot_id: "command-snapshot-beta",
            name: "UNSUPPORTED_ARG",
            encoding_layout_ref: "layout-nested",
            arguments: ["arg-array"]
          }
        ]
      })

    assert %Result{
             runtime_definitions: [],
             constraint_plans: [],
             verifier_plans: [],
             operational_bindings: [],
             diagnostics: diagnostics
           } = Compiler.compile(snapshot)

    diagnostic_codes = Enum.map(diagnostics, & &1.code)

    assert "command_compiler.encoding_layout_required" in diagnostic_codes
    assert "command_compiler.nested_layout_unsupported" in diagnostic_codes
  end

  test "compiles zero-argument commands that only provide a layout and opcode" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "command-snapshot-delta",
        mission_id: "mission-alpha",
        artifact_id: "artifact-delta",
        import_run_id: "import-run-delta",
        importer_key: "cadence_yaml",
        snapshot_name: "Zero Argument Commands",
        encoding_layouts: [
          %{
            layout_id: "layout-noop",
            snapshot_id: "command-snapshot-delta",
            name: "NOOP Layout",
            layout_kind: :space_packet,
            opcode: 0,
            opcode_size_bits: 8,
            entries: []
          }
        ],
        command_definitions: [
          %{
            command_id: "cmd-noop",
            snapshot_id: "command-snapshot-delta",
            name: "NOOP",
            encoding_layout_ref: "layout-noop",
            arguments: []
          }
        ]
      })

    assert %Result{
             runtime_definitions: [%RuntimeDefinition{} = runtime_definition],
             diagnostics: []
           } = Compiler.compile(snapshot)

    assert runtime_definition.command_id == "cmd-noop"
    assert runtime_definition.argument_specs == []
    assert runtime_definition.encoding_steps == []
    assert runtime_definition.opcode == 0
  end

  test "emits diagnostics for unsupported command argument type shapes" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "command-snapshot-gamma",
        mission_id: "mission-alpha",
        artifact_id: "artifact-gamma",
        import_run_id: "import-run-gamma",
        importer_key: "xtce",
        snapshot_name: "Unsupported Dynamic Argument",
        argument_types: [
          %{
            argument_type_id: "arg-type-dynamic-binary",
            snapshot_id: "command-snapshot-gamma",
            name: "DynamicBinary",
            base_type: :binary,
            encoding: %{encoding_type: :binary, dynamic_size_ref: "arg-count"}
          }
        ],
        arguments: [
          %{
            argument_id: "arg-payload",
            snapshot_id: "command-snapshot-gamma",
            name: "payload",
            argument_type_ref: "arg-type-dynamic-binary"
          }
        ],
        encoding_layouts: [
          %{
            layout_id: "layout-dynamic",
            snapshot_id: "command-snapshot-gamma",
            name: "Dynamic Layout",
            entries: [
              %{
                layout_entry_id: "entry-payload",
                entry_kind: :argument_ref,
                argument_ref: "arg-payload",
                bit_offset: 0
              }
            ]
          }
        ],
        command_definitions: [
          %{
            command_id: "cmd-dynamic",
            snapshot_id: "command-snapshot-gamma",
            name: "DYNAMIC",
            encoding_layout_ref: "layout-dynamic",
            arguments: ["arg-payload"]
          }
        ]
      })

    assert %Result{
             runtime_definitions: [],
             diagnostics: diagnostics
           } = Compiler.compile(snapshot)

    assert "command_compiler.fixed_size_encoding_required" in Enum.map(
             diagnostics,
             & &1.code
           )
  end
end
