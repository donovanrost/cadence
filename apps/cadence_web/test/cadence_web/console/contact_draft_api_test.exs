defmodule CadenceWeb.Console.ContactDraftAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias CadenceWeb.Console.SchedulingRunner
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
      base: "/api/console/v1/missions/#{mission.mission_id}/contact-plans/drafts"
    }
  end

  defp post_json(c, path, body),
    do: c.user |> TestFixtures.member_conn() |> post(c.base <> path, body)

  defp get_json(c, path), do: c.user |> TestFixtures.member_conn() |> get(c.base <> path)

  test "without a fleet planning policy the draft says planning isn't set up", c do
    conn = post_json(c, "", %{"day" => "2027-01-01", "operation_id" => "op-1"})

    assert %{
             "code" => "planning_not_set_up",
             "details" => %{"missing" => ["fleet_planning_policy"]}
           } =
             json_response(conn, 422)["error"]
  end

  test "re-planning needs a plan that came from a fleet draft and is executing", c do
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission)
    path = "/api/console/v1/missions/#{c.mission.mission_id}/contact-plans"

    post = fn body ->
      c.user
      |> TestFixtures.member_conn()
      |> post("#{path}/#{fixture.plan.contact_plan_id}/repairs", body)
    end

    assert json_response(post.(%{"operation_id" => "op-r"}), 409)["error"]["code"] ==
             "plan_not_repairable"

    assert json_response(post.(%{}), 422)["error"]["details"]["operation_id"]

    assert json_response(post.(%{"operation_id" => "x", "from" => "2027-01-01T00:00:00Z"}), 422)[
             "error"
           ]["details"]["from"]

    conn = c.user |> TestFixtures.member_conn() |> get("#{path}/repairs/nope")
    assert json_response(conn, 404)["error"]["code"] == "draft_not_found"
  end

  test "validates day and operation_id", c do
    assert json_response(post_json(c, "", %{"operation_id" => "x"}), 422)["error"]["details"][
             "day"
           ]

    assert json_response(post_json(c, "", %{"day" => "2027-01-01"}), 422)["error"]["details"][
             "operation_id"
           ]
  end

  test "starts a draft once per operation, runs it off-request and reads it back", c do
    scope =
      Scope.new(%{
        user: c.user,
        organization_id: c.org.organization_id,
        organization_membership: c.membership
      })

    ContactPlanningFixtures.active_policy!(scope, c.mission.mission_id)
    ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission)
    :ok = SchedulingRunner.subscribe(c.mission.mission_id)

    first =
      json_response(post_json(c, "", %{"day" => "2027-01-01", "operation_id" => "op-draft"}), 202)[
        "data"
      ]

    assert %{"run_id" => run_id, "outcome" => "created"} = first

    assert_receive {:scheduling_progress, %{kind: :draft, id: ^run_id, state: :running}}, 5_000
    assert_receive {:scheduling_progress, %{kind: :draft, id: ^run_id, state: final}}, 30_000
    assert final in [:finished, :failed]

    replay =
      json_response(post_json(c, "", %{"day" => "2027-01-01", "operation_id" => "op-draft"}), 202)[
        "data"
      ]

    assert %{"run_id" => ^run_id, "outcome" => "replayed"} = replay

    draft = json_response(get_json(c, "/#{run_id}"), 200)["data"]
    assert draft["run"]["id"] == run_id
    assert draft["run"]["state"] in ~w(completed partial failed)
    # A finished run says when it stopped.
    assert is_binary(draft["run"]["stopped_at"])
    assert %{"from" => "2027-01-01T00:00:00" <> _} = draft["run"]["horizon"]

    assert json_response(post_json(c, "/#{run_id}/continue", %{}), 409)["error"]["code"] ==
             "draft_not_interrupted"

    assert json_response(get_json(c, "/nope"), 404)["error"]["code"] == "draft_not_found"
  end
end
