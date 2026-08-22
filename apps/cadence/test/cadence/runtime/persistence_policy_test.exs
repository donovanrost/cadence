defmodule Cadence.Runtime.PersistencePolicyTest do
  use ExUnit.Case, async: true

  alias Cadence.Runtime.Persistence
  alias Cadence.Telemetry.{CurrentValueStore, Storage}

  test "one captured event bus governs runtime and nested telemetry publications" do
    current_value_store =
      CurrentValueStore.policy(module: Cadence.Telemetry.CurrentValueStore.Postgres)

    storage =
      Storage.policy([], current_value_store_policy: current_value_store, event_bus: :bus_a)

    inherited = Persistence.policy(%{}, %{}, storage)

    assert inherited.event_bus == :bus_a
    assert inherited.telemetry_storage.event_bus == :bus_a

    overridden = Persistence.policy(%{}, %{}, storage, event_bus: :bus_b)

    assert overridden.event_bus == :bus_b
    assert overridden.telemetry_storage.event_bus == :bus_b
    assert storage.event_bus == :bus_a
  end
end
