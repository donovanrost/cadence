defmodule Cadence.Management.BootIsolationTest do
  use ExUnit.Case, async: false

  test "starts the management plane without control or data services" do
    assert_unstarted(Cadence.Control.Supervisor)
    assert_unstarted(Cadence.Runtime.Supervisor)
    assert_unstarted(Cadence.Projections.Supervisor)
    assert_unstarted(Cadence.Repo)

    supervisor = start_supervised!(Cadence.Management.Supervisor)

    assert Process.whereis(Cadence.Management.Supervisor) == supervisor
    # Only in-memory tables (the password-check throttle, Policy's confirmed mission pairs): no
    # Repo, control or data services.
    children = supervisor |> Supervisor.which_children() |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    assert children ==
             Enum.sort([Cadence.Accounts.AttemptLimit, Cadence.Auth.MissionOrganizationCache])

    assert_unstarted(Cadence.Control.Supervisor)
    assert_unstarted(Cadence.Runtime.Supervisor)
  end

  defp assert_unstarted(name), do: assert(Process.whereis(name) == nil)
end
