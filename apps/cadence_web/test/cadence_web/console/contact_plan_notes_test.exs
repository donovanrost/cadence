defmodule CadenceWeb.Console.ContactPlanNotesTest do
  @moduledoc """
  ux U76 (lead 11-17): one 2,000-character note cap for the submitter's note and the approver's
  decision_note; an approval's note is recorded with the decision (NULL when none, never a canned
  text) and quoted in the plan history; the plan detail carries the Re-plan header (`repair`).
  """
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
      base: "/api/v1/missions/#{mission.mission_id}/contact-plans"
    }
  end

  defp submit(c, user, plan_id, body),
    do: user |> TestFixtures.member_conn() |> post("#{c.base}/#{plan_id}/submit", body)

  defp get_as(c, user, path),
    do: user |> TestFixtures.member_conn() |> get(c.base <> path) |> json_response(200)

  test "a note over 2,000 characters is refused with U76's line; up to 2,000 is kept", c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.member, c.member_membership, c.mission)

    plan_id = fixture.plan.contact_plan_id
    body = %{"expected_version" => 1, "operation_id" => "op-note"}

    assert %{"error" => %{"details" => %{"note" => "Keep the note under 2,000 characters."}}} =
             c
             |> submit(c.member, plan_id, Map.put(body, "note", String.duplicate("a", 2_001)))
             |> json_response(422)

    assert %{"state" => "pending_approval"} =
             c
             |> submit(c.member, plan_id, Map.put(body, "note", String.duplicate("a", 2_000)))
             |> json_response(200)
             |> Map.fetch!("data")
  end

  test "the approver's decision_note is recorded with the decision and quoted in the history",
       c do
    plan_id = approve(c, %{"decision_note" => "  Checked the Svalbard gap with the owner  "})

    assert %{"kind" => "approved", "text" => "Checked the Svalbard gap with the owner"} =
             approved_decision(c, plan_id)
  end

  test "an approval without a note records none: the history's text is null", c do
    plan_id = approve(c, %{})
    assert %{"kind" => "approved", "text" => nil} = approved_decision(c, plan_id)
  end

  test "the plan detail carries the Re-plan header (null without a run to repair from)", c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.member, c.member_membership, c.mission)

    data = get_as(c, c.member, "/#{fixture.plan.contact_plan_id}")["data"]

    assert Map.has_key?(data, "repair")

    case data["repair"] do
      nil ->
        :ok

      repair ->
        assert %{
                 "window" => %{"from" => _, "to" => _},
                 "horizon_seconds" => horizon,
                 "attempts" => %{"used" => used, "max" => max},
                 "available" => available,
                 "cause" => nil
               } = repair

        assert is_integer(horizon) and is_integer(used) and is_integer(max)
        assert is_boolean(available)
    end
  end

  # Under 'direct' approval an admin may approve their own submit (#257: submit, then approve,
  # which executes off the request); the execution's end is awaited so nothing outlives the test.
  defp approve(c, extra) do
    ContactPlanningFixtures.approve_directly!(c.org, c.admin, c.admin_membership, c.mission)
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.admin, c.admin_membership, c.mission)
    plan_id = fixture.plan.contact_plan_id
    :ok = SchedulingRunner.subscribe(c.mission.mission_id)

    submit_body = %{"expected_version" => 1, "operation_id" => "op-#{plan_id}"}
    assert c |> submit(c.admin, plan_id, submit_body) |> json_response(200)

    body = Map.merge(%{"expected_version" => 1, "operation_id" => "op-approve-#{plan_id}"}, extra)

    assert %{"state" => "executing", "outcome" => "approved"} =
             c.admin
             |> TestFixtures.member_conn()
             |> post("#{c.base}/#{plan_id}/approve", body)
             |> json_response(202)
             |> Map.fetch!("data")

    assert_receive {:scheduling_progress, %{kind: :execute, id: ^plan_id, state: final}}
                   when final in [:finished, :failed],
                   30_000

    plan_id
  end

  defp approved_decision(c, plan_id) do
    c
    |> get_as(c.admin, "/#{plan_id}/history")
    |> get_in(["data", "decisions"])
    |> Enum.find(&(&1["kind"] == "approved"))
  end
end
