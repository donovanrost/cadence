defmodule CadenceSimulator.ProviderTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Orchestrator, Store}
  alias CadenceSimulator.SendBuffer

  setup do
    :ok = Store.clear()
    :ok
  end

  test "generates deterministic synthetic opportunities for a 500-spacecraft fleet" do
    {:ok, scenario} = Provider.create_scenario(%{"spacecraft_count" => 500})
    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 42, "speed" => 100.0})
    starts_at = DateTime.utc_now() |> DateTime.add(5) |> DateTime.to_iso8601()
    ends_at = DateTime.utc_now() |> DateTime.add(600) |> DateTime.to_iso8601()

    params = %{
      "run_id" => run["id"],
      "starts_at" => starts_at,
      "ends_at" => ends_at,
      "limit" => 500
    }

    assert {:ok, first} = Provider.search_opportunities(params)
    assert {:ok, second} = Provider.search_opportunities(params)
    assert first["data"] == second["data"]
    assert length(first["data"]) == 500
    assert Enum.all?(first["data"], & &1["synthetic"])
    assert {:ok, spacecraft} = Provider.spacecraft(run["id"])
    assert length(spacecraft) == 500
  end

  test "reservation is idempotent and enforces antenna capacity" do
    {run, opportunity} = opportunity_fixture()
    attrs = reservation_attrs(run, opportunity)

    assert {:ok, first} = Provider.reserve_contact(attrs, "booking-alpha")
    assert {:ok, repeated} = Provider.reserve_contact(attrs, "booking-alpha")
    assert repeated["id"] == first["id"]

    conflicting = Map.put(attrs, "opportunity_id", "another-opportunity")

    assert {:error, {:conflict, "antenna is already reserved"}} =
             Provider.reserve_contact(conflicting, "booking-beta")
  end

  test "fault profile can reject every scheduling request deterministically" do
    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 2,
        "fault_profile" => %{"scheduling_rejection_rate" => 1.0}
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 7})
    {run, opportunity} = opportunity_fixture(run)

    assert {:ok, reservation} = Provider.reserve_contact(reservation_attrs(run, opportunity))
    assert reservation["status"] == "rejected"
    assert reservation["status_reason"] == "fault_profile_scheduling_rejection"
  end

  test "scenario rejects duplicate or malformed provider profiles" do
    duplicate_service = %{
      "id" => "service-duplicate",
      "display_name" => "Duplicate service"
    }

    assert {:error, {:invalid, "service_profiles ids must be unique"}} =
             Provider.create_scenario(%{
               "service_profiles" => [duplicate_service, duplicate_service]
             })

    assert {:error, {:invalid, "delivery_profiles[0].diagnostics is invalid"}} =
             Provider.create_scenario(%{
               "delivery_profiles" => [
                 %{
                   "id" => "delivery-invalid",
                   "display_name" => "Invalid delivery",
                   "diagnostics" => "not-an-object"
                 }
               ]
             })
  end

  test "orchestrator advances a contact through acquisition, active, and completion" do
    {:ok, scenario} = Provider.create_scenario(%{"spacecraft_count" => 1})
    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 9})
    now = DateTime.utc_now()

    attrs = %{
      "run_id" => run["id"],
      "opportunity_id" => "manual-opportunity",
      "spacecraft_id" => "SC-001",
      "ground_station_id" => "station-svalbard",
      "antenna_id" => "station-svalbard-antenna-1",
      "starts_at" => DateTime.add(now, 5) |> DateTime.to_iso8601(),
      "ends_at" => DateTime.add(now, 15) |> DateTime.to_iso8601()
    }

    {:ok, reservation} = Provider.reserve_contact(attrs)
    :ok = Orchestrator.reconcile(now)
    assert {:ok, %{"status" => "scheduled"}} = Provider.fetch_reservation(reservation["id"])

    :ok = Orchestrator.reconcile(DateTime.add(now, 3))
    assert {:ok, %{"status" => "acquiring"}} = Provider.fetch_reservation(reservation["id"])

    :ok = Orchestrator.reconcile(DateTime.add(now, 5))
    assert {:ok, %{"status" => "active"}} = Provider.fetch_reservation(reservation["id"])

    :ok = Orchestrator.reconcile(DateTime.add(now, 16))
    assert {:ok, %{"status" => "completed"}} = Provider.fetch_reservation(reservation["id"])
  end

  test "packet loss is applied in the real network send buffer" do
    {:ok, buffer} =
      SendBuffer.start_link(
        output: nil,
        fault_profile: %{"packet_loss_rate" => 1.0, "latency_ms" => 0, "jitter_ms" => 0}
      )

    SendBuffer.send_packets(buffer, ["alpha", "beta"])
    assert %{packets_dropped: 2, packets_buffered: 0} = SendBuffer.stats(buffer)
    SendBuffer.stop(buffer)
  end

  defp opportunity_fixture(run \\ nil) do
    run =
      run ||
        then(Provider.create_scenario(%{"spacecraft_count" => 2}), fn {:ok, scenario} ->
          {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 5, "speed" => 100.0})
          run
        end)

    params = %{
      "run_id" => run["id"],
      "starts_at" => DateTime.utc_now() |> DateTime.add(5) |> DateTime.to_iso8601(),
      "ends_at" => DateTime.utc_now() |> DateTime.add(7_200) |> DateTime.to_iso8601(),
      "limit" => 1
    }

    {:ok, %{"data" => [opportunity]}} = Provider.search_opportunities(params)
    {run, opportunity}
  end

  defp reservation_attrs(run, opportunity) do
    %{
      "run_id" => run["id"],
      "opportunity_id" => opportunity["id"],
      "spacecraft_id" => opportunity["spacecraft_id"],
      "ground_station_id" => opportunity["ground_station_id"],
      "antenna_id" => opportunity["antenna_id"],
      "starts_at" => opportunity["starts_at"],
      "ends_at" => opportunity["ends_at"]
    }
  end
end
