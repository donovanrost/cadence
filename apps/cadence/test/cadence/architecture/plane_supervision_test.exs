defmodule Cadence.Architecture.PlaneSupervisionTest do
  use Cadence.UnitCase, async: false

  @plane_supervisors [
    Cadence.Platform.Supervisor,
    Cadence.Management.Supervisor,
    Cadence.Runtime.Supervisor,
    Cadence.Control.Supervisor,
    Cadence.Projections.Supervisor
  ]

  setup do
    on_exit(fn ->
      Enum.each(@plane_supervisors, &ensure_root_child_started!/1)
    end)

    :ok
  end

  test "root supervision exposes the ADR-015 plane restart domains" do
    child_ids =
      Cadence.Supervisor
      |> Supervisor.which_children()
      |> Enum.map(fn {id, _pid, _type, _modules} -> id end)

    assert Enum.all?(@plane_supervisors, &(&1 in child_ids))
  end

  test "control and data supervisors restart independently" do
    runtime_pid = Process.whereis(Cadence.Runtime.Supervisor)
    control_pid = Process.whereis(Cadence.Control.Supervisor)
    platform_pid = Process.whereis(Cadence.Platform.Supervisor)
    projections_pid = Process.whereis(Cadence.Projections.Supervisor)

    assert is_pid(runtime_pid)
    assert is_pid(control_pid)

    assert :ok = Supervisor.terminate_child(Cadence.Supervisor, Cadence.Control.Supervisor)
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Runtime.Supervisor) == runtime_pid
    assert Process.whereis(Cadence.Platform.Supervisor) == platform_pid
    assert Process.whereis(Cadence.Projections.Supervisor) == projections_pid

    restarted_control_pid = restart_root_child!(Cadence.Control.Supervisor)
    assert restarted_control_pid != control_pid

    assert :ok = Supervisor.terminate_child(Cadence.Supervisor, Cadence.Runtime.Supervisor)
    assert Process.whereis(Cadence.Runtime.Supervisor) == nil
    assert Process.whereis(Cadence.Control.Supervisor) == restarted_control_pid
    assert Process.whereis(Cadence.Platform.Supervisor) == platform_pid
    assert Process.whereis(Cadence.Projections.Supervisor) == projections_pid

    restarted_runtime_pid = restart_root_child!(Cadence.Runtime.Supervisor)
    assert restarted_runtime_pid != runtime_pid
  end

  defp ensure_root_child_started!(child_id) do
    if is_nil(Process.whereis(child_id)) do
      restart_root_child!(child_id)
    end

    :ok
  end

  defp restart_root_child!(child_id) do
    case Supervisor.restart_child(Cadence.Supervisor, child_id) do
      {:ok, pid} -> pid
      {:ok, pid, _info} -> pid
      {:error, :running} -> Process.whereis(child_id)
    end
  end
end
