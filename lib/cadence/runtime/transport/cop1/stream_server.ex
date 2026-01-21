defmodule Cadence.Runtime.Transport.COP1.StreamServer do
  @moduledoc """
  GenServer wrapper for a COP-1 FOP stream.
  """

  use GenServer
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Runtime.Transport.COP1.Context
  alias Cadence.Runtime.Transport.COP1.Stream

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
      id: {:cop1_stream, mission_id, interface_id, stream_id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  def via_tuple(mission_id, interface_id, stream_id) do
    {:via, Registry,
     {Cadence.MissionRegistry, {:cop1_stream, mission_id, interface_id, stream_id}}}
  end

  @spec send_frames(pid(), [map()], Context.t()) :: :ok | {:error, term()}
  def send_frames(pid, frames, %Context{} = context) when is_list(frames) do
    GenServer.call(pid, {:send_frames, frames, context})
  end

  @spec ingest_clcw(pid(), CLCW.t()) :: :ok
  def ingest_clcw(pid, %CLCW{} = clcw) do
    GenServer.cast(pid, {:clcw, clcw})
  end

  @spec apply_clcw(pid(), CLCW.t()) :: :ok
  def apply_clcw(pid, %CLCW{} = clcw) do
    GenServer.call(pid, {:apply_clcw, clcw})
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
      |> Stream.new()

    {:ok, %{stream_id: stream_id, stream: stream}}
  end

  @impl true
  def handle_call({:send_frames, frames, context}, _from, state) do
    case Stream.send_frames(state.stream, frames, context) do
      {:ok, next_stream} ->
        {:reply, :ok, %{state | stream: next_stream}}

      {:error, reason, next_stream} ->
        {:reply, {:error, reason}, %{state | stream: next_stream}}
    end
  end

  def handle_call({:apply_clcw, %CLCW{} = clcw}, _from, state) do
    next_stream =
      state.stream
      |> Stream.apply_clcw(clcw)
      |> Stream.maybe_send_pending()
      |> elem(0)

    {:reply, :ok, %{state | stream: next_stream}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, %{stream_id: state.stream_id, stats: Stream.stats(state.stream)}, state}
  end

  @impl true
  def handle_cast({:clcw, %CLCW{} = clcw}, state) do
    next_stream =
      state.stream
      |> Stream.apply_clcw(clcw)
      |> Stream.maybe_send_pending()
      |> elem(0)

    {:noreply, %{state | stream: next_stream}}
  end

  @impl true
  def handle_info({:fop_timeout, seq}, state) do
    next_stream = Stream.handle_timeout(state.stream, seq)
    {:noreply, %{state | stream: next_stream}}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
