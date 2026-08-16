defmodule Cadence.ActivationVerticalSliceTest do
  use Cadence.RuntimeCase, async: false

  @moduletag :config

  alias Cadence.Accounts.User
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModels
  alias Cadence.Projections.ActivationStatus
  alias Cadence.Runtime
  alias Cadence.Runtime.Missions, as: RuntimeMissions

  setup do
    previous_governance = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: true)

    on_exit(fn ->
      Application.put_env(:cadence, :activation_governance, previous_governance)
    end)

    :ok
  end

  test "approved intent executes once and converges the exact data-plane generation" do
    organization_id = unique("org-vertical-activation")
    mission_id = unique("mission-vertical-activation")
    persist_mission_scope(organization_id, mission_id)

    binding_set =
      BindingSet.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        binding_set_id: "vertical-basis",
        version: 1
      })

    assert {:ok, ^binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    requester = user_scope(organization_id, unique("requester"))
    approver = user_scope(organization_id, unique("approver"))
    revision = persist_approved_model(organization_id, mission_id)

    assert {:ok, request} =
             MissionModels.request_promotion(
               requester,
               mission_id,
               revision.revision_id,
               binding_set.binding_set_id,
               1
             )

    assert {:ok, _request, _decision, approved} =
             ManagementActivations.approve(
               approver,
               request.activation_request_id,
               "approved for operations"
             )

    assert {:ok, execution} = ControlActivations.execute(approved)
    assert execution.status == :succeeded
    assert execution.activation_request_id == request.activation_request_id
    assert execution.generation == 1

    assert {:ok, runtime_spec} = RuntimeMissions.applied_spec(mission_id)
    assert runtime_spec.activation_request_id == request.activation_request_id
    assert runtime_spec.generation == execution.generation
    assert runtime_spec.binding_set == binding_set

    assert {:ok,
            %{
              requested: %{state: :approved},
              operational: %{generation: 1},
              applied: %{generation: 1},
              observed: %{generation_alignment: :converged, request_alignment: :executed}
            }} = ActivationStatus.fetch(organization_id, mission_id)

    assert {:ok, same_execution} = ControlActivations.execute(approved)
    assert same_execution.activation_execution_id == execution.activation_execution_id
    assert Enum.count(Cadence.Activations.list_activations(organization_id, mission_id)) == 1

    assert :ok = Runtime.stop_mission(mission_id)

    assert {:ok,
            %{
              requested: %{state: :approved},
              operational: %{generation: 1},
              applied: nil,
              observed: %{generation_alignment: :not_applied}
            }} = ActivationStatus.fetch(organization_id, mission_id)

    assert {:ok, %{generation: 1}} = MissionRuntimeReconciler.reconcile(mission_id)

    assert {:ok, %{generation: 1}} = RuntimeMissions.applied_spec(mission_id)
  end

  test "policy-approved intent executes without a human decision when approval is disabled" do
    Application.put_env(:cadence, :activation_governance, approval_required: false)

    organization_id = unique("org-policy-activation")
    mission_id = unique("mission-policy-activation")
    persist_mission_scope(organization_id, mission_id)

    binding_set = persist_binding_set(organization_id, mission_id, "policy-basis")
    requester = user_scope(organization_id, unique("requester"))
    revision = persist_approved_model(organization_id, mission_id)

    assert {:ok, %{state: :approved} = request} =
             MissionModels.request_promotion(
               requester,
               mission_id,
               revision.revision_id,
               binding_set.binding_set_id,
               binding_set.version,
               metadata: %{"source" => "policy-test"}
             )

    assert {:ok, approved} =
             ManagementActivations.fetch_approved(request.activation_request_id)

    assert approved.approval_decision_ids == []
    assert approved.metadata["source"] == "policy-test"
    assert approved.metadata["mission_model"]["revision_id"] == revision.revision_id
    assert {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)

    assert {:ok, activation} =
             ControlActivations.fetch_active_basis(organization_id, mission_id)

    assert activation.activation_request_id == request.activation_request_id
    assert activation.metadata["source"] == "policy-test"
    assert activation.metadata["mission_model"]["revision_id"] == revision.revision_id

    assert :ok = Runtime.stop_mission(mission_id)
  end

  test "the requester cannot approve their own activation request" do
    organization_id = unique("org-self-approval")
    mission_id = unique("mission-self-approval")
    persist_mission_scope(organization_id, mission_id)

    binding_set = persist_binding_set(organization_id, mission_id, "self-approval-basis")
    requester = user_scope(organization_id, unique("requester"))

    assert {:ok, request} =
             ManagementActivations.request(
               requester,
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:error, :activation_self_approval_forbidden} =
             ManagementActivations.approve(
               requester,
               request.activation_request_id,
               "self approval must fail"
             )
  end

  defp persist_binding_set(organization_id, mission_id, binding_set_id) do
    binding_set =
      BindingSet.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        binding_set_id: binding_set_id,
        version: 1
      })

    assert {:ok, ^binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    binding_set
  end

  defp persist_approved_model(organization_id, mission_id) do
    layer =
      Layer.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        name: "Activation vertical slice",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    assert {:ok, compilation} = MissionModels.compile_layers([layer])

    assert {:ok, revision} =
             MissionModels.approve_revision(
               organization_id,
               mission_id,
               compilation.revision.revision_id,
               %{"kind" => "test_fixture", "id" => "activation-vertical-slice"}
             )

    revision
  end

  defp user_scope(organization_id, user_id) do
    user =
      User.new(%{
        user_id: user_id,
        email: user_id <> "@example.test",
        display_name: user_id,
        capabilities: [:platform_admin]
      })

    Scope.new(%{user: user, organization_id: organization_id, admin_mode?: true})
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
