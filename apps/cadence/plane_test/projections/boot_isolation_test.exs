defmodule Cadence.Projections.BootIsolationTest do
  use ExUnit.Case, async: false

  test "starts projections without authoritative plane services" do
    assert_unstarted(Cadence.Management.Supervisor)
    assert_unstarted(Cadence.Control.Supervisor)
    assert_unstarted(Cadence.Runtime.Supervisor)
    assert_unstarted(Cadence.Repo)

    supervisor = start_supervised!(Cadence.Projections.Supervisor)

    assert Process.whereis(Cadence.Projections.Supervisor) == supervisor
    assert is_pid(Process.whereis(Cadence.Telemetry.RuntimeHealth))
    assert is_pid(Process.whereis(Cadence.Dashboards.RuntimeCache))
    assert_unstarted(Cadence.Management.Supervisor)
    assert_unstarted(Cadence.Control.Supervisor)
    assert_unstarted(Cadence.Runtime.Supervisor)
  end

  defp assert_unstarted(name), do: assert(Process.whereis(name) == nil)
end
