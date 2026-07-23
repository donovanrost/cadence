defmodule Cadence.Management.ActivationGovernanceTest do
  use ExUnit.Case, async: false

  alias Cadence.Accounts.User
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Management.Activations
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  setup do
    {:ok, _started_apps} = Application.ensure_all_started(:ecto_sql)
    start_supervised!(Cadence.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, :manual)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Cadence.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    :ok
  end

  test "persists a distinct human approval without booting Control or Data" do
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Runtime.Supervisor) == nil

    organization_id = unique("org-activation")
    mission_id = unique("mission-activation")
    persist_basis(organization_id, mission_id)

    requester = user_scope(organization_id, unique("requester"))
    approver = user_scope(organization_id, unique("approver"))

    assert {:ok, request} =
             Activations.request(requester, mission_id, "governed-basis", 1,
               change_class: :mission_data_plane,
               now: ~U[2026-07-21 12:00:00Z]
             )

    assert request.state == :approval_pending
    assert request.requester_actor_id == requester.user.user_id
    assert request.policy_document["required_human_approvals"] == 1

    assert {:error, :activation_self_approval_forbidden} =
             Activations.approve(
               requester,
               request.activation_request_id,
               "self approval must fail"
             )

    assert {:error, :human_activation_approver_required} =
             Activations.approve(
               service_scope(organization_id, mission_id, unique("service")),
               request.activation_request_id,
               "service approval must fail"
             )

    assert {:ok, approved_request, decision, approved} =
             Activations.approve(
               approver,
               request.activation_request_id,
               "independent flight approval",
               now: ~U[2026-07-21 12:01:00Z]
             )

    assert approved_request.state == :approved
    assert decision.actor_id == approver.user.user_id
    assert approved.activation_request_id == request.activation_request_id
    assert approved.approval_decision_ids == [decision.activation_decision_id]
    assert {:ok, ^approved} = Activations.fetch_approved(request.activation_request_id)

    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Runtime.Supervisor) == nil
  end

  defp persist_basis(organization_id, mission_id) do
    organization =
      Organization.new(%{
        organization_id: organization_id,
        slug: organization_id,
        display_name: organization_id
      })

    mission =
      Mission.new(%{
        mission_id: mission_id,
        organization_id: organization_id,
        slug: mission_id,
        display_name: mission_id
      })

    assert {:ok, _organization} = Cadence.Organizations.persist_organization(organization)
    assert {:ok, _mission} = Cadence.Missions.persist_mission(mission)

    binding_set =
      BindingSet.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        binding_set_id: "governed-basis",
        version: 1
      })

    assert {:ok, ^binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)
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

  defp service_scope(organization_id, mission_id, service_identity_id) do
    identity =
      ServiceIdentity.new(%{
        service_identity_id: service_identity_id,
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: service_identity_id,
        capabilities: [:mission_admin]
      })

    %Scope{
      actor_kind: :service,
      organization_id: organization_id,
      mission_id: mission_id,
      service_identity: identity,
      capabilities: MapSet.new(identity.capabilities)
    }
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
