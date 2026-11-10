defmodule CadenceWeb.Console.ContactPlanReviewTest do
  @moduledoc "Send back (reject) a plan waiting for approval."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!()
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    member_membership = TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    fixture = ContactPlanningFixtures.plan_fixture(org, member, member_membership, mission)

    %{
      admin: admin,
      member: member,
      plan_id: fixture.plan.contact_plan_id,
      base: "/api/console/v1/missions/#{mission.mission_id}/contact-plans"
    }
  end

  defp post_as(c, user, path, body),
    do: user |> TestFixtures.member_conn() |> post(c.base <> path, body)

  test "an approver sends a pending plan back to draft with a reason; refusals are coded", c do
    assert %{"error" => %{"code" => "plan_not_pending"}} =
             c
             |> post_as(c.admin, "/#{c.plan_id}/reject", %{
               "expected_version" => 1,
               "reason" => "Not yet"
             })
             |> json_response(409)

    assert %{"state" => "pending_approval"} =
             c
             |> post_as(c.member, "/#{c.plan_id}/submit", %{
               "expected_version" => 1,
               "operation_id" => "op-1"
             })
             |> json_response(200)
             |> Map.fetch!("data")

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"reason" => _}}} =
             c
             |> post_as(c.admin, "/#{c.plan_id}/reject", %{
               "expected_version" => 1,
               "reason" => " "
             })
             |> json_response(422)

    assert %{"error" => %{"code" => "forbidden"}} =
             c
             |> post_as(c.member, "/#{c.plan_id}/reject", %{
               "expected_version" => 1,
               "reason" => "Mine"
             })
             |> json_response(403)

    assert %{"id" => plan_id, "state" => "draft"} =
             c
             |> post_as(c.admin, "/#{c.plan_id}/reject", %{
               "expected_version" => 1,
               "reason" => "Move 004 off Kiruna first"
             })
             |> json_response(200)
             |> Map.fetch!("data")

    assert plan_id == c.plan_id
  end
end
