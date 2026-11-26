defmodule CadenceWeb.Console.RequirementHeldByAPITest do
  @moduledoc """
  ux P4 (fe-setup): a requirement's detail names the plan past draft that holds it (held_by), so
  the page offers 'Open plan R41' rather than 'Plan <day>'. A draft doesn't hold it.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.ContactPlans
  alias Cadence.Reads.ContactPlanOverview
  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    %{org: org, user: user, membership: membership, mission: mission, scope: scope}
  end

  defp held_by(c, requirement_id) do
    c.user
    |> TestFixtures.member_conn()
    |> get(
      "/api/v1/missions/#{c.mission.mission_id}/contact-planning/requirements/#{requirement_id}"
    )
    |> json_response(200)
    |> get_in(["data", "held_by"])
  end

  test "null while only a draft holds it; the submitted plan once one does", c do
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission)
    requirement_id = fixture.requirement.contact_requirement_id
    plan_id = fixture.plan.contact_plan_id

    assert held_by(c, requirement_id) == nil

    {:ok, _} = ContactPlans.submit(c.scope, c.mission.mission_id, plan_id, 1, "Book")

    assert %{"plan_id" => ^plan_id, "revision" => 1, "state" => state, "day" => day} =
             held_by(c, requirement_id)

    # The plans list's day for it: the console opens the plan through it.
    assert {:ok, %{window: %{from: from}}} =
             ContactPlanOverview.plan(c.org.organization_id, c.mission.mission_id, plan_id)

    assert day == (from && from |> DateTime.to_date() |> Date.to_iso8601())

    assert state in ["pending_approval", "approved"]
  end
end
