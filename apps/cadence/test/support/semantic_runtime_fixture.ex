defmodule Cadence.TestSupport.SemanticRuntimeFixture do
  @moduledoc "A small compiled mission model (input parameter and a delta algorithm) for semantic runtime tests."

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.{Compiler, Declaration, Layer}
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.SemanticRuntime.Update

  @doc "`{runtime_spec, input_parameter_id}`."
  def runtime_spec do
    input = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/input"})
    output = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/output"})

    algorithm =
      Declaration.new(%{
        kind: :algorithm,
        qualified_name: "/algorithms/delta",
        references: [
          %{expected_kind: :parameter, source_ref: input.qualified_name, role: :input},
          %{expected_kind: :parameter, source_ref: output.qualified_name, role: :output}
        ],
        definition: %{
          implementation: %{kind: :expression},
          outputs: [
            %{
              parameter_id: output.semantic_id,
              qualified_name: output.qualified_name,
              expression: %{
                node:
                  {:stateful, :delta, input.semantic_id, {:parameter, input.semantic_id}, %{}},
                result_type: :number
              }
            }
          ]
        }
      })

    layer =
      Layer.new(%{
        mission_id: "semantic-store-mission",
        name: "semantic store",
        declarations: [
          %{kind: :space_system, qualified_name: "/"},
          input,
          output,
          algorithm
        ]
      })

    {:ok, compilation} = Compiler.compile([layer])

    binding_set =
      BindingSet.new(%{
        mission_id: layer.mission_id,
        binding_set_id: "semantic-store-binding",
        version: 1
      })

    {:ok, runtime_spec} =
      MissionRuntimeSpec.new(%{
        activation_id: "semantic-store-activation",
        mission_id: layer.mission_id,
        generation: 1,
        binding_set_id: binding_set.binding_set_id,
        binding_set_version: binding_set.version,
        binding_set_content_sha256: MissionRuntimeSpec.content_sha256(binding_set),
        binding_set: binding_set,
        mission_model_revision_id: compilation.revision.revision_id,
        mission_model_content_sha256: compilation.revision.content_sha256,
        runtime_plans: compilation.plans,
        activated_at: ~U[2026-08-12 12:00:00Z]
      })

    {runtime_spec, input.semantic_id}
  end

  def update(update_id, parameter_id, value, at) do
    Update.new(%{
      update_id: update_id,
      parameter_id: parameter_id,
      qualified_name: "/parameters/input",
      value: value,
      raw_value: value,
      quality: :good,
      generation_time: at,
      receipt_time: at,
      producer_kind: :container,
      producer_id: "container:hk",
      metadata: %{mission_id: "semantic-store-mission", spacecraft_id: "spacecraft-a"}
    })
  end
end
