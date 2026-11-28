defmodule Cadence.Commanding.QueueLaneLockTest do
  @moduledoc """
  `QueueLaneLock.acquire_all/3` (#1041): every lane of a group in one statement, in key order.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Commanding.QueueLaneLock
  alias Cadence.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @lanes for i <- 1..20, do: "lane-#{i}"

  test "takes the locks of any number of lanes in one query" do
    ref = make_ref()
    me = self()
    handler = "queue-lane-lock-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, _meta, _cfg -> if self() == me, do: send(me, {:query, ref}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    Repo.transaction(fn ->
      :ok = QueueLaneLock.acquire_all("org-lock", "mission-lock", @lanes)
    end)

    # One statement for the 20 lanes (plus the transaction's own begin and commit).
    assert queries(ref, 0) <= 3
  end

  test "two transactions locking the same lanes in opposite orders don't deadlock" do
    test_pid = self()

    holder =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            :ok = QueueLaneLock.acquire_all("org-lock", "mission-lock", @lanes)
            send(test_pid, :held)
            receive do: (:commit -> :ok)
          end)
        end)
      end)

    assert_receive :held, 2_000

    waiter =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            :ok = QueueLaneLock.acquire_all("org-lock", "mission-lock", Enum.reverse(@lanes))
            send(test_pid, :acquired)
          end)
        end)
      end)

    # It waits for the first, and gets every lock once the first commits.
    refute_receive :acquired, 300
    send(holder.pid, :commit)
    assert_receive :acquired, 5_000
    assert {:ok, :ok} = Task.await(holder)
    assert {:ok, _} = Task.await(waiter)
  end

  test "the same lane twice, and no lanes, are fine" do
    Repo.transaction(fn ->
      assert :ok = QueueLaneLock.acquire_all("org-lock", "mission-lock", ["a", "a"])
      assert :ok = QueueLaneLock.acquire_all("org-lock", "mission-lock", [])
    end)
  end

  defp queries(ref, n) do
    receive do
      {:query, ^ref} -> queries(ref, n + 1)
    after
      0 -> n
    end
  end
end
