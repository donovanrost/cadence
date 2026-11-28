defmodule CadenceWeb.Console.PointConditionAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.MonitoringPlanFixtures
  alias Cadence.Repo
  alias Cadence.SemanticObservations.LatestAlarmStateRow
  alias CadenceWeb.MissionReadModelFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    MissionReadModelFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)

    %{user: user, org: org, mission: mission}
  end

  defp get_json(c, path, user \\ nil) do
    (user || c.user)
    |> TestFixtures.member_conn()
    |> get(
      "/api/v1/missions/#{c.mission.mission_id}/spacecraft/spacecraft-001/point-conditions" <>
        path
    )
  end

  test "lists a spacecraft's points from the alarm states and the plan, with the wire fields",
       c do
    # The mission's plan monitors both points (the seeded packet's catalog points carry no
    # parameter id, so a point is its own parameter); the runtime has HK.counter in a warning.
    MonitoringPlanFixtures.activate!(
      c.org.organization_id,
      c.mission.mission_id,
      {"read-models", 1},
      for(
        {name, point} <- [{"limit-counter", "HK.counter"}, {"limit-voltage", "HK.voltage"}],
        do:
          {name, "/parameters/" <> String.replace(point, ".", "-"),
           above: 10, parameter_id: point}
      )
    )

    MonitoringPlanFixtures.alarm_state!(
      c.org.organization_id,
      c.mission.mission_id,
      "spacecraft-001",
      "HK.counter",
      "warning",
      at: ~U[2023-11-15 23:15:00.000000Z]
    )

    body = c |> get_json("") |> json_response(200)

    # One in caution (the runtime's state), one the plan monitors that has no state yet; both last
    # sampled in 2023.
    assert [row, nominal] = body["data"]

    assert %{
             "point_id" => "HK.counter",
             "source" => "catalog_monitoring",
             "condition" => "caution",
             "raw_limit_state" => nil,
             "evaluated" => true,
             "policy_id" => "policy-HK.counter",
             "value" => nil,
             "freshness" => "stale",
             "last_sample_at" => "2023-11-15T23:15:00.000000Z",
             "entered_at" => "2023-11-15T23:15:00.000000Z",
             "entered_at_is_lower_bound" => false,
             "evaluated_at" => nil
           } = row

    assert %{
             "point_id" => "HK.voltage",
             "condition" => "nominal",
             "evaluated" => false,
             "freshness" => "stale"
           } = nominal

    assert %{
             "counts" => %{"caution" => 1, "critical" => 0, "stale" => 2, "total" => 2},
             "stale_after_s" => 900,
             "telemetry" => telemetry
           } = body["meta"]

    assert telemetry in ["ok", "degraded"]
    assert body["meta"]["next_cursor"] == nil
  end

  test "a live alarm shows, labelled by its source", c do
    %{
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      spacecraft_id: "spacecraft-001",
      parameter_id: "HK.mode",
      policy_id: "pol-1",
      evaluation_id: "ev-1",
      transition_id: "tr-1",
      effective_state: "critical",
      generation_time: ~U[2026-11-27 12:00:00.000000Z],
      receipt_time: ~U[2026-11-27 12:00:00.000000Z]
    }
    |> LatestAlarmStateRow.changeset()
    |> Repo.insert!()

    rows = c |> get_json("") |> json_response(200) |> Map.fetch!("data")

    assert [
             %{
               "point_id" => "HK.mode",
               "source" => "catalog_monitoring",
               "condition" => "critical",
               "policy_id" => "pol-1",
               "evaluated_at" => nil,
               "entered_at" => "2026-11-27T12:00:00.000000Z"
             }
           ] = rows
  end

  test "refuses a bad state, limit or cursor with the field named, and an unknown spacecraft",
       c do
    assert %{"error" => %{"details" => %{"state" => _}}} =
             c |> get_json("?state=bogus") |> json_response(422)

    assert %{"error" => %{"details" => %{"limit" => _}}} =
             c |> get_json("?limit=0") |> json_response(422)

    assert %{"error" => %{"details" => %{"cursor" => _}}} =
             c |> get_json("?cursor=nope") |> json_response(422)

    path = "/api/v1/missions/#{c.mission.mission_id}/spacecraft/nope/point-conditions"
    assert c.user |> TestFixtures.member_conn() |> get(path) |> json_response(404)
  end

  test "another organization's user cannot read the mission's points", c do
    other_org = TestFixtures.persist_org!()
    other = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(other, other_org)

    assert c |> get_json("", other) |> json_response(404)
  end
end
