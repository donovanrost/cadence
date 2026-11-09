defmodule CadenceWeb.Console.ContactPlanSubmitTest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.Console.SchedulingRunner
  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!()
    member = TestFixtures.persist_user!()
    admin_membership = TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    member_membership = TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    %{
      org: org,
      mission: mission,
      admin: admin,
      member: member,
      admin_membership: admin_membership,
      member_membership: member_membership,
      base: "/api/console/v1/missions/#{mission.mission_id}/contact-plans"
    }
  end

  defp submit(c, user, plan_id, body),
    do: user |> TestFixtures.member_conn() |> post("#{c.base}/#{plan_id}/submit", body)

  test "a member's submit asks for approval and replays by operation id", c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.member, c.member_membership, c.mission)

    plan_id = fixture.plan.contact_plan_id
    body = %{"expected_version" => 1, "operation_id" => "op-member"}

    first = json_response(submit(c, c.member, plan_id, body), 200)["data"]

    assert %{
             "plan_id" => ^plan_id,
             "state" => "pending_approval",
             "outcome" => "pending_approval"
           } = first

    replay = json_response(submit(c, c.member, plan_id, body), 200)["data"]
    assert %{"state" => "pending_approval", "outcome" => "replayed"} = replay
  end

  test "an admin's submit approves and executes off the request", c do
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.admin, c.admin_membership, c.mission)
    plan_id = fixture.plan.contact_plan_id
    :ok = SchedulingRunner.subscribe(c.mission.mission_id)

    conn = submit(c, c.admin, plan_id, %{"expected_version" => 1, "operation_id" => "op-admin"})

    assert %{"state" => "executing", "outcome" => "executing"} = json_response(conn, 202)["data"]
    assert_receive {:scheduling_progress, %{kind: :execute, id: ^plan_id, state: :running}}, 5_000
    # The fixture route isn't bookable, so execution ends failed, but off the request.
    assert_receive {:scheduling_progress, %{kind: :execute, id: ^plan_id, state: final}}, 30_000
    assert final in [:finished, :failed]

    detail =
      c.admin |> TestFixtures.member_conn() |> get("#{c.base}/#{plan_id}") |> json_response(200)

    refute detail["data"]["state"] in ["draft", "pending_approval"]
  end

  test "unmet requirements block until acknowledged", c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.admin, c.admin_membership, c.mission,
        select?: false
      )

    plan_id = fixture.plan.contact_plan_id
    requirement_id = fixture.requirement.contact_requirement_id

    conn = submit(c, c.admin, plan_id, %{"expected_version" => 1, "operation_id" => "op-gap"})
    error = json_response(conn, 422)["error"]

    # An empty plan is never approvable (only gaps can be acknowledged), so this stays not ready.
    assert error["code"] == "plan_not_ready"
    assert [%{"requirement_id" => ^requirement_id}] = error["details"]["unmet"]

    acks = [%{"requirement_id" => requirement_id, "reason" => "Accept the gap this pass"}]

    conn =
      submit(c, c.admin, plan_id, %{
        "expected_version" => 1,
        "operation_id" => "op-gap-2",
        "acknowledgements" => acks
      })

    assert json_response(conn, 422)["error"]["code"] == "plan_not_ready"
  end

  test "validates the body", c do
    conn = submit(c, c.admin, "any", %{"operation_id" => "x"})
    assert json_response(conn, 422)["error"]["details"]["expected_version"]

    conn = submit(c, c.admin, "any", %{"expected_version" => 1})
    assert json_response(conn, 422)["error"]["details"]["operation_id"]

    conn = submit(c, c.admin, "nope", %{"expected_version" => 1, "operation_id" => "x"})
    assert json_response(conn, 404)["error"]["code"] == "plan_not_found"
  end
end
