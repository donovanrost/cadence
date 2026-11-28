defmodule CadenceWeb.Console.PointConditionAPITest do
  use CadenceWeb.ConnCase, async: false

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

  test "lists a spacecraft's points from the ground-limit store, with the wire fields", c do
    body = c |> get_json("") |> json_response(200)

    # The fixture's two evaluated points: one in caution, one nominal, both last sampled in 2023.
    assert [row, nominal] = body["data"]

    assert %{
             "point_id" => "HK.counter",
             "source" => "ground_limit",
             "condition" => "caution",
             "raw_limit_state" => "yellow_high",
             "evaluated" => true,
             "policy_id" => nil,
             "value" => 30,
             "freshness" => "stale",
             "last_sample_at" => "2023-11-15T23:15:00.000000Z",
             "entered_at" => "2023-11-15T23:15:00.000000Z",
             "entered_at_is_lower_bound" => false
           } = row

    assert is_binary(row["evaluated_at"])

    assert %{"point_id" => "HK.voltage", "condition" => "nominal", "freshness" => "stale"} =
             nominal

    assert %{
             "counts" => %{"caution" => 1, "critical" => 0, "stale" => 2, "total" => 2},
             "stale_after_s" => 900,
             "telemetry" => telemetry
           } = body["meta"]

    assert telemetry in ["ok", "degraded"]
    assert body["meta"]["next_cursor"] == nil
  end

  test "a live alarm shows with no ground job, labelled by its source", c do
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
             },
             %{"point_id" => "HK.counter", "source" => "ground_limit"},
             %{"point_id" => "HK.voltage", "source" => "ground_limit"}
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
