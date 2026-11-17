defmodule Cadence.Runtime.MissionModelPlanDecoderTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, VerifierPlan}
  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.MissionModel.{Compiler, RuntimePlan}
  alias Cadence.Catalog.Source
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @database """
  packets:
    - name: HK
      apid: 42
      items:
        - name: temperature
          bit_offset: 0
          bit_size: 16
          data_type: uint
        - name: ready
          bit_offset: 16
          bit_size: 1
          data_type: bool
  commands:
    - name: SET_MODE
      apid: 77
      opcode: 3
      is_hazardous: true
      hazard_description: Changes spacecraft mode
      parameters:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_length: 8
          valid_values: [0, 1]
      verifiers:
        - name: complete
          phase: completion
          success_criteria:
            subject_ref: telemetry:HK.ready
            comparison: equal
            value: 1
  """

  test "decodes persisted native telemetry and command plans" do
    compilation = compilation()

    persisted_plans =
      Map.new(compilation.plans, fn {target, %RuntimePlan{} = plan} ->
        persisted_document = plan.plan |> Jason.encode!() |> Jason.decode!()
        {target, %RuntimePlan{plan | plan: persisted_document}}
      end)

    assert :ok = MissionModelPlanDecoder.validate(persisted_plans)

    [packet_document] = persisted_plans.telemetry.plan["packet_definitions"]

    configured =
      PacketDefinition.new(%{
        packet_definition_id: packet_document["packet_definition_id"],
        mission_id: "mission-alpha",
        packet_name: "stale binding copy",
        apid: 42,
        fields: [FieldDefinition.new(%{name: "stale", size_bits: 8, data_type: :uint})]
      })

    assert {:ok, %PacketDefinition{} = packet_definition} =
             MissionModelPlanDecoder.resolve_telemetry_configuration(persisted_plans, configured)

    assert packet_definition.packet_name == "HK"
    assert Enum.map(packet_definition.fields, & &1.size_bits) == [16, 1]
    assert Enum.all?(packet_definition.fields, &is_binary(&1.parameter_id))

    [runtime_document] = persisted_plans.command.plan["runtime_definitions"]

    assert {:ok, command_basis} =
             MissionModelPlanDecoder.command_basis(
               persisted_plans,
               runtime_document["command_id"]
             )

    assert [%ArgumentSpec{base_type: :enumerated}] =
             command_basis.runtime_definition.argument_specs

    assert command_basis.runtime_definition.mission_model_revision_id ==
             compilation.revision.revision_id

    assert [%VerifierPlan{phase: :completion, success_criteria: criteria}] =
             command_basis.verifier_plans

    assert String.starts_with?(criteria.subject_ref, "semantic:parameter:")
    assert command_basis.operational_binding.significance == :hazardous
  end

  test "fails closed without a native plan or matching telemetry definition" do
    compilation = compilation()

    configured =
      PacketDefinition.new(%{
        packet_definition_id: "semantic:container:missing",
        mission_id: "mission-alpha",
        packet_name: "Other",
        apid: 42,
        fields: []
      })

    assert {:error, {:mission_model_packet_definition_not_found, "semantic:container:missing"}} =
             MissionModelPlanDecoder.resolve_telemetry_configuration(
               compilation.plans,
               configured
             )

    assert {:error, {:mission_model_runtime_plan_required, :telemetry}} =
             MissionModelPlanDecoder.telemetry_packet_definitions(
               Map.delete(compilation.plans, :telemetry)
             )
  end

  defp compilation do
    source =
      Source.new(%{
        artifact_id: "mission-model-runtime-test",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        catalog_family: :combined,
        artifact_name: "runtime.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: @database
      })

    assert {:ok, import_result} =
             CadenceYamlDatabase.import(source, %{import_run_id: "runtime-test"})

    assert {:ok, compilation} = Compiler.compile(import_result.bundle.declaration_layers)
    assert Enum.all?(compilation.plans, fn {_target, plan} -> plan.status == :ready end)
    compilation
  end
end
