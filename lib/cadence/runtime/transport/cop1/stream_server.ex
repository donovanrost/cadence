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
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.fetch!(opts, :interface_id)
    stream_id = Keyword.fetch!(opts, :stream_id)
    name = Keyword.get(opts, :name, via_tuple(mission_id, interface_id, stream_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.fetch!(opts, :interface_id)
    stream_id = Keyword.fetch!(opts, :stream_id)

    %{
      id: {:cop1_stream, mission_id, interface_id, stream_key_value(stream_id)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  def via_tuple(mission_id, interface_id, stream_id) do
    {:via, Registry,
     {Cadence.MissionRegistry,
      {:cop1_stream, mission_id, interface_id, stream_key_value(stream_id)}}}
  end

  @spec send_frames(pid(), [map()], Context.t()) :: :ok | {:error, term()}
  def send_frames(pid, frames, %Context{} = context) when is_list(frames) do
    GenServer.call(pid, {:send_frames, frames, context})
  end

  @spec resync(TCStreamId.t()) :: :ok | {:error, :stream_not_found}
  def resync(%TCStreamId{} = tc_stream_id) do
    case Registry.lookup(
           Cadence.MissionRegistry,
           {:cop1_stream, tc_stream_id.mission_id, tc_stream_id.interface_id,
            stream_key_value(tc_stream_id)}
         ) do
      [{pid, _}] -> GenServer.call(pid, :resync)
      [] -> {:error, :stream_not_found}
    end
  end

  @spec apply_report(pid(), Report.t()) :: :ok
  def apply_report(pid, %Report{} = report) do
    GenServer.call(pid, {:apply_report, report})
  end

  @spec stats(pid()) :: map()
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  @impl true
  def init(opts) do
    stream_id = Keyword.fetch!(opts, :stream_id)
    base = Keyword.fetch!(opts, :base_stream)
    stream_vcid = Keyword.get(opts, :vcid)

    stream =
      base
      |> Map.put(:default_vcid, stream_vcid || Map.get(base, :default_vcid))
      |> Map.put(:stream_id, stream_id)
      |> Map.put(:initial_seq, Map.get(base, :initial_seq, 0))
      |> Map.put(:held, true)
      |> Stream.new()
      |> Stream.on_restart()

    {:ok, %{stream_id: stream_id, stream: stream}}
  end

  @impl true
  def handle_call({:send_frames, frames, context}, _from, state) do
    case Stream.send_frames(state.stream, frames, context) do
      {:ok, next_stream} ->
        {:reply, :ok, %{state | stream: next_stream}}

      {:defer, reason, next_stream} ->
        {:reply, {:defer, reason}, %{state | stream: next_stream}}

      {:error, reason, next_stream} ->
        {:reply, {:error, reason}, %{state | stream: next_stream}}
    end
  end

  def handle_call({:apply_report, %Report{} = report}, _from, state) do
    next_stream =
      state.stream
      |> Stream.apply_report(report)
      |> Stream.maybe_send_pending()
      |> elem(0)

    {:reply, :ok, %{state | stream: next_stream}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, %{stream_id: state.stream_id, stats: Stream.stats(state.stream)}, state}
  end

  def handle_call(:resync, _from, state) do
    next_stream = Stream.resync_state(state.stream, :manual)
    {:reply, :ok, %{state | stream: next_stream}}
  end

  defp stream_key_value(%TCStreamId{} = stream_id), do: TCStreamId.to_key(stream_id)
  defp stream_key_value(stream_id), do: stream_id

  @impl true
  def handle_info({:fop_timeout, seq}, state) do
    next_stream = Stream.handle_timeout(state.stream, seq)
    {:noreply, %{state | stream: next_stream}}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
