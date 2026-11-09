defmodule CadenceWeb.Console.ContactPlanAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    %{
      org: org,
      user: user,
      membership: membership,
      mission: mission,
      base: "/api/console/v1/missions/#{mission.mission_id}"
    }
  end

  defp get_json(c, path), do: c.user |> TestFixtures.member_conn() |> get(c.base <> path)

  test "an empty mission has no plans; an unknown plan is not found", c do
    assert json_response(get_json(c, "/contact-plans"), 200)["data"] == %{"plans" => []}

    assert json_response(get_json(c, "/contact-plans/nope"), 404)["error"]["code"] ==
             "plan_not_found"

    assert json_response(get_json(c, "/contact-plans?day=bad"), 422)["error"]["details"]["day"]

    assert json_response(get_json(c, "/contact-plans?state=bad"), 422)["error"]["details"][
             "state"
           ]
  end

  test "lists the plan and shows passes, demand, unmet and conflicts", c do
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission)
    plan_id = fixture.plan.contact_plan_id

    [row] =
      json_response(get_json(c, "/contact-plans?day=2027-01-01&state=draft"), 200)["data"][
        "plans"
      ]

    assert %{"id" => ^plan_id, "version" => 1, "state" => "draft"} = row
    assert %{"passes" => 1, "conflicts" => 0, "unsatisfied" => 0, "minutes" => 15} = row["counts"]
    assert row["ready_to_approve"] == true

    assert json_response(get_json(c, "/contact-plans?day=2027-01-02"), 200)["data"]["plans"] == []

    detail = json_response(get_json(c, "/contact-plans/#{plan_id}"), 200)["data"]

    assert [%{"spacecraft_id" => sc, "station" => "station-review", "synthetic" => true}] =
             detail["passes"]

    assert sc == fixture.craft.spacecraft_id
    assert detail["unmet"] == []
    assert detail["conflicts"] == []

    assert %{"rule_met" => 1, "rule_total" => 1, "spacecraft" => [demand], "rules" => [rule]} =
             detail["demand"]

    assert %{
             "spacecraft_id" => ^sc,
             "rule_met" => true,
             "contacts" => %{"have" => 1, "need" => 1}
           } = demand

    assert rule["text"] =~ "at least 1 min"
  end

  test "setup says what is missing before drafting, and demand counts the day", c do
    setup = json_response(get_json(c, "/contact-plans/setup"), 200)["data"]["setup"]

    assert %{
             "ready" => false,
             "missing" => ["fleet_planning_policy", "contact_requirements"],
             "policy" => nil
           } =
             setup

    scope =
      Cadence.Auth.Scope.new(%{
        user: c.user,
        organization_id: c.org.organization_id,
        organization_membership: c.membership
      })

    policy = ContactPlanningFixtures.active_policy!(scope, c.mission.mission_id)
    ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission)
    TestFixtures.persist_spacecraft!(c.mission, display_name: "No rule craft")

    setup = json_response(get_json(c, "/contact-plans/setup"), 200)["data"]["setup"]
    assert %{"ready" => true, "missing" => [], "requirements" => 1, "templates" => 0} = setup
    assert setup["policy"]["id"] == policy.fleet_planning_policy_id

    demand = json_response(get_json(c, "/contact-plans/demand?day=2027-01-01"), 200)["data"]

    assert %{
             "spacecraft_with_rules" => 1,
             "contacts_needed" => 1,
             "without_rule" => 1,
             "spacecraft_total" => 2
           } =
             demand

    assert json_response(get_json(c, "/contact-plans/demand?day=2027-01-05"), 200)["data"][
             "contacts_needed"
           ] == 0

    assert json_response(get_json(c, "/contact-plans/demand"), 422)["error"]["details"]["day"]
  end

  test "a plan without its pass lists the requirement as unmet", c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission, select?: false)

    detail =
      json_response(get_json(c, "/contact-plans/#{fixture.plan.contact_plan_id}"), 200)["data"]

    assert [%{"requirement_id" => req, "spacecraft_id" => sc, "why" => [_ | _]}] = detail["unmet"]
    assert req == fixture.requirement.contact_requirement_id
    assert sc == fixture.craft.spacecraft_id
    assert detail["ready_to_approve"] == false
    assert detail["demand"]["rule_met"] == 0
  end
end
