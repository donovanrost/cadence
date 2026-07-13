defmodule CadenceSimulator.ProviderScaleTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Orchestrator, Store}

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
end
