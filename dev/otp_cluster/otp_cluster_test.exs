defmodule Cadence.OTPClusterSpikeTest do
  use ExUnit.Case, async: false

  alias Cadence.OTPClusterSpike.{Cluster, NodeAgent, Owner}

  @moduletag timeout: 60_000

  setup do
    peers = Cluster.start()
    on_exit(fn -> Cluster.stop(peers) end)
    %{peers: peers, key: {:partition, "org-spike", "mission-spike", make_ref()}}
  end

  test "libcluster forms three nodes and routing distinguishes registration from readiness", %{
    peers: [a, b, c] = peers,
    key: key
  } do
    Cluster.await(fn ->
      Enum.all?(peers, fn peer ->
        length(
          Cluster.call(peer, :pg, :get_members, [Cadence.OTPClusterSpike.Groups, :execution])
        ) ==
          3
      end)
    end)

    assert {:ok, owner} = Cluster.call(b, NodeAgent, :start_owner, [:partition, key])
    assert {:error, :recovering} = Cluster.call(b, Owner, :route, [key])
    assert :ok = Cluster.call(b, GenServer, :call, [owner, :ready])

    Cluster.await(fn ->
      Enum.all?(peers, &(Cluster.call(&1, :global, :whereis_name, [key]) == owner))
    end)

    assert {:ok, node, ^owner} = Cluster.call(a, Owner, :route, [key])
    assert node == b.node
    assert {:ok, ^node, ^owner} = Cluster.call(c, Owner, :route, [key])
  end

  test "simultaneous connected starts register one owner", %{peers: peers, key: key} do
    results =
      peers
      |> Task.async_stream(&Cluster.call(&1, NodeAgent, :start_owner, [:partition, key, true]))
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, {:shutdown, :name_taken}}, &1)) == 2
  end

  test "controller restart preserves a separately supervised partition", %{
    peers: [a, b, _],
    key: key
  } do
    control_key = {:control, key}
    assert {:ok, owner} = Cluster.call(b, NodeAgent, :start_owner, [:partition, key, true])

    assert {:ok, controller} =
             Cluster.call(a, NodeAgent, :start_owner, [:control, control_key, true])

    Cluster.call(a, Process, :exit, [controller, :kill])

    Cluster.await(fn ->
      pid = Cluster.call(a, :global, :whereis_name, [control_key])
      is_pid(pid) and pid != controller
    end)

    assert Cluster.call(b, Process, :alive?, [owner])
    assert {:ok, _, ^owner} = Cluster.call(b, Owner, :route, [key])
  end

  test "split nodes can have two live owners and healing retires the loser without restart", %{
    peers: [a, b, c] = peers,
    key: key
  } do
    assert {:ok, first} = Cluster.call(a, NodeAgent, :start_owner, [:partition, key, true])
    Cluster.await(fn -> Cluster.call(b, :global, :whereis_name, [key]) == first end)
    Cluster.isolate(a, [b, c])
    Cluster.await(fn -> Cluster.call(b, :global, :whereis_name, [key]) == :undefined end)
    assert {:ok, second} = Cluster.call(b, NodeAgent, :start_owner, [:partition, key, true])
    assert Cluster.call(a, Process, :alive?, [first])
    assert Cluster.call(b, Process, :alive?, [second])
    assert {:ok, _, ^first} = Cluster.call(a, Owner, :route, [key])
    assert {:ok, _, ^second} = Cluster.call(b, Owner, :route, [key])

    Cluster.heal(peers)

    Cluster.await(fn ->
      names = Enum.map(peers, &Cluster.call(&1, :global, :whereis_name, [key]))

      alive = [
        Cluster.call(a, Process, :alive?, [first]),
        Cluster.call(b, Process, :alive?, [second])
      ]

      length(Enum.uniq(names)) == 1 and Enum.count(alive, & &1) == 1
    end)

    counts =
      Enum.map(
        peers,
        &Cluster.call(&1, DynamicSupervisor, :count_children, [Cadence.OTPClusterSpike.Partitions])
      )

    assert Enum.sum(Enum.map(counts, & &1.active)) == 1
  end

  test "pg restart re-advertises eligibility without restarting execution", %{
    peers: [a, _, _],
    key: key
  } do
    assert {:ok, owner} = Cluster.call(a, NodeAgent, :start_owner, [:partition, key, true])
    scope = Cadence.OTPClusterSpike.Groups
    old = Cluster.call(a, Process, :whereis, [scope])
    Cluster.call(a, Process, :exit, [old, :kill])

    Cluster.await(fn ->
      current = Cluster.call(a, Process, :whereis, [scope])

      is_pid(current) and current != old and
        length(Cluster.call(a, :pg, :get_members, [scope, :execution])) == 3
    end)

    assert Cluster.call(a, Process, :alive?, [owner])
    assert {:ok, _, ^owner} = Cluster.call(a, Owner, :route, [key])
  end

  test "node loss removes discovery and replacement starts under another local supervisor", %{
    peers: [a, b, c],
    key: key
  } do
    assert {:ok, owner} = Cluster.call(b, NodeAgent, :start_owner, [:partition, key, true])
    Cluster.await(fn -> Cluster.call(a, :global, :whereis_name, [key]) == owner end)
    :peer.stop(b.peer)

    Cluster.await(fn ->
      Enum.all?([a, c], fn peer ->
        Cluster.call(peer, :global, :whereis_name, [key]) == :undefined and
          length(Cluster.call(peer, :erlang, :nodes)) == 1
      end)
    end)

    assert {:ok, replacement} = Cluster.call(c, NodeAgent, :start_owner, [:partition, key])
    assert replacement != owner
    assert :ok = Cluster.call(c, GenServer, :call, [replacement, :ready])
    Cluster.await(fn -> Cluster.call(a, :global, :whereis_name, [key]) == replacement end)
    assert {:ok, node, ^replacement} = Cluster.call(a, Owner, :route, [key])
    assert node == c.node
  end
end
