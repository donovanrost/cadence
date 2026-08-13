defmodule Cadence.MissionModels.ComparisonTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.{Declaration, Expression, Layer, Reference}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.Comparison
  alias Cadence.Platform.ContentHash
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, State, Update}

  test "high-risk promotion requires and executes an approved qualification corpus" do
    organization_id = "org-mission-model-comparison"
    mission_id = "mission-model-comparison-#{System.unique_integer([:positive])}"
    persist_mission_scope(organization_id, mission_id)
    scope = user_scope(organization_id)

    binding_set =
      BindingSet.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        binding_set_id: "comparison-binding",
        version: 1
      })

    assert {:ok, binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    {layer, input_id} = algorithm_layer(organization_id, mission_id)
    assert {:ok, compilation} = MissionModels.compile_layers([layer])

    assert {:ok, revision} =
             MissionModels.approve_revision(
               organization_id,
               mission_id,
               compilation.revision.revision_id,
               %{"kind" => "user", "id" => "reviewer"}
             )

    assert {:error, :mission_model_comparison_not_passed} =
             MissionModels.request_promotion(
               scope,
               mission_id,
               revision.revision_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    update = qualification_update(mission_id, input_id)
    expected_hash = semantic_result_hash(compilation.plans, [update])

    assert {:ok, qualification_case} =
             MissionModels.register_qualification_case(
               scope,
               mission_id,
               "nominal input",
               [update],
               expected_result_sha256: expected_hash
             )

    assert qualification_case.expected_result_sha256 == expected_hash

    assert {:ok, request} =
             MissionModels.request_promotion(
               scope,
               mission_id,
               revision.revision_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    comparison_id =
      request.metadata["mission_model_comparison"]["comparison_report_id"]

    assert {:ok, report} = Comparison.fetch(organization_id, mission_id, comparison_id)
    assert report["risk"] == "high"
    assert report["status"] == "passed"
    assert report["replay"]["required"]
    assert [%{"status" => "passed"}] = report["replay"]["cases"]
  end

  defp algorithm_layer(organization_id, mission_id) do
    input = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/input"})
    output = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/output"})

    algorithm =
      Declaration.new(%{
        kind: :algorithm,
        qualified_name: "/algorithms/double",
        references: [
          Reference.new(%{
            expected_kind: :parameter,
            source_ref: input.qualified_name,
            role: :input
          }),
          Reference.new(%{
            expected_kind: :parameter,
            source_ref: output.qualified_name,
            role: :output
          })
        ],
        definition: %{
          implementation: %{kind: :expression},
          outputs: [
            %{
              parameter_id: output.semantic_id,
              qualified_name: output.qualified_name,
              expression:
                Expression.new(%{
                  node: {:*, {:parameter, input.semantic_id}, {:literal, 2}},
                  result_type: :number
                })
            }
          ]
        }
      })

    layer =
      Layer.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        name: "qualified algorithms",
        declarations: [
          %{kind: :space_system, qualified_name: "/"},
          input,
          output,
          algorithm
        ]
      })

    {layer, input.semantic_id}
  end

  defp qualification_update(mission_id, input_id) do
    Update.new(%{
      update_id: "qualification:input:1",
      parameter_id: input_id,
      qualified_name: "/parameters/input",
      value: 4,
      raw_value: 4,
      quality: :good,
      generation_time: ~U[2026-08-12 12:00:00Z],
      receipt_time: ~U[2026-08-12 12:00:00Z],
      producer_kind: :container,
      producer_id: "container:qualification",
      metadata: %{mission_id: mission_id, spacecraft_id: "qualification-spacecraft"}
    })
  end

  defp semantic_result_hash(plans, updates) do
    assert {:ok, result, %State{}} =
             SemanticRuntime.process(%State{}, updates, PlanDecoder.decode(plans))

    ContentHash.term_sha256(%{
      updates:
        Enum.map(result.parameter_updates, fn update ->
          {update.parameter_id, update.value, update.quality, update.generation_time,
           update.receipt_time}
        end),
      monitoring:
        Enum.map(result.monitoring_results, fn monitoring ->
          {monitoring.policy_id, monitoring.parameter_id, monitoring.effective_state,
           monitoring.transition}
        end)
    })
  end

  defp user_scope(organization_id) do
    user =
      User.new(%{
        user_id: "comparison-user",
        email: "comparison@example.test",
        display_name: "Comparison User",
        capabilities: [:platform_admin]
      })

    Scope.new(%{user: user, organization_id: organization_id, admin_mode?: true})
  end
end
