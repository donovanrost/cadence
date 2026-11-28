defmodule CadenceWeb.Console.PointAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.MissionReadModelFixtures
  alias CadenceWeb.TestFixtures

  # seed_mission_read_models ingests one HK packet received at this instant.
  @received ~U[2023-11-15 23:15:00Z]

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    MissionReadModelFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)

    %{user: user, mission: mission}
  end

  defp get_json(c, path) do
    c.user
    |> TestFixtures.member_conn()
    |> get("/api/v1/missions/#{c.mission.mission_id}" <> path)
  end

  defp window do
    from = DateTime.add(@received, -1_800) |> DateTime.to_iso8601()
    to = DateTime.add(@received, 1_800) |> DateTime.to_iso8601()
    "from=#{URI.encode_www_form(from)}&to=#{URI.encode_www_form(to)}"
  end

  test "returns decimated history buckets for a point", c do
    data =
      c
      |> get_json(
        "/telemetry/points/HK.counter/history?#{window()}&max_points=60&spacecraft_id=spacecraft-001"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["point_id"] == "HK.counter"
    assert data["bucket_width_ms"] == 60_000
    assert data["truncated"] == false
    assert [%{"min" => 30, "max" => 30, "mean" => 30.0, "count" => 1, "t" => _}] = data["buckets"]
  end

  test "an empty window has no buckets", c do
    data =
      c
      |> get_json(
        "/telemetry/points/HK.counter/history?from=2020-01-01T00:00:00Z&to=2020-01-01T01:00:00Z"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["buckets"] == []
  end

  test "rejects bad windows and point budgets", c do
    conn = get_json(c, "/telemetry/points/HK.counter/history?from=nope")
    assert json_response(conn, 422)["error"]["details"]["from"]

    conn = get_json(c, "/telemetry/points/HK.counter/history?max_points=99999")
    assert json_response(conn, 422)["error"]["details"]["max_points"]

    conn =
      get_json(
        c,
        "/telemetry/points/HK.counter/history?from=2026-01-02T00:00:00Z&to=2026-01-01T00:00:00Z"
      )

    assert json_response(conn, 422)["error"]["details"]["from"]
  end

  test "returns limit-definition intervals for a point", c do
    data =
      c
      |> get_json(
        "/limits/points/HK.counter/intervals?from=2000-01-01T00:00:00Z&to=2100-01-01T00:00:00Z"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["point_id"] == "HK.counter"
    assert is_list(data["intervals"])

    for interval <- data["intervals"] do
      assert Map.keys(interval["thresholds"]) |> Enum.sort() ==
               ~w(red_high red_low yellow_high yellow_low)
    end
  end
end
