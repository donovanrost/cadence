defmodule CadenceSimulator.DrainSink do
  @moduledoc """
  Minimal TCP drain sink for simulator throughput benchmarking.

  It accepts TCP connections, reads and discards all bytes, and exposes
  aggregate counters so local tooling can compare simulator-side transmit
  throughput against a dumb receiver with no Cadence processing in the loop.
  """

  use GenServer

  @default_socket_buffer 4_194_304

  @bytes_received_idx 1
  @chunks_received_idx 2
  @accepted_connections_idx 3
  @open_connections_idx 4
  @closed_connections_idx 5

  defstruct [:host, :port, :listen_socket, :acceptor_pid, :counters]

  @type stats :: %{
          output: String.t(),
          bytes_received: non_neg_integer(),
          chunks_received: non_neg_integer(),
          accepted_connections: non_neg_integer(),
          open_connections: non_neg_integer(),
          closed_connections: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec stats(GenServer.server()) :: stats()
  def stats(server), do: GenServer.call(server, :stats)

  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @impl true
  def init(opts) do
    host = Keyword.get(opts, :host, "127.0.0.1")
    port = Keyword.fetch!(opts, :port)
    ip = resolve_ip!(host)

    listen_opts = [
      :binary,
      packet: :raw,
      active: false,
      reuseaddr: true,
      backlog: 1024,
      ip: ip,
      recbuf: @default_socket_buffer,
      sndbuf: @default_socket_buffer,
      buffer: @default_socket_buffer
    ]

    {:ok, listen_socket} = :gen_tcp.listen(port, listen_opts)
    counters = :counters.new(5, [:write_concurrency])

    acceptor_pid =
      spawn(fn ->
        accept_loop(listen_socket, counters)
      end)

    {:ok,
     %__MODULE__{
       host: host,
       port: port,
       listen_socket: listen_socket,
       acceptor_pid: acceptor_pid,
       counters: counters
     }}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       output: "tcp:#{state.host}:#{state.port}",
       bytes_received: :counters.get(state.counters, @bytes_received_idx),
       chunks_received: :counters.get(state.counters, @chunks_received_idx),
       accepted_connections: :counters.get(state.counters, @accepted_connections_idx),
       open_connections: :counters.get(state.counters, @open_connections_idx),
       closed_connections: :counters.get(state.counters, @closed_connections_idx)
     }, state}
  end

  @impl true
  def terminate(_reason, state) do
    if is_port(state.listen_socket) do
      :gen_tcp.close(state.listen_socket)
    end

    :ok
  end

  defp accept_loop(listen_socket, counters) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        :counters.add(counters, @accepted_connections_idx, 1)
        :counters.add(counters, @open_connections_idx, 1)

        :ok =
          :inet.setopts(socket,
            active: false,
            recbuf: @default_socket_buffer,
            buffer: @default_socket_buffer
          )

        receive_loop(socket, counters)
        accept_loop(listen_socket, counters)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp receive_loop(socket, counters) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        :counters.add(counters, @bytes_received_idx, byte_size(data))
        :counters.add(counters, @chunks_received_idx, 1)
        receive_loop(socket, counters)

      {:error, _reason} ->
        :counters.sub(counters, @open_connections_idx, 1)
        :counters.add(counters, @closed_connections_idx, 1)
        :gen_tcp.close(socket)
        :ok
    end
  end

  defp resolve_ip!(host) when is_binary(host) do
    host_charlist = String.to_charlist(host)

    case :inet.parse_address(host_charlist) do
      {:ok, ip} ->
        ip

      {:error, _reason} ->
        case :inet.getaddr(host_charlist, :inet) do
          {:ok, ip} ->
            ip

          {:error, reason} ->
            raise ArgumentError, "invalid TCP drain host #{inspect(host)}: #{inspect(reason)}"
        end
    end
  end
end
