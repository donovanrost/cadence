defmodule CadenceSimulator.Provider.StoreResilienceTest do
  # qa #46: the Orchestrator crashed when a Store call timed out under load, mid-pass,
  # orphaning streams and uplink peers. A suspended process stands in for one stuck past
  # every call timeout.
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Orchestrator, Store}
  alias CadenceSimulator.StoreRestart

  @definitions Path.expand(
                 "../../../../../dev/catalogs/demo_spacecraft.yaml",
                 __DIR__
               )
  @dets :cadence_simulator_provider_store

  setup do
    :ok = Store.clear()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)
    acceptor = spawn_link(fn -> accept_connections(listener) end)

    on_exit(fn ->
      resume(Process.whereis(Store))
      # Leave no stream running for the next test: with nothing stored, the sweep stops all.
      :ok = Store.clear()
      :ok = Orchestrator.reconcile()
      0 = Orchestrator.active_stream_count()
      :gen_tcp.close(listener)
      if Process.alive?(acceptor), do: Process.exit(acceptor, :normal)
    end)

    %{port: port}
  end

  describe "the Orchestrator tick" do
    @tag timeout: 60_000
    test "keeps running and sweeps while the Store process is stuck", %{port: port} do
      now = DateTime.utc_now()
      reservation = active_reservation(port, now)
      orchestrator = Process.whereis(Orchestrator)
      assert Orchestrator.active_stream_count() == 1

      :ok = :sys.suspend(Store)

      {:ok, _canceled} =
        Provider.update_reservation_status(reservation, "canceled", "store_resilience_test")

      assert :ok = Orchestrator.reconcile(DateTime.add(now, 2))
      assert Orchestrator.active_stream_count() == 0
      # The periodic 100 ms ticks ran against the stuck Store too.
      Process.sleep(300)
      assert Process.whereis(Orchestrator) == orchestrator
      assert Process.alive?(orchestrator)

      :ok = :sys.resume(Store)
      :ok = Store.flush()

      assert [{_key, %{"status" => "canceled"}}] =
               :dets.lookup(@dets, {:reservation, reservation["id"]})
    end

    @tag timeout: 60_000
    test "skips, without stopping streams, while the Store's tables are gone", %{port: port} do
      now = DateTime.utc_now()
      _reservation = active_reservation(port, now)
      orchestrator = Process.whereis(Orchestrator)

      :ok = Supervisor.terminate_child(CadenceSimulator.Supervisor, Store)

      try do
        assert :ok = Orchestrator.reconcile(DateTime.add(now, 2))
        assert Process.whereis(Orchestrator) == orchestrator
        # The sweep couldn't read the active set, so it kept the stream.
        assert Orchestrator.active_stream_count() == 1
      after
        {:ok, _store} = Supervisor.restart_child(CadenceSimulator.Supervisor, Store)
      end
    end

    @tag timeout: 60_000
    test "a step that failed after starting a stream leaves exactly one running", %{port: port} do
      now = DateTime.utc_now()
      reservation = active_reservation(port, now)
      orchestrator = Process.whereis(Orchestrator)
      %{pid: started} = :sys.get_state(Orchestrator).streams[reservation["id"]]

      # What guarded/3 leaves when the status write raises after start_stream (the Store's
      # tables gone): the stream runs, linked, but the state from before the step doesn't
      # track it, and the reservation still reads acquiring.
      :sys.replace_state(
        Orchestrator,
        &%{&1 | streams: Map.delete(&1.streams, reservation["id"])}
      )

      {:ok, _acquiring} = Provider.update_reservation_status(reservation, "acquiring")

      :ok = Orchestrator.reconcile(DateTime.add(now, 2))

      refute Process.alive?(started)
      assert Orchestrator.active_stream_count() == 1
      assert [_one] = linked_runtime_children(orchestrator)
      assert {:ok, %{"status" => "active"}} = Provider.fetch_reservation(reservation["id"])
    end

    @tag timeout: 60_000
    test "stops a stream that doesn't answer its stats call", %{port: port} do
      now = DateTime.utc_now()
      reservation = active_reservation(port, now)
      orchestrator = Process.whereis(Orchestrator)
      %{pid: stream} = :sys.get_state(Orchestrator).streams[reservation["id"]]

      :ok = :sys.suspend(stream)

      {:ok, _canceled} =
        Provider.update_reservation_status(reservation, "canceled", "store_resilience_test")

      assert :ok = Orchestrator.reconcile(DateTime.add(now, 2))
      assert Orchestrator.active_stream_count() == 0
      assert Process.whereis(Orchestrator) == orchestrator
    end
  end

  describe "reads and writes" do
    test "don't wait on the Store process, and persist once it runs again" do
      :ok = :sys.suspend(Store)

      assert {:ok, _scenario} = Store.put(:scenario, %{"id" => "scenario-stuck"})
      assert {:ok, %{"id" => "scenario-stuck"}} = Store.fetch(:scenario, "scenario-stuck")
      assert [%{"id" => "scenario-stuck"}] = Store.list(:scenario)
      assert {:ok, %{"sequence" => sequence}} = Store.append_event(%{"run_id" => "run-a"})
      assert [] = :dets.lookup(@dets, {:scenario, "scenario-stuck"})

      :ok = :sys.resume(Store)
      :ok = Store.flush()

      assert [{_key, %{"id" => "scenario-stuck"}}] =
               :dets.lookup(@dets, {:scenario, "scenario-stuck"})

      assert [{_key, %{"sequence" => ^sequence}}] = :dets.lookup(@dets, {:event, sequence})
    end

    test "a clean stop persists writes still queued, and a restart reloads them" do
      orchestrator = Process.whereis(Orchestrator)
      store = Process.whereis(Store)
      :ok = :sys.suspend(store)
      {:ok, _run} = Store.put(:run, %{"id" => "run-queued", "state" => "running"})

      :ok = GenServer.stop(store)
      # #331: back under its name AND past init/1, so its ETS mirror exists before the read.
      restarted = StoreRestart.await(store)

      assert restarted != store
      assert {:ok, %{"state" => "running"}} = Store.fetch(:run, "run-queued")
      assert Process.whereis(Orchestrator) == orchestrator
    end

    test "list returns one kind, newest first" do
      {:ok, _old} = Store.put(:run, %{"id" => "run-old", "created_at" => "2026-11-01T00:00:00Z"})
      {:ok, _new} = Store.put(:run, %{"id" => "run-new", "created_at" => "2026-11-02T00:00:00Z"})
      {:ok, _other} = Store.put(:scenario, %{"id" => "scenario-x"})

      assert ["run-new", "run-old"] = Enum.map(Store.list(:run), & &1["id"])
    end
  end

  describe "events" do
    setup do
      for run_id <- ~w(run-a run-b run-a run-b run-b) do
        {:ok, _event} = Store.append_event(%{"run_id" => run_id})
      end

      :ok
    end

    test "page in sequence order after the cursor" do
      assert %{data: data, next_cursor: 3} = Store.events(1, 2)
      assert [2, 3] = Enum.map(data, & &1["sequence"])
      assert %{data: [], next_cursor: 5} = Store.events(5, 10)
    end

    test "for a run skip the other runs' events" do
      assert %{data: [%{"sequence" => 1}, %{"sequence" => 3}], next_cursor: 3} =
               Store.events_for_run("run-a", 0, 10)

      assert %{data: [%{"sequence" => 2}], next_cursor: 2} = Store.events_for_run("run-b", 0, 1)
      # Nothing more for run-a: the cursor moves past every event read.
      assert %{data: [], next_cursor: 5} = Store.events_for_run("run-a", 3, 10)
      assert %{data: [], next_cursor: 5} = Store.events_for_run("run-c", 5, 10)
    end
  end

  test "a fault counter is consumed exactly up to its limit" do
    assert Store.consume_fault("run-a", "drop", 2)
    assert Store.consume_fault("run-a", "drop", 2)
    refute Store.consume_fault("run-a", "drop", 2)
    refute Store.consume_fault("run-a", "drop", 2)
    refute Store.consume_fault("run-a", "never", 0)

    :ok = Store.flush()
    assert [{_key, 2}] = :dets.lookup(@dets, {:fault_counter, "run-a", "drop"})
  end

  defp active_reservation(port, now) do
    {:ok, scenario} = Provider.create_scenario(%{"spacecraft_count" => 1})
    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 46})

    {:ok, reservation} =
      Provider.reserve_contact(%{
        "run_id" => run["id"],
        "opportunity_id" => "store-resilience",
        "spacecraft_id" => "SC-001",
        "ground_station_id" => "station-svalbard",
        "antenna_id" => "station-svalbard-antenna-1",
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

    :ok = Orchestrator.reconcile(now)
    :ok = Orchestrator.reconcile(now)
    :ok = Orchestrator.reconcile(DateTime.add(now, 1))
    {:ok, active} = Provider.fetch_reservation(reservation["id"])
    assert active["status"] == "active"
    active
  end

  defp linked_runtime_children(orchestrator) do
    supervisor = Process.whereis(CadenceSimulator.RuntimeSupervisor)
    {:links, links} = Process.info(orchestrator, :links)

    Enum.filter(links, fn pid ->
      is_pid(pid) and Process.info(pid, :parent) == {:parent, supervisor}
    end)
  end

  defp resume(nil), do: :ok

  defp resume(pid) do
    :sys.resume(pid)
  catch
    _kind, _reason -> :ok
  end

  defp accept_connections(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        spawn(fn -> drain(socket) end)
        accept_connections(listener)

      {:error, _reason} ->
        :ok
    end
  end

  defp drain(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, _data} -> drain(socket)
      {:error, _reason} -> :ok
    end
  end
end
