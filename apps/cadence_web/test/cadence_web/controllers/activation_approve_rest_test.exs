defmodule CadenceWeb.ActivationApproveRESTTest do
  @moduledoc """
  #263: REST activation approve, once the approval is recorded, answers 200 with `outcome`
  (`applied | needs_review`), never an error. Today only service identities hold API tokens and
  services can't approve (`human_activation_approver_required`, before anything is written), so no
  client reaches this answer yet. The controller is called with a person's scope, as a person's
  token or another route would give it.
  """
  use CadenceWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Management.Activations
  alias Cadence.MissionModelApproval
  alias Cadence.MissionModelCatalogNaming
  alias Cadence.MissionModels
  alias CadenceWeb.{ActivationController, TestFixtures}

  setup do
    approver = TestFixtures.persist_user!(display_name: "REST approver")
    requester = TestFixtures.persist_user!(display_name: "REST requester")
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(approver, org, role: :organization_admin)
    TestFixtures.grant_membership!(requester, org)
    mission = TestFixtures.persist_mission!(org)

    scope = %Scope{
      actor_kind: :user,
      user: approver,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      organization_membership: membership,
      capabilities: MapSet.new([:organization_admin])
    }

    %{org: org, mission: mission, scope: scope, requester: requester}
  end

  test "an approval whose apply succeeds answers applied", c do
    request = request!(c)

    assert %{"outcome" => "applied", "execution" => %{"status" => "succeeded"}} =
             c |> approve(request) |> json_response(200) |> Map.fetch!("data")
  end

  test "an approval whose apply then fails answers 200 needs_review; the approval stands", c do
    request = request!(c)

    # The apply fails transiently AFTER the approval commits: the activation's own insert is
    # interrupted, as a lost connection would (activation_approvals_test's injection).
    Cadence.Repo.query!("""
    CREATE FUNCTION pg_temp.interrupt_apply() RETURNS trigger AS $$
    BEGIN RAISE EXCEPTION 'connection lost (injected)'; END $$ LANGUAGE plpgsql
    """)

    Cadence.Repo.query!("""
    CREATE TRIGGER interrupt_apply BEFORE INSERT ON mission_binding_set_activations
    FOR EACH ROW EXECUTE FUNCTION pg_temp.interrupt_apply()
    """)

    {conn, log} = with_log(fn -> approve(c, request) end)

    assert %{
             "outcome" => "needs_review",
             "request" => %{"state" => "approved"},
             "decision" => %{"decision" => "approved"}
           } = data = conn |> json_response(200) |> Map.fetch!("data")

    assert data["execution"] == nil or data["execution"]["status"] != "succeeded"
    refute Jason.encode!(data) =~ "injected"
    assert log =~ "activation request #{request.activation_request_id}: approved, but its apply"

    assert {:ok, %{state: :approved}} =
             Activations.fetch(c.scope, request.activation_request_id)
  end

  defp approve(c, request) do
    build_conn()
    |> assign(:current_scope, c.scope)
    |> ActivationController.approve(%{
      "organization_id" => c.org.organization_id,
      "mission_id" => c.mission.mission_id,
      "activation_request_id" => request.activation_request_id,
      "decision" => %{"reason" => "Reviewed the exact basis"}
    })
  end

  # An applicable request (approve refuses one that could never apply): an approved exact model
  # with its binding set, requested by someone other than the approver.
  defp request!(c) do
    binding =
      BindingSet.new(%{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        binding_set_id: Cadence.Ids.new("rest-approve-basis"),
        version: 1
      })

    {:ok, binding} = Cadence.Governance.persist_binding_set(c.org.organization_id, binding)

    layer =
      Layer.new(%{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        name: "REST approve model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    {:ok, compilation} = MissionModels.compile_layers([layer])
    revision_id = compilation.revision.revision_id
    MissionModelCatalogNaming.name!(c.org.organization_id, c.mission.mission_id, revision_id)

    {:ok, revision} =
      MissionModelApproval.approve!(c.org.organization_id, c.mission.mission_id, revision_id)

    {:ok, request} =
      MissionModels.request_promotion(
        %{c.scope | user: c.requester},
        c.mission.mission_id,
        revision.revision_id,
        binding.binding_set_id,
        1
      )

    request
  end
end
