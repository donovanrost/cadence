defmodule CadenceWeb.Console.TelemetryPointAPITest do
  @moduledoc "M23 point search."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.MonitoringPlanFixtures
  alias Cadence.Telemetry.CurrentValueStore
  alias CadenceWeb.{MissionReadModelFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    MissionReadModelFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)

    {:ok, _activation} =
      Cadence.Activations.record_binding_set_activation(
        org.organization_id,
        mission.mission_id,
        "read-models",
        1,
        binding_set_content_sha256: String.duplicate("0", 64)
      )

    %{user: user, org: org, mission: mission}
  end

  # The mission's active monitoring plan evaluates these points' parameters (the catalog points
  # of the seeded packet carry no parameter id, so a point is its own parameter).
  defp monitor(c, points) do
    MonitoringPlanFixtures.activate!(
      c.org.organization_id,
      c.mission.mission_id,
      {"read-models", 1},
      for(
        point <- points,
        do:
          {"limit-" <> String.replace(point, ".", "-"),
           "/parameters/" <> String.replace(point, ".", "-"), above: 10, parameter_id: point}
      )
    )
  end

  defp get_json(c, query) do
    c.user
    |> TestFixtures.member_conn()
    |> get("/api/v1/missions/#{c.mission.mission_id}/telemetry/points" <> query)
  end

  test "searches the active points by id, name or description", c do
    points = c |> get_json("?q=COUNT") |> json_response(200) |> get_in(["data", "points"])

    assert [
             %{"id" => "HK.counter", "name" => "counter", "subsystem" => "HK", "unit" => "count"} =
               point
           ] =
             points

    assert point["type"] == "numeric"
    assert point["latest"] == nil

    assert c
           |> get_json("?q=nothing-like-this")
           |> json_response(200)
           |> get_in(["data", "points"]) ==
             []
  end

  test "with a spacecraft, points carry the latest value and limit state", c do
    craft = TestFixtures.persist_spacecraft!(c.mission)
    data = c |> get_json("?spacecraft_id=#{craft.spacecraft_id}") |> json_response(200)
    assert Enum.all?(data["data"]["points"], &Map.has_key?(&1, "latest"))

    assert json_response(get_json(c, "?spacecraft_id=ghost"), 422)["error"]["details"][
             "spacecraft_id"
           ]

    assert json_response(get_json(c, "?limit=0"), 422)["error"]["details"]["limit"]
  end

  test "after a restart empties the live store, latest falls back to the stored history", c do
    live = c |> get_json("?q=COUNT&spacecraft_id=spacecraft-001") |> json_response(200)
    assert [%{"latest" => %{"source" => "live", "value" => value}}] = live["data"]["points"]

    # What a :4011 restart does to the ETS current-value store.
    :ok = CurrentValueStore.reset(c.mission.mission_id)

    stored = c |> get_json("?q=COUNT&spacecraft_id=spacecraft-001") |> json_response(200)

    assert [
             %{
               "latest" => %{"source" => "history", "value" => ^value, "limit_state" => state}
             }
           ] =
             stored["data"]["points"]

    # The limit state still comes from the alarm states and the plan; never null.
    assert state in ~w(critical caution nominal no_data)
  end

  test "each point says whether it has limits at all (ux T1 'No limits'), with or without latest",
       c do
    monitor(c, ["HK.counter", "HK.voltage"])
    points = c |> get_json("?limit=200") |> json_response(200) |> get_in(["data", "points"])
    by_id = Map.new(points, &{&1["id"], &1})

    assert by_id["HK.counter"]["has_limits"] == true
    assert by_id["HK.voltage"]["has_limits"] == true
    assert by_id["HK.voltage"]["latest"] == nil

    # The next generation's plan drops the voltage policy: the point is still listed, with no
    # limits defined.
    monitor(c, ["HK.counter"])

    after_retire =
      c |> get_json("?q=voltage") |> json_response(200) |> get_in(["data", "points"])

    assert [%{"id" => "HK.voltage", "has_limits" => false}] = after_retire
  end
end
