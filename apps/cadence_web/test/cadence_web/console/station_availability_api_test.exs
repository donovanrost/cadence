defmodule CadenceWeb.Console.StationAvailabilityAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    {:ok, _} =
      GroundStationStore.persist_ground_station(
        org.organization_id,
        GroundStation.new(%{
          ground_station_id: "gs-svb",
          mission_id: mission.mission_id,
          display_name: "Svalbard",
          code: "SVB"
        })
      )

    %{user: user, base: "/api/v1/missions/#{mission.mission_id}/station-availability"}
  end

  defp conn(c), do: TestFixtures.member_conn(c.user)
  defp iso(seconds), do: DateTime.utc_now() |> DateTime.add(seconds) |> DateTime.to_iso8601()

  test "a station with nothing reported is up; maintenance makes it down with the window", c do
    data = conn(c) |> get(c.base) |> json_response(200) |> Map.fetch!("data")

    assert [
             %{
               "ground_station_id" => "gs-svb",
               "state" => "up",
               "since" => nil,
               "basis" => "no reported windows"
             }
           ] = data["stations"]

    window =
      conn(c)
      |> post(c.base <> "/gs-svb/windows", %{
        "kind" => "maintenance",
        "starts_at" => iso(-60),
        "ends_at" => iso(3_600),
        "reason" => "Antenna service"
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert %{"kind" => "maintenance", "source" => "operator", "reason" => "Antenna service"} =
             window

    shown = conn(c) |> get(c.base <> "/gs-svb") |> json_response(200) |> Map.fetch!("data")
    assert %{"state" => "down", "source" => "operator"} = shown["status"]
    assert [%{"id" => id}] = shown["windows"]
    assert id == window["id"]

    assert %{"error" => %{"code" => "window_overlaps"}} =
             conn(c)
             |> post(c.base <> "/gs-svb/windows", %{
               "kind" => "maintenance",
               "starts_at" => iso(0),
               "ends_at" => iso(60)
             })
             |> json_response(409)

    cleared =
      conn(c)
      |> post(c.base <> "/windows/#{id}/clear", %{"reason" => "Done early"})
      |> json_response(200)

    assert cleared["data"]["cleared_at"]

    assert %{"data" => %{"status" => %{"state" => "up"}}} =
             conn(c) |> get(c.base <> "/gs-svb") |> json_response(200)
  end

  test "impact counts booked passes at the station", c do
    data = conn(c) |> get(c.base <> "/gs-svb/impact") |> json_response(200) |> Map.fetch!("data")

    assert %{
             "ground_station_id" => "gs-svb",
             "passes_hit" => 0,
             "reservation_ids" => [],
             "truncated" => false
           } = data
  end

  test "validation and unknown resources", c do
    assert %{"error" => %{"code" => "invalid_params", "details" => %{"kind" => _}}} =
             conn(c)
             |> post(c.base <> "/gs-svb/windows", %{"kind" => "storm", "starts_at" => iso(0)})
             |> json_response(422)

    assert %{"error" => %{"code" => "station_not_found"}} =
             conn(c)
             |> post(c.base <> "/nope/windows", %{"kind" => "outage", "starts_at" => iso(0)})
             |> json_response(404)

    assert %{"error" => %{"code" => "window_not_found"}} =
             conn(c) |> post(c.base <> "/windows/nope/clear", %{}) |> json_response(404)
  end
end
