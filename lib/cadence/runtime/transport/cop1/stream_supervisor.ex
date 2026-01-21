defmodule Cadence.Runtime.Transport.COP1.StreamSupervisor do
  @moduledoc """
  Dynamic supervisor for per-stream COP-1 processes.
  """

  alias Cadence.Runtime.Transport.COP1.StreamServer

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.fetch!(opts, :interface_id)
    name = via_tuple(mission_id, interface_id)
    DynamicSupervisor.start_link(strategy: :one_for_one, name: name)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.fetch!(opts, :interface_id)

    %{
      id: {:cop1_stream_supervisor, mission_id, interface_id},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @spec ensure_stream(String.t(), String.t(), term(), map(), keyword()) ::
          {:ok, pid(), :existing | :started} | {:error, term()}
  def ensure_stream(mission_id, interface_id, stream_id, base_stream, opts \\ []) do
    case lookup_stream(mission_id, interface_id, stream_id) do
      {:ok, pid} -> {:ok, pid, :existing}
      :error -> start_stream(mission_id, interface_id, stream_id, base_stream, opts)
    end
  end

  @spec lookup_stream(String.t(), String.t(), term()) :: {:ok, pid()} | :error
  def lookup_stream(mission_id, interface_id, stream_id) do
    case Registry.lookup(Cadence.MissionRegistry, stream_key(mission_id, interface_id, stream_id)) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @spec start_stream(String.t(), String.t(), term(), map(), keyword()) ::
          {:ok, pid(), :existing | :started} | {:error, term()}
  def start_stream(mission_id, interface_id, stream_id, base_stream, opts \\ []) do
    child_opts =
      [
        mission_id: mission_id,
        interface_id: interface_id,
        stream_id: stream_id,
        name: StreamServer.via_tuple(mission_id, interface_id, stream_id),
        base_stream: base_stream,
        vcid: Keyword.get(opts, :vcid)
      ]
      |> Keyword.merge(opts)

    result =
      case supervisor_pid(mission_id, interface_id) do
        {:ok, supervisor} ->
          DynamicSupervisor.start_child(supervisor, {StreamServer, child_opts})

        :error ->
          {:error, :cop1_stream_supervisor_not_running}
      end

    case result do
      {:ok, pid} ->
        {:ok, pid, :started}

      {:error, {:already_started, pid}} ->
        {:ok, pid, :existing}

      {:error, :already_present} ->
        case lookup_stream(mission_id, interface_id, stream_id) do
          {:ok, pid} -> {:ok, pid, :existing}
          :error -> {:error, :cop1_stream_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec broadcast_clcw(String.t(), String.t(), term()) :: :ok
  def broadcast_clcw(mission_id, interface_id, clcw) do
    stream_pids(mission_id, interface_id)
    |> Enum.each(fn pid -> StreamServer.ingest_clcw(pid, clcw) end)

    :ok
  end

  @spec broadcast_timeout(String.t(), String.t(), non_neg_integer()) :: :ok
  def broadcast_timeout(mission_id, interface_id, seq) do
    stream_pids(mission_id, interface_id)
    |> Enum.each(fn pid -> send(pid, {:fop_timeout, seq}) end)

    :ok
  end

  @spec stream_stats(String.t(), String.t()) :: list()
  def stream_stats(mission_id, interface_id) do
    stream_pids(mission_id, interface_id)
    |> Enum.map(fn pid -> StreamServer.stats(pid) end)
  end

  defp stream_pids(mission_id, interface_id) do
    case supervisor_pid(mission_id, interface_id) do
      {:ok, supervisor} ->
        DynamicSupervisor.which_children(supervisor)
        |> Enum.flat_map(fn
          {_id, pid, _type, _modules} when is_pid(pid) -> [pid]
          _ -> []
        end)

      :error ->
        []
    end
  end

  defp via_tuple(mission_id, interface_id) do
    {:via, Registry,
     {Cadence.MissionRegistry, {:cop1_stream_supervisor, mission_id, interface_id}}}
  end

  defp stream_key(mission_id, interface_id, stream_id) do
    {:cop1_stream, mission_id, interface_id, stream_id}
  end

  defp supervisor_pid(mission_id, interface_id) do
    case Registry.lookup(Cadence.MissionRegistry, supervisor_key(mission_id, interface_id)) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp supervisor_key(mission_id, interface_id) do
    {:cop1_stream_supervisor, mission_id, interface_id}
  end
end
