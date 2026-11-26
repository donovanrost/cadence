defmodule CadenceSimulator.StoreRestart do
  @moduledoc false

  import ExUnit.Callbacks, only: [on_exit: 1, start_supervised!: 1]

  alias CadenceSimulator.Provider.Store

  @app_supervisor CadenceSimulator.Supervisor

  def isolate!(tmp_dir) do
    :ok = Store.clear()

    # ExUnit stops the test supervisor before running on_exit, even on failure.
    on_exit(fn ->
      {:ok, _pid} = Supervisor.restart_child(@app_supervisor, Store)
    end)

    :ok = Supervisor.terminate_child(@app_supervisor, Store)

    path = Path.join(tmp_dir, "provider-store.ets")
    ready = make_ref()

    child =
      Supervisor.child_spec({Store, path: path},
        start: {__MODULE__, :start_store, [path, self(), ready]}
      )

    supervisor =
      start_supervised!(%{
        id: __MODULE__,
        start: {Supervisor, :start_link, [[child], [strategy: :one_for_one]]},
        type: :supervisor,
        restart: :temporary
      })

    fixture = %{supervisor: supervisor, path: path, ready: ready}
    await(fixture)
    fixture
  end

  # The supervisor invokes this on every start. Store.start_link returns only
  # after init has restored the snapshot and set up all the named ETS tables.
  def start_store(path, test, ready) do
    with {:ok, pid} <- Store.start_link(path: path) do
      send(test, {ready, pid})
      {:ok, pid}
    end
  end

  def await(%{supervisor: supervisor, ready: ready}) do
    monitor = Process.monitor(supervisor)

    try do
      receive do
        {^ready, pid} ->
          pid

        {:DOWN, ^monitor, :process, ^supervisor, reason} ->
          exit({:test_store_supervisor_down, reason})
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  def reload(%{supervisor: supervisor} = fixture) do
    :ok = Supervisor.terminate_child(supervisor, Store)
    {:ok, pid} = Supervisor.restart_child(supervisor, Store)
    ^pid = await(fixture)
  end
end
