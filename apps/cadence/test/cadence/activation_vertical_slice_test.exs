defmodule Cadence.ActivationVerticalSliceTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Projections.ActivationStatus
  alias Cadence.Runtime
  alias Cadence.Runtime.Missions, as: RuntimeMissions

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

    assert {:ok, request} =
             ManagementActivations.request(requester, mission_id, binding_set.binding_set_id, 1)

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
              desired: %{generation: 1},
              applied: %{generation: 1},
              observed: %{generation_alignment: :converged}
            }} = ActivationStatus.fetch(organization_id, mission_id)

    assert {:ok, same_execution} = ControlActivations.execute(approved)
    assert same_execution.activation_execution_id == execution.activation_execution_id
    assert Enum.count(Cadence.Activations.list_activations(organization_id, mission_id)) == 1

    assert :ok = Runtime.stop_mission(mission_id)

    assert {:ok,
            %{
              desired: %{generation: 1},
              applied: nil,
              observed: %{generation_alignment: :not_applied}
            }} = ActivationStatus.fetch(organization_id, mission_id)

    assert {:ok, %{generation: 1}} = MissionRuntimeReconciler.reconcile(mission_id)

    assert {:ok, %{generation: 1}} = RuntimeMissions.applied_spec(mission_id)
  end

  defp user_scope(organization_id, user_id) do
    user =
      User.new(%{
        user_id: user_id,
        email: user_id <> "@example.test",
        display_name: user_id,
        capabilities: [:platform_admin]
      })

    Scope.new(%{user: user, organization_id: organization_id})
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
