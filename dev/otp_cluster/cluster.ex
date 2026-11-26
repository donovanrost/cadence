defmodule Cadence.OTPClusterSpike.Cluster do
  @moduledoc false
  @cookie :cadence_otp_spike_cookie
  @peer_count 3

  def start do
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
    epmd_port = start_epmd()

    try do
      peers = start_peers(Enum.to_list(1..@peer_count), paths, epmd_port)

      try do
        Enum.each(peers, &boot(&1, peers))
        await(fn -> connected?(peers) end)
        Enum.each(peers, &call(&1, :global, :sync))
        peers
      catch
        kind, reason ->
          Enum.each(peers, fn %{peer: peer} -> stop_peer(peer) end)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    catch
      kind, reason ->
        stop_epmd(epmd_port)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  def stop(peers) do
    Enum.each(peers, fn %{peer: peer} -> stop_peer(peer) end)

    case {length(peers), peers} do
      {@peer_count, [%{epmd_port: port} | _]} -> stop_epmd(port)
      _ -> :ok
    end
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

  defp start_peers([], _paths, _epmd_port), do: []

  defp start_peers([index | rest], paths, epmd_port) do
    port = Integer.to_string(epmd_port)

    {:ok, peer, node} =
      :peer.start_link(%{
        name: ~c"cadence_spike_#{System.pid()}_#{index}",
        connection: :standard_io,
        env: [
          {~c"ERL_EPMD_ADDRESS", ~c"127.0.0.1"},
          {~c"ERL_EPMD_PORT", String.to_charlist(port)},
          {~c"ERL_AFLAGS", ~c"-start_epmd false -kernel inet_dist_use_interface {127,0,0,1}"}
        ],
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(@cookie)] ++ paths,
        wait_boot: 15_000
      })

    Process.unlink(peer)

    try do
      [%{peer: peer, node: node, epmd_port: epmd_port} | start_peers(rest, paths, epmd_port)]
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

  defp start_epmd do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, active: false)
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)

    case System.cmd(
           "epmd",
           ["-daemon", "-port", Integer.to_string(port), "-address", "127.0.0.1"],
           env: epmd_env(port),
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, status} -> raise "private epmd exited #{status}: #{String.trim(output)}"
    end

    try do
      await(fn -> epmd_names(port) != :unavailable end)
      port
    catch
      kind, reason ->
        stop_epmd(port)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp stop_epmd(port) do
    await(fn -> epmd_names(port) in [[], :unavailable] end)

    if epmd_names(port) != :unavailable do
      {_output, 0} =
        System.cmd("epmd", ["-port", Integer.to_string(port), "-kill"],
          env: epmd_env(port),
          stderr_to_stdout: true
        )

      await(fn -> epmd_names(port) == :unavailable end)
    end

    :ok
  end

  defp epmd_names(port) do
    case System.cmd("epmd", ["-port", Integer.to_string(port), "-names"],
           env: epmd_env(port),
           stderr_to_stdout: true
         ) do
      {output, 0} -> Regex.scan(~r/name \S+ at port \d+/, output)
      _ -> :unavailable
    end
  end

  defp epmd_env(port),
    do: [{"ERL_EPMD_ADDRESS", "127.0.0.1"}, {"ERL_EPMD_PORT", Integer.to_string(port)}]

  defp boot(peer, peers) do
    {:ok, _} = call(peer, :application, :ensure_all_started, [:elixir])
    # The runtime supervisor's children attach telemetry handlers at init (the ingress
    # backpressure monitor), as in production, where :telemetry always runs.
    {:ok, _} = call(peer, :application, :ensure_all_started, [:telemetry])

    for file <- ["owner.ex", "node_agent.ex", "membership.ex", "pools.ex", "node.ex"] do
      call(peer, Code, :require_file, [Path.join(__DIR__, file)])
    end

    call(peer, Logger, :configure, [[level: :emergency]])
    {:ok, _} = call(peer, Cadence.OTPClusterSpike.Node, :boot, [Enum.map(peers, & &1.node)])
  end
end
