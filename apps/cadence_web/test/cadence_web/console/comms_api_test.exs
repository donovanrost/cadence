defmodule CadenceWeb.Console.CommsAPITest do
  use CadenceWeb.ConnCase, async: true

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{
      user: user,
      org: org,
      mission: mission,
      base: "/api/console/v1/missions/#{mission.mission_id}"
    }
  end

  defp get_data(c, path),
    do:
      c.user
      |> TestFixtures.member_conn()
      |> get(c.base <> path)
      |> json_response(200)
      |> Map.fetch!("data")

  test "empty mission lists no stations, transports or rules", c do
    assert get_data(c, "/ground-stations") == %{"stations" => []}
    assert get_data(c, "/transports") == %{"transports" => []}
    assert get_data(c, "/routing-rules") == %{"rules" => [], "total" => 0, "next_cursor" => nil}
  end

  test "lists a ground station with unknown health and links", c do
    station =
      GroundStation.new(%{
        ground_station_id: "gs-svalbard",
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        display_name: "Svalbard",
        provider: "KSAT",
        region: "Arctic",
        metadata: %{"code" => "SVB"}
      })

    {:ok, _} =
      GroundStationStore.persist_ground_station(c.org.organization_id, station)

    assert [row] = get_data(c, "/ground-stations")["stations"]

    assert %{
             "id" => "gs-svalbard",
             "display_name" => "Svalbard",
             "code" => "SVB",
             "provider" => "KSAT",
             "lifecycle_state" => "active",
             "transport_count" => nil,
             "health" => nil
           } = row
  end

  test "routing rules reject a bad page size", c do
    conn = c.user |> TestFixtures.member_conn() |> get(c.base <> "/routing-rules?limit=0")
    assert json_response(conn, 422)["error"]["details"]["limit"]
  end

  test "kind schemas generate station and transport forms", c do
    station = get_data(c, "/config/kinds/ground_station/schema")
    assert Enum.map(station["fields"], & &1["path"]) == ~w(display_name provider region)

    transport = get_data(c, "/config/kinds/transport/schema")
    paths = Enum.map(transport["fields"], & &1["path"])
    assert "configuration.mode" in paths
    assert "configuration.port" in paths

    port = Enum.find(transport["fields"], &(&1["path"] == "configuration.port"))
    assert %{"type" => "integer", "range" => %{"min" => 1, "max" => 65_535}} = port

    conn = c.user |> TestFixtures.member_conn() |> get(c.base <> "/config/kinds/nope/schema")
    assert json_response(conn, 422)["error"]["code"] == "invalid_params"
  end
end
