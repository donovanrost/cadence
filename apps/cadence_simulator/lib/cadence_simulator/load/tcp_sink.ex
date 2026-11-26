defmodule CadenceSimulator.Load.TcpSink do
  @moduledoc false

  def start_link(site, sites, craft, frame_size, counters) do
    listener =
      case :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, backlog: 1024]) do
        {:ok, listener} -> listener
        {:error, reason} -> raise "could not open site #{site} TCP listener: #{inspect(reason)}"
      end

    {:ok, port} = :inet.port(listener)
    acceptor = spawn_link(fn -> accept(listener, site, sites, craft, frame_size, counters) end)
    :ok = :gen_tcp.controlling_process(listener, acceptor)
    {acceptor, port}
  end

  defp accept(listener, site, sites, craft, frame_size, counters) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        receiver = spawn_link(fn -> receive_path(site, sites, craft, frame_size, counters) end)
        :ok = :gen_tcp.controlling_process(socket, receiver)
        send(receiver, {:socket, socket})
        accept(listener, site, sites, craft, frame_size, counters)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        raise "site #{site} TCP accept failed: #{inspect(reason)}"
    end
  end

  defp receive_path(site, sites, craft, frame_size, counters) do
    receive do
      {:socket, socket} ->
        case :gen_tcp.recv(socket, frame_size, 10_000) do
          {:ok, <<0::2, scid::10, _rest::bitstring>>}
          when scid >= 1 and scid <= craft and rem(scid - 1, sites) == site ->
            Process.set_label({:simulator_load_receiver, scid})
            count(counters, scid, 1, frame_size)
            drain(socket, scid, frame_size, counters, 0)

          {:ok, _frame} ->
            raise "unexpected TM spacecraft or version on site #{site}"

          {:error, :closed} ->
            :ok

          {:error, reason} ->
            raise "site #{site} could not receive first TM frame: #{inspect(reason)}"
        end
    end
  end

  defp drain(socket, scid, frame_size, counters, remainder) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        bytes = byte_size(data)
        buffered = bytes + remainder
        count(counters, scid, div(buffered, frame_size), bytes)
        drain(socket, scid, frame_size, counters, rem(buffered, frame_size))

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        raise "SCID #{scid} TCP receive failed: #{inspect(reason)}"
    end
  end

  defp count(counters, scid, frames, bytes) do
    :counters.add(counters, scid * 2 - 1, frames)
    :counters.add(counters, scid * 2, bytes)
  end
end
