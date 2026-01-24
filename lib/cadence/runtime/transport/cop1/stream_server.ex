defmodule Cadence.Runtime.Transport.COP1.StreamServer do
  @moduledoc """
  GenServer wrapper for a COP-1 FOP stream.
  """

  use GenServer

  alias Cadence.Runtime.Transport.COP1.Context
  alias Cadence.Runtime.Transport.COP1.Report
  alias Cadence.Runtime.Transport.COP1.Stream
  alias Cadence.Transport.TCStreamId

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec resync(TCStreamId.t()) :: :ok | {:error, :stream_not_found}
  def resync(%TCStreamId{} = tc_stream_id) do
    case lookup(tc_stream_id) do
      {:ok, pid} -> GenServer.call(pid, :resync)
      :error -> {:error, :stream_not_found}
    end
  end

  @spec send_frames(pid(), [map()], Context.t()) :: :ok | {:error, term()} | {:defer, term()}
  def send_frames(pid, frames, %Context{} = context) when is_pid(pid) do
    GenServer.call(pid, {:send_frames, frames, context})
  end

  @spec apply_report(pid(), Report.t()) :: :ok
  def apply_report(pid, %Report{} = report) when is_pid(pid) do
    GenServer.cast(pid, {:report, report})
  end

  @spec stats(pid()) :: map()
  def stats(pid) when is_pid(pid) do
    GenServer.call(pid, :stats)
  end

  @impl true
  def init(opts) do
    base_stream = Keyword.fetch!(opts, :base_stream)
    stream_id = Keyword.fetch!(opts, :stream_id)

    state = %{
      stream_id: stream_id,
      stream:
        base_stream
        |> Map.put(:stream_id, stream_id)
        |> Stream.new()
        |> Stream.on_restart()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_frames, frames, %Context{} = context}, _from, state) do
    case Stream.send_frames(state.stream, frames, context) do
      {:ok, next_stream} -> {:reply, :ok, %{state | stream: next_stream}}
      {:defer, reason, next_stream} -> {:reply, {:defer, reason}, %{state | stream: next_stream}}
      {:error, reason, next_stream} -> {:reply, {:error, reason}, %{state | stream: next_stream}}
    end
  end

  def handle_call(:stats, _from, state) do
    {:reply, %{stream_id: state.stream_id, stats: Stream.stats(state.stream)}, state}
  end

  def handle_call(:resync, _from, state) do
    next_stream = Stream.resync_state(state.stream, :manual)
    {:reply, :ok, %{state | stream: next_stream}}
  end

  @impl true
  def handle_cast({:report, %Report{} = report}, state) do
    {next_stream, _result} =
      state.stream
      |> Stream.apply_report(report)
      |> Stream.maybe_send_pending()

    {:noreply, %{state | stream: next_stream}}
  end

  @impl true
  def handle_info({:fop_timeout, seq}, state) do
    next_stream = Stream.handle_timeout(state.stream, seq)
    {:noreply, %{state | stream: next_stream}}
  end

  defp lookup(%TCStreamId{} = tc_stream_id) do
    case Registry.lookup(Cadence.MissionRegistry, stream_key(tc_stream_id)) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  def via_tuple(mission_id, %TCStreamId{} = stream_id) do
    {:via, Registry, {Cadence.MissionRegistry, stream_key({mission_id, stream_id})}}
  end

  defp stream_key({mission_id, %TCStreamId{} = stream_id}) do
    {:cop1_stream, mission_id, TCStreamId.to_key(stream_id)}
  end

  defp stream_key(%TCStreamId{} = stream_id) do
    {:cop1_stream, stream_id.mission_id, TCStreamId.to_key(stream_id)}
  end
end
