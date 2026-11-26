defmodule CadenceWeb.Console.ActivationApproveRefusalsAPITest do
  @moduledoc """
  ux U95: L10's approve is refused BEFORE anything is recorded when the request couldn't apply
  (domain's approve preflight, director 11-17): a 409 with the refusal's own code and U95's
  words, and the request stays pending with no decision.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Management.Activations
  alias CadenceWeb.TestFixtures

  setup do
    approver = TestFixtures.persist_user!(display_name: "Ada Approver")
    requester = TestFixtures.persist_user!(display_name: "Flight requester")
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(approver, org, role: :organization_admin)
    TestFixtures.grant_membership!(requester, org)
    mission = TestFixtures.persist_mission!(org)

    scope = %Scope{
      actor_kind: :user,
      user: requester,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      organization_membership: membership,
      capabilities: MapSet.new([:organization_admin])
    }

    %{
      approver: approver,
      org: org,
      mission: mission,
      scope: scope,
      base: "/api/v1/missions/#{mission.mission_id}/activations"
    }
  end

  test "a request that names no catalog revision can't be approved, and nothing is recorded", c do
    id = request(c).activation_request_id

    assert %{"code" => "mission_model_activation_manifest_required", "message" => message} =
             c.approver
             |> post_conn(c.base <> "/#{id}/approve", %{"reason" => "Looks right"})
             |> json_response(409)
             |> Map.fetch!("error")

    assert message =~ "doesn't say which catalog revision it activates"
    assert String.ends_with?(message, "Your approval wasn't recorded.")

    assert %{"state" => "approval_pending", "decision" => nil} =
             c.approver
             |> TestFixtures.member_conn()
             |> get(c.base <> "/#{id}")
             |> json_response(200)
             |> Map.fetch!("data")
  end

  defp post_conn(user, path, body), do: user |> TestFixtures.member_conn() |> post(path, body)

  defp request(c) do
    binding =
      BindingSet.new(%{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        binding_set_id: Cadence.Ids.new("refusal-basis"),
        version: 1
      })

    {:ok, binding} = Cadence.Governance.persist_binding_set(c.org.organization_id, binding)
    {:ok, request} = Activations.request(c.scope, c.mission.mission_id, binding.binding_set_id, 1)
    request
  end
end
