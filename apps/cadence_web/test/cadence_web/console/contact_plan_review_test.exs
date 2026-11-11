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
    assert c.admin
           |> TestFixtures.member_conn()
           |> get(c.base <> "/" <> c.plan_id)
           |> json_response(200)
           |> get_in(["data", "approval"]) == nil

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

    # Plan detail says who sent it back and why.
    admin_id = c.admin.user_id

    assert %{
             "decision" => "rejected",
             "reason" => "Move 004 off Kiruna first",
             "actor" => %{"kind" => "user", "id" => ^admin_id},
             "exceptions" => []
           } =
             c.admin
             |> TestFixtures.member_conn()
             |> get(c.base <> "/" <> c.plan_id)
             |> json_response(200)
             |> get_in(["data", "approval"])
  end

  test "a sent-back draft resubmits unchanged as a new version, and a double-click can't cut twice (U36)",
       c do
    submit = fn version, op, extra ->
      post_as(
        c,
        c.member,
        "/#{c.plan_id}/submit",
        Map.merge(%{"expected_version" => version, "operation_id" => op}, extra)
      )
    end

    assert submit.(1, "op-1", %{}) |> json_response(200)

    assert c
           |> post_as(c.admin, "/#{c.plan_id}/reject", %{
             "expected_version" => 1,
             "reason" => "Explain the gaps"
           })
           |> json_response(200)

    assert %{"state" => "pending_approval"} =
             submit.(1, "op-2", %{"note" => "Reasons are clearer now"})
             |> json_response(200)
             |> Map.fetch!("data")

    detail =
      c.admin
      |> TestFixtures.member_conn()
      |> get(c.base <> "/" <> c.plan_id)
      |> json_response(200)
      |> Map.fetch!("data")

    member_id = c.member.user_id

    assert %{
             "version" => 2,
             "state" => "pending_approval",
             "submission" => %{
               "round" => 2,
               "unchanged" => true,
               "note" => "Reasons are clearer now",
               "actor" => %{"kind" => "user", "id" => ^member_id}
             },
             "previous_round" => %{
               "round" => 1,
               "version" => 1,
               "approval" => %{"decision" => "rejected", "reason" => "Explain the gaps"},
               "acknowledgements" => []
             }
           } = detail

    # A stale second click (still expecting v1) is refused and cuts no v3.
    assert %{"error" => %{"code" => "plan_changed"}} =
             submit.(1, "op-3", %{}) |> json_response(409)

    assert %{"version" => 2} =
             c.admin
             |> TestFixtures.member_conn()
             |> get(c.base <> "/" <> c.plan_id)
             |> json_response(200)
             |> Map.fetch!("data")
  end
end
