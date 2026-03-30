defmodule Cadence.Telemetry.BackendLoadingTest do
  use ExUnit.Case, async: false

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
end
