defmodule CadenceWeb.Console.ContactPlanReviewTest do
  @moduledoc "Send back (reject) a plan waiting for approval."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ContactPlanning.PlanSubmissions
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
      org_id: org.organization_id,
      mission_id: mission.mission_id,
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

    sent_back =
      c
      |> post_as(c.admin, "/#{c.plan_id}/reject", %{
        "expected_version" => 1,
        "reason" => "Move 004 off Kiruna first"
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"id" => plan_id, "state" => "draft"} = sent_back
    assert plan_id == c.plan_id

    # Drift sweep: the reply is the same plan detail as GET (booking, unconfirmed, execution,
    # chain), not the bare plan read.
    shown =
      c.admin
      |> TestFixtures.member_conn()
      |> get(c.base <> "/" <> c.plan_id)
      |> json_response(200)
      |> Map.fetch!("data")

    assert Map.keys(sent_back) |> Enum.sort() == Map.keys(shown) |> Enum.sort()
    assert Enum.all?(~w(unconfirmed execution chain chain_head), &Map.has_key?(sent_back, &1))

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

    # A stale second click (still expecting v1) is refused and cuts no v3: the plan is already
    # waiting for approval (#257: never a silent 200).
    assert %{"error" => %{"code" => "plan_already_submitted"}} =
             submit.(1, "op-3", %{}) |> json_response(409)

    assert %{"version" => 2, "latest_version" => 2} =
             c.admin
             |> TestFixtures.member_conn()
             |> get(c.base <> "/" <> c.plan_id)
             |> json_response(200)
             |> Map.fetch!("data")

    # U69 A10: an older version reads with the latest named, for the historical banner.
    assert %{"version" => 1, "latest_version" => 2} =
             c.admin
             |> TestFixtures.member_conn()
             |> get(c.base <> "/" <> c.plan_id <> "?version=1")
             |> json_response(200)
             |> Map.fetch!("data")

    history =
      c.admin
      |> TestFixtures.member_conn()
      |> get(c.base <> "/" <> c.plan_id <> "/history")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"latest_version" => 2, "truncated" => false, "versions" => [v2, v1]} = history
    assert %{"version" => 2, "decision" => nil, "submitted" => true} = v2
    assert %{"version" => 1, "decision" => "rejected", "submitted" => true} = v1
    assert %{"kind" => _, "id" => _} = v2["created_by"]
    # #468 (api on #503): the member who created version 1 keeps their id, and no one is named
    # by email.
    member_id = c.member.user_id
    assert %{"kind" => "user", "id" => ^member_id} = v1["created_by"]
    refute inspect(history) =~ c.member.email

    # #468 C: the submits stored no email in their rounds (PlanResubmission's writer).
    rounds = PlanSubmissions.list(c.org_id, c.mission_id, c.plan_id)
    assert rounds != []
    for r <- rounds, do: refute(inspect(r.actor_document) =~ "@")

    admin_id = c.admin.user_id

    assert [
             %{
               "kind" => "submitted",
               "version" => 2,
               "round" => 2,
               "unchanged" => true,
               "text" => "Reasons are clearer now",
               "actor" => %{"id" => ^member_id}
             },
             %{
               "kind" => "rejected",
               "version" => 1,
               "round" => 1,
               "text" => "Explain the gaps",
               "actor" => %{"id" => ^admin_id}
             },
             %{"kind" => "submitted", "version" => 1, "round" => 1}
           ] = history["decisions"]

    assert %{"error" => %{"code" => "plan_not_found"}} =
             c.admin
             |> TestFixtures.member_conn()
             |> get(c.base <> "/nope/history")
             |> json_response(404)
  end
end
