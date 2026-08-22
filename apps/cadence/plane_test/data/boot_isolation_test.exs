defmodule Cadence.Runtime.BootIsolationTest do
  use ExUnit.Case, async: false

  test "starts the data plane without management or control services" do
    assert_unstarted(Cadence.Management.Supervisor)
    assert_unstarted(Cadence.Control.Supervisor)
    assert_unstarted(Cadence.Projections.Supervisor)
    assert_unstarted(Cadence.Repo)

    supervisor = start_supervised!(Cadence.Runtime.Supervisor)

    assert Process.whereis(Cadence.Runtime.Supervisor) == supervisor
    assert is_pid(Process.whereis(Cadence.Runtime.CapabilityRegistry))
    assert is_pid(Process.whereis(Cadence.Runtime.Registry))
    assert is_pid(Process.whereis(Cadence.Runtime.MissionSupervisor))
    assert_unstarted(Cadence.Management.Supervisor)
    assert_unstarted(Cadence.Control.Supervisor)
    assert_unstarted(Cadence.Repo)
  end

  defp assert_unstarted(name), do: assert(Process.whereis(name) == nil)
end
