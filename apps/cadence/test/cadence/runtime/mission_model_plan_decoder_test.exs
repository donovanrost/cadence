defmodule Cadence.Runtime.MissionModelPlanDecoderTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Bundle
  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, ConstraintPlan, VerifierPlan}
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Catalog.MissionModel.{Adapters.Snapshots, Compiler, RuntimePlan}
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetrySnapshot
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  test "decodes persisted executable telemetry and command plans without source snapshots" do
    telemetry_snapshot = telemetry_snapshot()
    command_snapshot = command_snapshot()

    layer =
      Snapshots.to_layer(
        Bundle.new(%{
          telemetry_snapshot: telemetry_snapshot,
          command_snapshot: command_snapshot
        })
      )

    assert {:ok, compilation} = Compiler.compile([layer])
    assert Enum.all?(compilation.plans, fn {_target, plan} -> plan.status == :ready end)

    persisted_plans =
      Map.new(compilation.plans, fn {target, %RuntimePlan{} = plan} ->
        persisted_document = plan.plan |> Jason.encode!() |> Jason.decode!()
        {target, %RuntimePlan{plan | plan: persisted_document}}
      end)

    assert :ok = MissionModelPlanDecoder.validate(persisted_plans)

    configured =
      PacketDefinition.new(%{
        packet_definition_id: "packet-hk",
        mission_id: "mission-alpha",
        packet_name: "stale binding copy",
        apid: 42,
        fields: [
          FieldDefinition.new(%{name: "stale", size_bits: 8, data_type: :uint})
        ]
      })

    assert {:ok, %PacketDefinition{} = packet_definition} =
             MissionModelPlanDecoder.resolve_telemetry_configuration(
               persisted_plans,
               configured
             )

    assert packet_definition.packet_name == "HK"

    assert [%FieldDefinition{size_bits: 16, parameter_id: parameter_id}] =
             packet_definition.fields

    assert is_binary(parameter_id)

    assert {:ok, command_basis} =
             MissionModelPlanDecoder.command_basis(
               persisted_plans,
               command_snapshot.snapshot_id,
               "cmd-set-mode"
             )

    assert [%ArgumentSpec{base_type: :enumerated}] =
             command_basis.runtime_definition.argument_specs

    assert [%ConstraintPlan{criteria: %{subject_ref: constraint_parameter_id}}] =
             command_basis.constraint_plans

    assert String.starts_with?(constraint_parameter_id, "semantic:parameter:")

    assert [%VerifierPlan{phase: :completion}] = command_basis.verifier_plans
    assert command_basis.operational_binding.significance == :critical
  end

  test "fails closed when an active telemetry plan does not contain the bound definition" do
    layer = Snapshots.to_layer(Bundle.new(%{telemetry_snapshot: telemetry_snapshot()}))
    assert {:ok, compilation} = Compiler.compile([layer])

    configured =
      PacketDefinition.new(%{
        packet_definition_id: "packet-other",
        mission_id: "mission-alpha",
        packet_name: "Other",
        apid: 42,
        fields: []
      })

    assert {:error, {:mission_model_packet_definition_not_found, "packet-other"}} =
             MissionModelPlanDecoder.resolve_telemetry_configuration(
               compilation.plans,
               configured
             )
  end

  defp telemetry_snapshot do
    TelemetrySnapshot.new(%{
      snapshot_id: "telemetry-snapshot-alpha",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      artifact_id: "artifact-alpha",
      import_run_id: "import-alpha",
      importer_key: "cadence_yaml",
      snapshot_name: "Alpha Telemetry",
      types: [
        %{
          type_id: "type-temp",
          snapshot_id: "telemetry-snapshot-alpha",
          name: "Temperature",
          base_type: :integer,
          encoding: %{encoding_type: :integer, size_bits: 16, integer_encoding: :unsigned}
        }
      ],
      points: [
        %{
          point_id: "point-temp",
          snapshot_id: "telemetry-snapshot-alpha",
          name: "temperature",
          type_ref: "type-temp"
        },
        %{
          point_id: "point-ready",
          snapshot_id: "telemetry-snapshot-alpha",
          name: "subsystem.ready",
          type_ref: "type-temp"
        },
        %{
          point_id: "point-mode",
          snapshot_id: "telemetry-snapshot-alpha",
          name: "subsystem.mode",
          type_ref: "type-temp"
        }
      ],
      packets: [
        %{
          packet_id: "packet-hk",
          snapshot_id: "telemetry-snapshot-alpha",
          name: "HK",
          apid: 42,
          entries: [
            %{packet_entry_id: "entry-temp", point_ref: "point-temp", bit_offset: 0}
          ]
        }
      ]
    })
  end

  defp command_snapshot do
    CommandSnapshot.new(%{
      snapshot_id: "command-snapshot-alpha",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      artifact_id: "artifact-alpha",
      import_run_id: "import-alpha",
      importer_key: "cadence_yaml",
      snapshot_name: "Alpha Commands",
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
          argument_type_ref: "arg-type-mode"
        }
      ],
      encoding_layouts: [
        %{
          layout_id: "layout-main",
          snapshot_id: "command-snapshot-alpha",
          name: "Main Layout",
          layout_kind: :space_packet,
          apid: 77,
          entries: [
            %{
              layout_entry_id: "entry-mode",
              entry_kind: :argument_ref,
              argument_ref: "arg-mode",
              bit_offset: 0
            }
          ]
        }
      ],
      command_definitions: [
        %{
          command_id: "cmd-set-mode",
          snapshot_id: "command-snapshot-alpha",
          name: "SET_MODE",
          encoding_layout_ref: "layout-main",
          arguments: ["arg-mode"],
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
              }
            }
          ],
          operational_metadata: %{significance: :critical, critical: true}
        }
      ]
    })
  end
end
