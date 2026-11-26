defmodule CadenceSimulator.Provider.StoreResilienceTest do
  # qa #46: the Orchestrator crashed when a Store call timed out under load, mid-pass,
  # orphaning streams and uplink peers. A suspended process stands in for one stuck past
  # every call timeout.
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Orchestrator, Router, Store}
  alias CadenceSimulator.StoreRestart

  @definitions Path.expand(
                 "../../../../../dev/catalogs/demo_spacecraft.yaml",
                 __DIR__
               )
  @mirror :cadence_simulator_provider_store_mirror
  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # The fixture restores the shared store before this callback reconciles streams.
    on_exit(fn ->
      :ok = Orchestrator.reconcile()
      0 = Orchestrator.active_stream_count()
    end)

    store_fixture = StoreRestart.isolate!(tmp_dir)
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)
    acceptor = spawn_link(fn -> accept_connections(listener) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(acceptor), do: Process.exit(acceptor, :normal)
    end)

    %{port: port, store_fixture: store_fixture}
  end

  describe "the Orchestrator tick" do
    @tag timeout: 60_000
    test "keeps running and sweeps while the Store process is stuck", %{
      port: port,
      store_fixture: store_fixture
    } do
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

      StoreRestart.reload(store_fixture)

      assert {:ok, %{"status" => "canceled"}} = Provider.fetch_reservation(reservation["id"])
    end

    @tag timeout: 60_000
    test "skips, without stopping streams, while the Store's tables are gone", %{
      port: port,
      store_fixture: store_fixture
    } do
      now = DateTime.utc_now()
      _reservation = active_reservation(port, now)
      orchestrator = Process.whereis(Orchestrator)

      :ok = Supervisor.terminate_child(store_fixture.supervisor, Store)

      assert :ok = Orchestrator.reconcile(DateTime.add(now, 2))
      assert Process.whereis(Orchestrator) == orchestrator
      # The sweep couldn't read the active set, so it kept the stream.
      assert Orchestrator.active_stream_count() == 1
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
    test "don't wait on the Store process, and persist once it runs again", %{
      store_fixture: store_fixture
    } do
      :ok = Store.clear()
      :ok = :sys.suspend(Store)
      snapshot = File.read!(store_fixture.path)

      assert {:ok, _scenario} = Store.put(:scenario, %{"id" => "scenario-stuck"})
      assert {:ok, %{"id" => "scenario-stuck"}} = Store.fetch(:scenario, "scenario-stuck")
      assert [%{"id" => "scenario-stuck"}] = Store.list(:scenario)
      assert {:ok, %{"sequence" => sequence}} = Store.append_event(%{"run_id" => "run-a"})
      assert File.read!(store_fixture.path) == snapshot

      :ok = :sys.resume(Store)
      :ok = Store.flush()
      StoreRestart.reload(store_fixture)

      assert {:ok, %{"id" => "scenario-stuck"}} = Store.fetch(:scenario, "scenario-stuck")
      assert %{data: [%{"sequence" => ^sequence}]} = Store.events()
    end

    test "a clean stop persists writes still queued, and a restart reloads them", %{
      store_fixture: store_fixture
    } do
      orchestrator = Process.whereis(Orchestrator)
      store = Process.whereis(Store)
      :ok = :sys.suspend(store)
      {:ok, _run} = Store.put(:run, %{"id" => "run-queued", "state" => "running"})

      :ok = GenServer.stop(store)
      restarted = StoreRestart.await(store_fixture)

      assert restarted != store
      assert {:ok, %{"state" => "running"}} = Store.fetch(:run, "run-queued")
      assert Process.whereis(Orchestrator) == orchestrator
    end

    test "publishes changes on the snapshot timer", %{store_fixture: store_fixture} do
      observer = self()
      :sys.replace_state(Store, &Map.put(&1, :snapshot_observer, observer))
      {:ok, _scenario} = Store.put(:scenario, %{"id" => "periodic"})

      assert_receive {:provider_store_snapshot, _timing}, 3_000
      StoreRestart.reload(store_fixture)

      assert {:ok, %{"id" => "periodic"}} = Store.fetch(:scenario, "periodic")
    end

    test "acknowledged POSTs share a snapshot and survive a hard restart", %{
      store_fixture: store_fixture
    } do
      server =
        start_supervised!(
          {Bandit, plug: {Router, provider_auth: []}, scheme: :http, ip: {127, 0, 0, 1}, port: 0}
        )

      {:ok, {_address, port}} = ThousandIsland.listener_info(server)
      url = "http://127.0.0.1:#{port}/admin/v1/scenarios"
      store = Process.whereis(Store)
      observer = self()
      :sys.replace_state(store, &Map.put(&1, :snapshot_observer, observer))

      ids = ["published-first", "published-second"]
      :ok = :sys.suspend(store)
      requests = Enum.map(ids, &post_scenario(url, &1))

      try do
        await_scenarios(ids)
        assert Enum.all?(Task.yield_many(requests, 50), fn {_task, result} -> is_nil(result) end)
      after
        :ok = :sys.resume(store)
      end

      responses = Task.await_many(requests)
      assert Enum.map(responses, & &1.status) == [201, 201]
      assert Enum.map(responses, &get_in(&1.body, ["data", "id"])) == ids
      assert_received {:provider_store_snapshot, _timing}
      refute_received {:provider_store_snapshot, _timing}

      :ok = :sys.suspend(store)
      unacknowledged = post_scenario(url, "unpublished")

      try do
        await_scenarios(["unpublished"])
        File.write!(store_fixture.path <> ".tmp", "incomplete snapshot")
        Process.exit(store, :kill)
      after
        resume(store)
      end

      assert %{status: 503, body: %{"error" => %{"retryable" => true}}} =
               Task.await(unacknowledged)

      StoreRestart.await(store_fixture)

      for id <- ids do
        assert {:ok, %{"id" => ^id}} = Store.fetch(:scenario, id)
      end

      assert {:error, :not_found} = Store.fetch(:scenario, "unpublished")
    end

    @tag capture_log: true
    test "a failed snapshot restore leaves the shared supervisor running", %{
      store_fixture: %{supervisor: supervisor, path: path}
    } do
      shared_supervisor = Process.whereis(CadenceSimulator.Supervisor)
      monitor = Process.monitor(supervisor)
      store = Process.whereis(Store)
      :ok = :sys.suspend(store)
      File.write!(path, "invalid snapshot")
      Process.exit(store, :kill)

      assert_receive {:DOWN, ^monitor, :process, ^supervisor, :shutdown}, 10_000
      assert Process.alive?(shared_supervisor)
      assert Process.whereis(Store) == nil
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

    test "allocates after recovered events when the saved sequence trails them", %{
      store_fixture: store_fixture
    } do
      true = :ets.insert(@mirror, {{:metadata, :event_sequence}, 4})
      :ok = Store.flush()
      StoreRestart.reload(store_fixture)

      assert {:ok, %{"sequence" => 6}} = Store.append_event(%{"run_id" => "run-a"})
      assert %{data: [%{"sequence" => 5}, %{"sequence" => 6}]} = Store.events(4, 10)
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

  test "a fault counter is consumed exactly up to its limit", %{store_fixture: store_fixture} do
    assert Store.consume_fault("run-a", "drop", 2)
    assert Store.consume_fault("run-a", "drop", 2)
    refute Store.consume_fault("run-a", "drop", 2)
    refute Store.consume_fault("run-a", "drop", 2)
    refute Store.consume_fault("run-a", "never", 0)

    :ok = Store.flush()
    StoreRestart.reload(store_fixture)
    refute Store.consume_fault("run-a", "drop", 2)
  end

  defp post_scenario(url, id) do
    Task.async(fn ->
      Req.post!(url, json: %{"id" => id, "spacecraft_count" => 1}, retry: false)
    end)
  end

  defp await_scenarios(ids, attempts \\ 100)

  defp await_scenarios(ids, 0) do
    Enum.each(ids, fn id -> assert {:ok, _scenario} = Store.fetch(:scenario, id) end)
  end

  defp await_scenarios(ids, attempts) do
    unless Enum.all?(ids, &match?({:ok, _scenario}, Store.fetch(:scenario, &1))) do
      Process.sleep(10)
      await_scenarios(ids, attempts - 1)
    end
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
