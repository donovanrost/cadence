defmodule Cadence.DerivedTelemetryContractTest do
  use ExUnit.Case, async: true

  alias Cadence.DerivedTelemetry

  test "data-plane evaluation requires an exact definition snapshot" do
    assert Process.whereis(Cadence.Management.Supervisor) == nil
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil

    assert {:error, :derived_definition_snapshot_required} =
             DerivedTelemetry.evaluate("mission-data-plane")

    assert {:error, :derived_definition_snapshot_required} =
             DerivedTelemetry.start_evaluate("mission-data-plane")
  end
end
