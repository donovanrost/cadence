defmodule Cadence.Telemetry.BackendLoadingTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.HistoryStore

  test "current value store child_spec loads a configured backend module before checking exports" do
    backend = Cadence.TestSupport.LazyCurrentValueStore
    previous_config = Application.get_env(:cadence, :telemetry_current_value_store, [])

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_current_value_store, previous_config)
      Code.ensure_loaded(backend)
    end)

    Application.put_env(:cadence, :telemetry_current_value_store, module: backend)
    :code.purge(backend)
    :code.delete(backend)

    assert :code.is_loaded(backend) == false

    assert %{start: {^backend, :start_link, [[]]}} = CurrentValueStore.child_spec()
    assert match?({:file, _path}, :code.is_loaded(backend))
  end

  test "history store child_spec can evaluate an unloaded noop backend" do
    backend = Cadence.TestSupport.LazyHistoryStore
    previous_config = Application.get_env(:cadence, :telemetry_history_store, [])

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_history_store, previous_config)
      Code.ensure_loaded(backend)
    end)

    Application.put_env(:cadence, :telemetry_history_store, module: backend)
    :code.purge(backend)
    :code.delete(backend)

    assert :code.is_loaded(backend) == false

    assert HistoryStore.child_spec() == nil
    assert match?({:file, _path}, :code.is_loaded(backend))
  end

  test "store facades retain compatibility with optionless backends" do
    current_policy =
      CurrentValueStore.policy(
        module: Cadence.TestSupport.LazyCurrentValueStore,
        client_identity: :ignored_by_legacy_backend
      )

    history_policy =
      HistoryStore.policy(
        module: Cadence.TestSupport.LazyHistoryStore,
        client_identity: :ignored_by_legacy_backend
      )

    assert CurrentValueStore.hot_path_safe?(current_policy)
    assert :ok = CurrentValueStore.record_samples(current_policy, [])
    assert :ok = CurrentValueStore.replace_value(current_policy, "mission", "point", nil, [])
    assert :ok = CurrentValueStore.replace_values_for_scope(current_policy, "mission", [], [])
    assert CurrentValueStore.latest_value(current_policy, "mission", "point", []) == nil
    assert CurrentValueStore.latest_values_for_mission(current_policy, "mission", []) == []
    assert :ok = CurrentValueStore.reset(current_policy, "mission")
    assert :ok = CurrentValueStore.reset(current_policy)

    assert :ok = HistoryStore.persist_samples(history_policy, [])
    assert HistoryStore.sample_history(history_policy, "mission", "point", []) == []

    assert {:ok, %{samples: [], diagnostics: %{}}} =
             HistoryStore.sample_history_result(history_policy, "mission", "point", [])

    assert :ok = HistoryStore.reset(history_policy)
  end
end
