defmodule Cadence.Applications.TelemetryDecomReviewTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.ConfigurationLock
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  @organization_id "org-decom-review"

  test "independent transactions wait on the same mission even before any configuration exists" do
    parent = self()
    mission = "empty-lock-#{System.unique_integer([:positive])}"

    first =
      independent(fn ->
        ConfigurationLock.run(@organization_id, mission, fn ->
          send(parent, {:locked, self()})

          receive do
            :release -> :ok
          after
            5_000 -> raise "lock release was not delivered"
          end
        end)
      end)

    assert_receive {:locked, owner}, 2_000

    second =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:waiting, pid})
        ConfigurationLock.run(@organization_id, mission, fn -> send(parent, :second_entered) end)
      end)

    assert_receive {:waiting, backend_pid}, 2_000
    assert wait_for_lock(backend_pid, 100)
    refute_received :second_entered

    other =
      independent(fn ->
        ConfigurationLock.run(@organization_id, mission <> "-other", fn ->
          :other_mission_entered
        end)
      end)

    assert Task.await(other) == :other_mission_entered
    send(owner, :release)
    assert Task.await(first) == :ok
    assert Task.await(second) == :second_entered
    assert_receive :second_entered
  end

  defp independent(operation) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        operation.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_for_lock(_pid, 0), do: false

  defp wait_for_lock(pid, attempts) do
    %{rows: [[waiting]]} =
      SQL.query!(
        Repo,
        "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = $1 AND locktype = 'advisory' AND NOT granted)",
        [pid]
      )

    if waiting do
      true
    else
      Process.sleep(10)
      wait_for_lock(pid, attempts - 1)
    end
  end
end
