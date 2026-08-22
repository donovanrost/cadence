defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticFormatterTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticFormatter

  test "value formats fallback and primitive diagnostics" do
    assert RuntimeDiagnosticFormatter.value(nil) == "-"
    assert RuntimeDiagnosticFormatter.value("") == "-"
    assert RuntimeDiagnosticFormatter.value(true) == "true"
    assert RuntimeDiagnosticFormatter.value(12) == "12"
    assert RuntimeDiagnosticFormatter.value(1.5) == "1.5"
    assert RuntimeDiagnosticFormatter.value(:live_tick) == "live_tick"
    assert RuntimeDiagnosticFormatter.value("accepted") == "accepted"
    assert RuntimeDiagnosticFormatter.value(%{reason: :test}) == "%{reason: :test}"
  end

  test "count_summary sorts by diagnostic key and ignores nil or zero counts" do
    assert RuntimeDiagnosticFormatter.count_summary(%{
             stale: 2,
             refresh_source_result: 1,
             ignored: 0,
             empty: nil
           }) == "refresh_source_result:1 stale:2"

    assert RuntimeDiagnosticFormatter.count_summary(%{}) == nil
    assert RuntimeDiagnosticFormatter.count_summary(nil) == nil
  end

  test "list compacts blank diagnostic values" do
    assert RuntimeDiagnosticFormatter.list([nil, "", "-", :telemetry, "req-1"]) ==
             "telemetry req-1"

    assert RuntimeDiagnosticFormatter.list([]) == "-"
    assert RuntimeDiagnosticFormatter.list(:source_health_event) == "source_health_event"
  end

  test "row formats label and diagnostic value" do
    assert RuntimeDiagnosticFormatter.row("Refresh allowed", 2) == %{
             label: "Refresh allowed",
             value: "2"
           }
  end
end
