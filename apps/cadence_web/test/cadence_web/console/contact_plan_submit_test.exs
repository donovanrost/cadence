defmodule CadenceWeb.Console.ContactPlanSubmitTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.Comms.{GroundStation, GroundStationStore, StationAvailability}
  alias Cadence.ContactPlanning.ContactPlanApprovals
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

  # The mission's governance setting: 'independent' (the default) needs a second person.
  defp approve_directly!(c),
    do: ContactPlanningFixtures.approve_directly!(c.org, c.admin, c.admin_membership, c.mission)

  defp submit(c, user, plan_id, body),
    do: user |> TestFixtures.member_conn() |> post("#{c.base}/#{plan_id}/submit", body)

  defp approve(c, user, plan_id, body),
    do: user |> TestFixtures.member_conn() |> post("#{c.base}/#{plan_id}/approve", body)

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

    assert %{"version" => 1, "replayed" => false} = first

    # #257: the same request again gets the original answer, flagged.
    replay = json_response(submit(c, c.member, plan_id, body), 200)["data"]
    assert Map.delete(replay, "replayed") == Map.delete(first, "replayed")
    assert replay["replayed"] == true
  end

  test "under 'independent' approval an admin's own submit waits for a second approver", c do
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.admin, c.admin_membership, c.mission)
    plan_id = fixture.plan.contact_plan_id

    conn = submit(c, c.admin, plan_id, %{"expected_version" => 1, "operation_id" => "op-self"})

    assert %{"state" => "pending_approval", "outcome" => "pending_approval"} =
             json_response(conn, 200)["data"]
  end

  test "under 'direct' an admin's submit only submits; their own approve executes off the request",
       c do
    approve_directly!(c)
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.admin, c.admin_membership, c.mission)
    plan_id = fixture.plan.contact_plan_id
    :ok = SchedulingRunner.subscribe(c.mission.mission_id)

    # #257 (breaking under 'direct'): submit no longer approves.
    conn = submit(c, c.admin, plan_id, %{"expected_version" => 1, "operation_id" => "op-admin"})
    assert %{"state" => "pending_approval"} = json_response(conn, 200)["data"]

    assert [] = ContactPlanApprovals.list(c.org.organization_id, c.mission.mission_id, plan_id)

    conn = approve(c, c.admin, plan_id, %{"expected_version" => 1, "operation_id" => "op-ok"})
    assert %{"state" => "executing", "outcome" => "approved"} = json_response(conn, 202)["data"]
    assert_receive {:scheduling_progress, %{kind: :execute, id: ^plan_id, state: :running}}, 5_000
    # The fixture route isn't bookable, so execution ends failed, but off the request.
    assert_receive {:scheduling_progress, %{kind: :execute, id: ^plan_id, state: final}}, 30_000
    assert final in [:finished, :failed]

    detail =
      c.admin |> TestFixtures.member_conn() |> get("#{c.base}/#{plan_id}") |> json_response(200)

    refute detail["data"]["state"] in ["draft", "pending_approval"]
  end

  test "unmet requirements block until acknowledged", c do
    approve_directly!(c)

    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.admin, c.admin_membership, c.mission,
        select?: false
      )

    plan_id = fixture.plan.contact_plan_id
    requirement_id = fixture.requirement.contact_requirement_id

    # Submitting doesn't check coverage; approving does (#257: submit only submits).
    conn = submit(c, c.admin, plan_id, %{"expected_version" => 1, "operation_id" => "op-gap"})
    assert json_response(conn, 200)

    conn = approve(c, c.admin, plan_id, %{"expected_version" => 1, "operation_id" => "op-gap-a"})
    error = json_response(conn, 422)["error"]

    # An empty plan is never approvable (only gaps can be acknowledged), so this stays not ready.
    assert error["code"] == "plan_not_ready"
    assert [%{"requirement_id" => ^requirement_id}] = error["details"]["unmet"]

    acks = [%{"requirement_id" => requirement_id, "reason" => "Accept the gap this pass"}]

    conn =
      approve(c, c.admin, plan_id, %{
        "expected_version" => 1,
        "operation_id" => "op-gap-2",
        "acknowledgements" => acks
      })

    assert json_response(conn, 422)["error"]["code"] == "plan_not_ready"
  end

  test "a pass at a station in an outage is a conflict that blocks submit (U26)", c do
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.admin, c.admin_membership, c.mission)
    plan_id = fixture.plan.contact_plan_id

    {:ok, _station} =
      GroundStationStore.persist_ground_station(
        c.org.organization_id,
        GroundStation.new(%{
          ground_station_id: "gs-review",
          mission_id: c.mission.mission_id,
          display_name: "Review",
          code: "REV",
          metadata: %{"provider_station_ref" => "station-review"}
        })
      )

    scope =
      Scope.new(%{
        user: c.admin,
        organization_id: c.org.organization_id,
        organization_membership: c.admin_membership
      })

    {:ok, %{id: window_id}} =
      StationAvailability.schedule(scope, c.mission.mission_id, "gs-review", %{
        kind: :outage,
        starts_at: ContactPlanningFixtures.now(),
        ends_at: DateTime.add(ContactPlanningFixtures.now(), 86_400),
        reason: "Antenna down"
      })

    detail =
      c.admin |> TestFixtures.member_conn() |> get("#{c.base}/#{plan_id}") |> json_response(200)

    assert [conflict] = detail["data"]["conflicts"]

    assert %{
             "code" => "station_unavailable",
             "ground_station_id" => "gs-review",
             "window_id" => ^window_id,
             "kind" => "outage",
             "snapshot_ids" => [_]
           } = conflict

    assert detail["data"]["at_risk"] == []
    assert detail["data"]["ready_to_approve"] == false

    conn = submit(c, c.admin, plan_id, %{"expected_version" => 1, "operation_id" => "op-outage"})
    error = json_response(conn, 422)["error"]
    assert error["code"] == "plan_not_ready"
    assert [%{"code" => "station_unavailable"}] = error["details"]["conflicts"]
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
