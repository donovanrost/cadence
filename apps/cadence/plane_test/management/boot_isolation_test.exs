defmodule Cadence.Management.BootIsolationTest do
  use ExUnit.Case, async: false

  test "starts the management plane without control or data services" do
    assert_unstarted(Cadence.Control.Supervisor)
    assert_unstarted(Cadence.Runtime.Supervisor)
    assert_unstarted(Cadence.Projections.Supervisor)
    assert_unstarted(Cadence.Repo)

    supervisor = start_supervised!(Cadence.Management.Supervisor)

    assert Process.whereis(Cadence.Management.Supervisor) == supervisor
    # Only the in-memory password-check throttle (Accounts.AttemptLimit): no Repo, control or
    # data services.
    assert [{Cadence.Accounts.AttemptLimit, pid, :worker, _modules}] =
             Supervisor.which_children(supervisor)

    assert is_pid(pid)
    assert_unstarted(Cadence.Control.Supervisor)
    assert_unstarted(Cadence.Runtime.Supervisor)
  end

  defp assert_unstarted(name), do: assert(Process.whereis(name) == nil)
end
