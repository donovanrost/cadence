defmodule Cadence.OTPClusterSpike.Cluster do
  @moduledoc false
  @cookie :cadence_otp_spike_cookie

  def start do
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    peers = start_peers([1, 2, 3], paths)

    try do
      Enum.each(peers, &boot(&1, peers))
      await(fn -> connected?(peers) end)
      Enum.each(peers, &call(&1, :global, :sync))
      peers
    catch
      kind, reason ->
        stop(peers)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  def stop(peers) do
    Enum.each(peers, fn %{peer: peer} -> stop_peer(peer) end)
  end

  def call(%{peer: peer}, module, function, args \\ []),
    do: :peer.call(peer, module, function, args, 10_000)

  def isolate(peer, others) do
    Enum.each(others, fn other ->
      call(peer, :erlang, :set_cookie, [other.node, :cadence_spike_isolated])
      call(other, :erlang, :set_cookie, [peer.node, :cadence_spike_isolated])
      call(peer, :erlang, :disconnect_node, [other.node])
    end)

    await(fn -> call(peer, :erlang, :nodes) == [] end)
  end

  def heal(peers) do
    for peer <- peers, other <- peers, peer != other do
      call(peer, :erlang, :set_cookie, [other.node, @cookie])
    end

    await(fn -> connected?(peers) end)
    Enum.each(peers, &call(&1, :global, :sync))
  end

  def await(fun, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_until(fun, deadline)
  end

  defp await_until(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "cluster convergence timed out"

      true ->
        Process.sleep(20)
        await_until(fun, deadline)
    end
  end

  defp connected?(peers),
    do: Enum.all?(peers, &(length(call(&1, :erlang, :nodes)) == length(peers) - 1))

  defp start_peers([], _paths), do: []

  defp start_peers([index | rest], paths) do
    {:ok, peer, node} =
      :peer.start_link(%{
        name: ~c"cadence_spike_#{System.pid()}_#{index}",
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(@cookie)] ++ paths,
        wait_boot: 15_000
      })

    Process.unlink(peer)

    try do
      [%{peer: peer, node: node} | start_peers(rest, paths)]
    catch
      kind, reason ->
        stop_peer(peer)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp stop_peer(peer) do
    if Process.alive?(peer), do: :peer.stop(peer)
  catch
    :exit, _reason -> :ok
  end

  defp boot(peer, peers) do
    {:ok, _} = call(peer, :application, :ensure_all_started, [:elixir])

    for file <- ["owner.ex", "node_agent.ex", "membership.ex", "pools.ex", "node.ex"] do
      call(peer, Code, :require_file, [Path.join(__DIR__, file)])
    end

    call(peer, Logger, :configure, [[level: :emergency]])
    {:ok, _} = call(peer, Cadence.OTPClusterSpike.Node, :boot, [Enum.map(peers, & &1.node)])
  end
end
