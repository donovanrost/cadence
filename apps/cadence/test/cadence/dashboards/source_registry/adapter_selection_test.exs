defmodule Cadence.Dashboards.SourceRegistry.AdapterSelectionTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.ResolvedSourceBinding

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Dashboards.SourceRegistry.AdapterSelection
  alias Cadence.Dashboards.Sources.{Events, Limits, OperationalObservables, Telemetry}

  test "exposes and selects every default logical-source adapter" do
    assert AdapterSelection.logical_sources() == [
             :events,
             :limits,
             :operational_observables,
             :telemetry
           ]

    assert {:ok, Telemetry} = AdapterSelection.for_logical_source(:telemetry, [])
    assert {:ok, Limits} = AdapterSelection.for_logical_source(:limits, [])
    assert {:ok, Events} = AdapterSelection.for_logical_source(:events, [])

    assert {:ok, OperationalObservables} =
             AdapterSelection.for_logical_source(:operational_observables, [])

    assert :error = AdapterSelection.for_logical_source(:unsupported, [])
  end

  test "explicit logical-source overrides take precedence over defaults" do
    assert {:ok, Cadence.Support.DashboardSourceTestAdapter} =
             AdapterSelection.for_logical_source(
               :telemetry,
               adapters: %{telemetry: Cadence.Support.DashboardSourceTestAdapter}
             )
  end

  test "binding selection prefers overrides and otherwise uses the configured adapter" do
    resolved_binding = resolved_binding(Telemetry)

    assert {:ok, Telemetry} = AdapterSelection.for_binding(resolved_binding, [])

    assert {:ok, Cadence.Support.DashboardSourceTestAdapter} =
             AdapterSelection.for_binding(
               resolved_binding,
               adapters: %{telemetry: Cadence.Support.DashboardSourceTestAdapter}
             )

    assert :error = AdapterSelection.for_binding(resolved_binding(nil), [])
  end

  defp resolved_binding(adapter) do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "flight-telemetry",
        logical_source: :telemetry,
        data_source_id: "source-1"
      },
      data_source: %DataSource{
        data_source_id: "source-1",
        adapter: adapter
      },
      realm: :flight,
      dataset: "flight"
    }
  end
end
