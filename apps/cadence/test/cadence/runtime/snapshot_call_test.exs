defmodule Cadence.Runtime.SnapshotCallTest do
  use ExUnit.Case, async: true

  alias Cadence.Runtime.SnapshotCall

  test "timeouts shrink inward: component < transport < provider < path < contact" do
    levels = [:component, :transport, :provider, :path, :contact]
    timeouts = Enum.map(levels, &SnapshotCall.timeout/1)
    assert timeouts == Enum.sort(timeouts)
    assert Enum.uniq(timeouts) == timeouts
    assert SnapshotCall.timeout(:contact) <= 5_000
  end

  test "a busy server is :snapshot_timeout, and the caller lives" do
    busy = spawn(fn -> receive(do: (:never -> :ok)) end)

    assert {:error, :snapshot_timeout} = SnapshotCall.call(busy, :snapshot, :component)
    assert Process.alive?(self())
  end

  test "a server that's gone is :not_running" do
    gone = spawn(fn -> :ok end)
    ref = Process.monitor(gone)
    assert_receive {:DOWN, ^ref, :process, ^gone, _reason}

    assert {:error, :not_running} = SnapshotCall.call(gone, :snapshot, :component)
  end

  test "a server that crashes on the call is {:snapshot_failed, reason}" do
    crashing =
      spawn(fn ->
        receive do
          {:"$gen_call", _from, :snapshot} -> exit(:boom)
        end
      end)

    assert {:error, {:snapshot_failed, _reason}} =
             SnapshotCall.call(crashing, :snapshot, :component)
  end

  test "a reply passes through unchanged" do
    {:ok, agent} = Agent.start_link(fn -> :state end)
    assert :state = SnapshotCall.call(agent, {:get, & &1}, :component)
  end
end
