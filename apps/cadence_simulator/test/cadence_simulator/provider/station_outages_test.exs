defmodule CadenceSimulator.Provider.StationOutagesTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Contacts, FaultProfile, Opportunities, Store}
  alias CadenceSimulator.TestProviderFixtures

  setup do
    :ok = Store.clear()
    :ok
  end

  test "an outage marks the station's passes unavailable, rejects bookings and is reported" do
    context = TestProviderFixtures.create_contact!(%{}, run_state: "paused")
    station = context.opportunity["ground_station_ref"]

    {:ok, run} =
      Provider.configure_run_faults(context.run["id"], %{
        "station_outages" => [
          %{
            "id" => "svb-down",
            "ground_station_id" => station,
            "starts_at" => "2026-07-17T00:00:00Z",
            "ends_at" => "2026-07-18T00:00:00Z",
            "reason" => "Antenna fire"
          }
        ]
      })

    {:ok, stations} = Provider.ground_stations(run["id"])

    assert [%{"id" => "svb-down", "kind" => "outage", "reason" => "Antenna fire"}] =
             Enum.find(stations, &(&1["id"] == station))["availability_windows"]

    {:ok, %{data: opportunities}} =
      Opportunities.search(run, %{
        "spacecraft_refs" => ["SC-001"],
        "ground_station_refs" => [],
        "service_profile_ref" => "service-realtime-ttc-downlink",
        "starts_at" => "2026-07-17T12:00:00Z",
        "ends_at" => "2026-07-17T13:00:00Z",
        "page_size" => 25
      })

    {down, up} = Enum.split_with(opportunities, &(&1["ground_station_ref"] == station))
    assert down != [] and Enum.all?(down, &(&1["availability"] == "unavailable"))
    assert Enum.all?(up, &(&1["availability"] == "available"))

    opportunity = Enum.find(down, &(&1["id"] != context.opportunity["id"]))

    request = %{
      context.request
      | "opportunity_ref" => opportunity["id"],
        "client_reference" => "outage-booking"
    }

    assert {:ok, %{"status" => "rejected", "status_reason" => "station_unavailable"}} =
             Contacts.create(run, request, idempotency_key: "outage-booking")
  end

  test "station outages are validated" do
    assert {:ok, %{"station_outages" => [%{"kind" => "outage", "ends_at" => nil}]}} =
             FaultProfile.normalize(%{
               "station_outages" => [
                 %{"ground_station_id" => "svb", "starts_at" => "2026-07-17T00:00:00Z"}
               ]
             })

    for bad <- [
          %{"ground_station_id" => "svb"},
          %{"ground_station_id" => "svb", "starts_at" => "2026-07-17T00:00:00Z", "kind" => "x"},
          %{
            "ground_station_id" => "svb",
            "starts_at" => "2026-07-17T02:00:00Z",
            "ends_at" => "2026-07-17T01:00:00Z"
          }
        ] do
      assert {:error, {:invalid, "fault_profile.station_outages is invalid"}} =
               FaultProfile.normalize(%{"station_outages" => [bad]})
    end
  end
end
