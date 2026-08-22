defmodule Cadence.Control.BootIsolationTest do
  use ExUnit.Case, async: false

  test "starts the control plane without management or data services" do
    assert_unstarted(Cadence.Management.Supervisor)
    assert_unstarted(Cadence.Runtime.Supervisor)
    assert_unstarted(Cadence.Projections.Supervisor)
    assert_unstarted(Cadence.Repo)

    supervisor = start_supervised!(Cadence.Control.Supervisor)

    assert Process.whereis(Cadence.Control.Supervisor) == supervisor
    assert is_pid(Process.whereis(Cadence.Control.Registry))
    assert is_pid(Process.whereis(Cadence.Control.MissionSupervisor))
    assert_unstarted(Cadence.Management.Supervisor)
    assert_unstarted(Cadence.Runtime.Supervisor)
  end

  defp assert_unstarted(name), do: assert(Process.whereis(name) == nil)
end
