defmodule CadenceSimulator.ProviderScaleTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider

  alias CadenceSimulator.Provider.{
    Contacts,
    DeliveryProfiles,
    FleetScenarios,
    Opportunities,
    Orchestrator,
    Store
  }

  @definitions Path.expand(
                 "../../../../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml",
                 __DIR__
               )

  setup do
    :ok = Store.clear()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)
    acceptor = spawn_link(fn -> accept_connections(listener) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(acceptor), do: Process.exit(acceptor, :normal)
    end)

    %{port: port}
  end

  @tag timeout: 60_000
  test "models 500 spacecraft and activates 25 concurrent telemetry contacts", %{port: port} do
    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 500,
        "telemetry_profile" => %{"rate_hz" => 1.0}
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 2026})
    assert {:ok, spacecraft} = Provider.spacecraft(run["id"])
    assert length(spacecraft) == 500
    assert Orchestrator.active_stream_count() == 0

    now = DateTime.utc_now()

    reservations =
      Enum.map(1..25, fn index ->
        station_number = div(index - 1, 10)
        antenna_number = rem(index - 1, 10) + 1

        station_id =
          Enum.at(["station-svalbard", "station-troll", "station-hawaii"], station_number)

        {:ok, reservation} =
          Provider.reserve_contact(%{
            "run_id" => run["id"],
            "opportunity_id" => "scale-opportunity-#{index}",
            "spacecraft_id" => "SC-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}",
            "ground_station_id" => station_id,
            "antenna_id" => "#{station_id}-antenna-#{antenna_number}",
            "starts_at" => DateTime.add(now, 1) |> DateTime.to_iso8601(),
            "ends_at" => DateTime.add(now, 30) |> DateTime.to_iso8601(),
            "data_plane" => %{
              "definitions_path" => @definitions,
              "host" => "127.0.0.1",
              "port" => port,
              "tm_frame_size" => 1115,
              "target_id" => "SIM-1",
              "generator_count" => 1
            }
          })

        reservation
      end)

    :ok = Orchestrator.reconcile(now)
    :ok = Orchestrator.reconcile(now)
    :ok = Orchestrator.reconcile(DateTime.add(now, 1))

    assert Orchestrator.active_stream_count() == 25

    assert Enum.all?(reservations, fn reservation ->
             {:ok, current} = Provider.fetch_reservation(reservation["id"])
             current["status"] == "active"
           end)

    :ok = Orchestrator.reconcile(DateTime.add(now, 31))
    assert Orchestrator.active_stream_count() == 0
  end

  @tag timeout: 60_000
  test "stage five fleet scenario models shared capacity, deterministic rejection, and replay" do
    assert {:ok, scenario} =
             FleetScenarios.stage_five(spacecraft_count: 300)
             |> Provider.create_scenario()

    assert {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 2_035})
    assert {:ok, spacecraft} = Provider.spacecraft(run["id"])
    assert length(spacecraft) == 300
    assert length(run["scenario_snapshot"]["route_profiles"]) == 3

    starts_at = DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)

    search = %{
      "spacecraft_refs" => Enum.map(1..40, &spacecraft_ref/1),
      "ground_station_refs" => ["station-svalbard"],
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => starts_at |> DateTime.add(3_600, :second) |> DateTime.to_iso8601(),
      "page_size" => 100,
      "cursor" => nil
    }

    assert {:error, {:rate_limited, rate_limit}} = Opportunities.search(run, search)
    assert rate_limit["route_profile_ref"] == "route-svalbard-shared"
    assert rate_limit["retry_after_seconds"] == 1

    assert {:ok, %{data: opportunities, truncated: truncated}} =
             Opportunities.search(run, search)

    assert length(opportunities) > 40
    assert is_boolean(truncated)

    assert Enum.all?(opportunities, fn opportunity ->
             opportunity["antenna_or_service_pool_ref"] == "pool-svalbard-realtime" and
               opportunity["extensions"]["route_profile_ref"] == "route-svalbard-shared"
           end)

    assert overlapping_pair(opportunities)

    assert {:ok, %{data: [], truncated: false}} =
             Opportunities.search(run, Map.put(search, "spacecraft_refs", ["SC-UNKNOWN"]))

    assert {:ok, delivery_profile} =
             DeliveryProfiles.provision(run, %{
               "display_name" => "Stage 5 scale sink",
               "client_reference" => "stage-five-scale-sink",
               "direction" => "downlink",
               "delivery_kind" => "realtime_stream",
               "target" => %{
                 "protocol" => "tcp",
                 "mode" => "provider_connects",
                 "host" => "127.0.0.1",
                 "port" => 49_999
               },
               "framing" => %{
                 "family" => "ccsds_tm",
                 "mode" => "fixed_size",
                 "frame_bytes" => 1_115
               }
             })

    rejected_opportunity =
      Enum.find(opportunities, &scheduling_rejected?(run, &1))

    accepted_opportunity =
      Enum.find(opportunities, &(not scheduling_rejected?(run, &1)))

    assert rejected_opportunity
    assert accepted_opportunity

    assert {:ok, %{"status" => "rejected"}} =
             Contacts.create(
               run,
               contact_request(rejected_opportunity, delivery_profile, "rejected"),
               request_id: "stage-five-partial-rejection"
             )

    assert {:ok, accepted_contact} =
             Contacts.create(
               run,
               contact_request(accepted_opportunity, delivery_profile, "accepted"),
               request_id: "stage-five-accepted"
             )

    assert accepted_contact["status"] in ["pending", "confirmed"]

    conflicting_opportunity =
      Enum.find(opportunities, fn opportunity ->
        opportunity["id"] != accepted_opportunity["id"] and
          not scheduling_rejected?(run, opportunity) and
          overlaps?(opportunity, accepted_opportunity)
      end)

    assert conflicting_opportunity

    assert {:error, {:no_capacity, _detail}} =
             Contacts.create(
               run,
               contact_request(conflicting_opportunity, delivery_profile, "conflict"),
               request_id: "stage-five-exclusive-pool-conflict"
             )

    before_restart = Store.events_for_run(run["id"], 0, 500)
    assert before_restart.data != []
    previous_store = Process.whereis(Store)
    Process.exit(previous_store, :kill)

    assert_eventually(fn ->
      current_store = Process.whereis(Store)
      is_pid(current_store) and current_store != previous_store and Process.alive?(current_store)
    end)

    after_restart = Store.events_for_run(run["id"], 0, 500)

    assert Enum.map(after_restart.data, & &1["id"]) ==
             Enum.map(before_restart.data, & &1["id"])

    assert after_restart.next_cursor == before_restart.next_cursor
  end

  defp accept_connections(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        receiver = spawn_link(fn -> receive_loop_start() end)
        :ok = :gen_tcp.controlling_process(socket, receiver)
        send(receiver, {:socket, socket})
        accept_connections(listener)

      {:error, :closed} ->
        :ok
    end
  end

  defp receive_loop_start do
    receive do
      {:socket, socket} -> receive_loop(socket)
    end
  end

  defp receive_loop(socket) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, _bytes} -> receive_loop(socket)
      {:error, _reason} -> :ok
    end
  end

  defp spacecraft_ref(index) do
    "SC-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}"
  end

  defp scheduling_rejected?(run, opportunity) do
    rate = get_in(run, ["scenario_snapshot", "fault_profile", "scheduling_rejection_rate"])

    :erlang.phash2(
      {run["seed"], opportunity["id"], :scheduling_rejection},
      1_000_000
    ) /
      1_000_000 < rate
  end

  defp contact_request(opportunity, delivery_profile, suffix) do
    %{
      "opportunity_ref" => opportunity["id"],
      "spacecraft_ref" => opportunity["spacecraft_ref"],
      "service_profile_ref" => opportunity["service_profile_ref"],
      "delivery_profile_ref" => delivery_profile["id"],
      "client_reference" => "stage-five-scale-#{suffix}",
      "tags" => %{"qualification" => "stage-five"}
    }
  end

  defp overlapping_pair(opportunities) do
    opportunities
    |> Enum.with_index()
    |> Enum.any?(fn {left, index} ->
      opportunities
      |> Enum.drop(index + 1)
      |> Enum.any?(&overlaps?(left, &1))
    end)
  end

  defp overlaps?(left, right) do
    {:ok, left_start, _offset} = DateTime.from_iso8601(left["starts_at"])
    {:ok, left_end, _offset} = DateTime.from_iso8601(left["ends_at"])
    {:ok, right_start, _offset} = DateTime.from_iso8601(right["starts_at"])
    {:ok, right_end, _offset} = DateTime.from_iso8601(right["ends_at"])

    DateTime.before?(left_start, right_end) and DateTime.before?(right_start, left_end)
  end

  defp assert_eventually(fun, attempts \\ 100)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(fun, 0), do: assert(fun.())
end
