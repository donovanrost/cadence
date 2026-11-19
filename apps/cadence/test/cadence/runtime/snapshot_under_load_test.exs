defmodule Cadence.Runtime.SnapshotUnderLoadTest do
  @moduledoc """
  #334: a read-only path snapshot under load must never terminate a live runtime. The TCP
  provider's `:snapshot` called its ingress executor's and projector's snapshots with the default
  5 s and no catch, so a busy projector (a persist under CI load) made the read time out INSIDE the
  provider's `handle_call`, which terminated the live provider runtime ('TCP provider ...
  terminating: {:timeout, {GenServer, :call, [..., :snapshot, 5000]}}'), and every caller above it
  timed out too. A busy projector is simulated with `:sys.suspend/1`: it handles nothing, so its
  `:snapshot` call can't be answered, exactly as when it's stuck in a long write.
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.TCPContactFixture

  alias Cadence.Runtime.MissionRuntime

  test "a busy projector doesn't terminate the provider: the snapshot returns, naming the unavailable part" do
    c = start_tcp_contact!()

    provider =
      GenServer.whereis(
        MissionRuntime.provider_runtime_name(
          c.mission_id,
          c.realized_contact_id,
          c.path_id,
          c.provider_binding_id
        )
      )

    projector =
      GenServer.whereis(
        MissionRuntime.provider_persistence_projector_name(
          c.mission_id,
          c.realized_contact_id,
          c.path_id,
          c.provider_binding_id
        )
      )

    assert is_pid(provider) and is_pid(projector)
    monitor = Process.monitor(provider)
    :ok = :sys.suspend(projector)

    on_exit(fn -> if Process.alive?(projector), do: :sys.resume(projector) end)

    {micros, result} =
      :timer.tc(fn ->
        Cadence.path_runtime_snapshot(
          c.organization_id,
          c.mission_id,
          c.realized_contact_id,
          c.path_id
        )
      end)

    assert {:ok, %{provider_runtimes: [snapshot]}} = result
    assert %{error: _unavailable} = snapshot.ingress_persistence_projector
    assert micros < 3_000_000, "the read is bounded well under the 5 s outer call"

    refute_received {:DOWN, ^monitor, :process, ^provider, _reason}
    assert Process.alive?(provider)

    :ok = :sys.resume(projector)
  end

  # ca-security's review: the contact-level read also called DownlinkCombiner.snapshot raw.
  test "a busy downlink combiner doesn't terminate the contact coordinator" do
    c = start_tcp_contact!()

    combiner =
      GenServer.whereis(
        MissionRuntime.downlink_combiner_name(c.mission_id, c.realized_contact_id)
      )

    coordinator =
      GenServer.whereis(
        MissionRuntime.realized_contact_coordinator_name(c.mission_id, c.realized_contact_id)
      )

    assert is_pid(combiner) and is_pid(coordinator)
    monitor = Process.monitor(coordinator)
    :ok = :sys.suspend(combiner)
    on_exit(fn -> if Process.alive?(combiner), do: :sys.resume(combiner) end)

    {micros, result} =
      :timer.tc(fn -> Cadence.realized_contact_snapshot(c.mission_id, c.realized_contact_id) end)

    assert {:error, :snapshot_timeout} = result
    assert micros < 5_000_000

    refute_received {:DOWN, ^monitor, :process, ^coordinator, _reason}
    assert Process.alive?(coordinator)

    :ok = :sys.resume(combiner)
  end
end
