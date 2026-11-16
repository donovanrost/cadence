defmodule CadenceWeb.Console.ContactPlanDaysAPITest do
  @moduledoc "DECISIONS #100: K1's day strip, one read for up to 14 UTC days."
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

  defp get_data(c, path),
    do: c.admin |> TestFixtures.member_conn() |> get(c.base <> path) |> json_response(200)

  defp post_as(c, user, path, body),
    do: user |> TestFixtures.member_conn() |> post(c.base <> path, body)

  test "the plan's day names its plan; a sent-back draft says so; other days say how much to plan",
       c do
    assert post_as(c, c.member, "/#{c.plan_id}/submit", %{
             "expected_version" => 1,
             "operation_id" => "op-1"
           })
           |> json_response(200)

    assert post_as(c, c.admin, "/#{c.plan_id}/reject", %{
             "expected_version" => 1,
             "reason" => "Gaps"
           })
           |> json_response(200)

    %{"data" => %{"window" => %{"from" => from}}} = get_data(c, "/" <> c.plan_id)
    {:ok, at, 0} = DateTime.from_iso8601(from)
    day = DateTime.to_date(at)
    range = "?from=#{Date.add(day, -1)}&to=#{Date.add(day, 1)}"

    assert %{"data" => %{"days" => [before, planned, later]}} = get_data(c, "/days" <> range)

    assert %{
             "plan" => %{"id" => id, "version" => 1, "state" => "draft"},
             "sent_back" => true,
             "requirements_count" => needed,
             "booked_count" => nil
           } = planned

    assert id == c.plan_id and is_integer(needed)
    assert planned["day"] == Date.to_iso8601(day)

    # U61: null until the day demand carries it, then a time in the plan's own day.
    first = planned["first_window_at"]
    assert first == nil or String.starts_with?(first, Date.to_iso8601(day))

    for empty <- [before, later] do
      assert %{"plan" => nil, "sent_back" => false, "requested_count" => nil} = empty
      assert is_integer(empty["requirements_count"])
    end
  end

  test "a range over 14 days, backwards, or not a day is 422", c do
    for query <- [
          "?from=2026-11-01&to=2026-11-20",
          "?from=2026-11-10&to=2026-11-09",
          "?from=nope&to=2026-11-09"
        ] do
      assert %{"error" => %{"code" => "invalid_params"}} =
               c.admin
               |> TestFixtures.member_conn()
               |> get(c.base <> "/days" <> query)
               |> json_response(422)
    end
  end
end
