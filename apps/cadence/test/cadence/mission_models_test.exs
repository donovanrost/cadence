defmodule Cadence.MissionModelsTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.Activations
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModelApproval
  alias Cadence.MissionModelCatalogNaming
  alias Cadence.MissionModelFixtures
  alias Cadence.MissionModels
  alias Cadence.Runtime

  @organization_id "org-mission-models"

  setup do
    previous_governance = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: true)
    mission_id = "mission-models-#{System.unique_integer([:positive])}"
    persist_mission_scope(@organization_id, mission_id)

    on_exit(fn ->
      Application.put_env(:cadence, :activation_governance, previous_governance)
      Missions.stop(mission_id)
      Runtime.stop_mission(mission_id)
    end)

    %{mission_id: mission_id}
  end

  test "an approved revision and exact binding set apply as one runtime generation", %{
    mission_id: mission_id
  } do
    binding_set = persist_binding_set(mission_id)
    revision = compile_and_approve(mission_id)

    requester = user_scope("requester")
    approver = user_scope("approver")

    assert {:ok, request} =
             MissionModelFixtures.request_model_activation(
               requester,
               mission_id,
               revision.revision_id,
               binding_set.binding_set_id,
               binding_set.version,
               at: ~U[2026-08-11 12:00:00Z]
             )

    assert request.state == :approval_pending
    assert request.metadata["mission_model"]["revision_id"] == revision.revision_id
    assert is_binary(request.metadata["mission_model_comparison"]["comparison_report_id"])

    assert {:ok, _request, _decision, approved} =
             ManagementActivations.approve(
               approver,
               request.activation_request_id,
               "qualified mission model"
             )

    assert {:ok, execution} =
             ControlActivations.execute(approved, now: ~U[2026-08-11 12:00:00Z])

    assert {:ok, activation} =
             Activations.fetch_active_activation(@organization_id, mission_id)

    assert execution.activation_id == activation.activation_id
    assert activation.generation == 1
    assert activation.binding_set_id == binding_set.binding_set_id
    assert get_in(activation.metadata, ["mission_model", "revision_id"]) == revision.revision_id

    assert {:ok, basis} = MissionModelPromotion.runtime_basis(activation)
    assert basis.mission_model_revision_id == revision.revision_id
    assert map_size(basis.runtime_plans) == 4

    snapshot = MissionRuntimeReconciler.snapshot(mission_id)
    assert snapshot.applied_generation == activation.generation
    assert snapshot.last_error == nil
  end

  defp user_scope(prefix) do
    user_id = "#{prefix}-#{System.unique_integer([:positive])}"

    user =
      User.new(%{
        user_id: user_id,
        email: user_id <> "@example.test",
        display_name: user_id,
        capabilities: [:platform_admin]
      })

    Scope.new(%{user: user, organization_id: @organization_id, admin_mode?: true})
  end

  defp persist_binding_set(mission_id) do
    binding_set =
      BindingSet.new(%{
        organization_id: @organization_id,
        mission_id: mission_id,
        binding_set_id: "mission-model-runtime-binding",
        version: 1
      })

    assert {:ok, persisted} = Cadence.Governance.persist_binding_set(binding_set)
    persisted
  end

  defp compile_and_approve(mission_id) do
    layer =
      Layer.new(%{
        organization_id: @organization_id,
        mission_id: mission_id,
        name: "empty executable model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    assert {:ok, compilation} = MissionModels.compile_layers([layer])

    MissionModelCatalogNaming.name!(
      @organization_id,
      mission_id,
      compilation.revision.revision_id
    )

    # The decision itself is RevisionDecisionsTest's.
    assert {:ok, revision} =
             MissionModelApproval.approve!(
               @organization_id,
               mission_id,
               compilation.revision.revision_id
             )

    revision
  end
end
