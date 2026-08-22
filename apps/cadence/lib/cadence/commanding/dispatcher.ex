defmodule Cadence.Commanding.Dispatcher do
  @moduledoc false

  use GenServer

  alias Cadence.Commanding.{DispatchSupervisor, LaneDispatcher, ProcessNamespace}
  alias Cadence.Control.Commanding

  @default_safety_poll_interval_ms 60_000
  @event_prefix [:cadence, :commanding, :dispatcher]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    process_namespace = process_namespace(opts)

    case Keyword.get(opts, :name, process_namespace.dispatcher) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec reconcile_now(GenServer.server() | ProcessNamespace.t()) ::
          {:ok, map()} | {:error, term()}
  def reconcile_now(server \\ __MODULE__) do
    GenServer.call(dispatcher_server(server), :reconcile_now, :infinity)
  end

  @spec kick_lane(binary(), binary(), binary(), keyword()) :: :ok | {:error, term()}
  def kick_lane(organization_id, mission_id, queue_lane_key),
    do: kick_lane(organization_id, mission_id, queue_lane_key, [])

  def kick_lane(organization_id, mission_id, queue_lane_key, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_list(opts) do
    process_namespace =
      Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)

    kick_lane(process_namespace, organization_id, mission_id, queue_lane_key, opts)
  end

  @spec kick_lane(ProcessNamespace.t(), binary(), binary(), binary(), keyword()) ::
          :ok | {:error, term()}
  def kick_lane(
        %ProcessNamespace{} = process_namespace,
        organization_id,
        mission_id,
        queue_lane_key
      ),
      do: kick_lane(process_namespace, organization_id, mission_id, queue_lane_key, [])

  def kick_lane(
        %ProcessNamespace{} = process_namespace,
        organization_id,
        mission_id,
        queue_lane_key,
        opts
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_list(opts) do
    case drain_lane(process_namespace, organization_id, mission_id, queue_lane_key, opts) do
      {:ok, _summary} -> :ok
      {:error, :dispatcher_not_running} -> :ok
      {:error, :noproc} -> :ok
      {:error, %{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec drain_lane(binary(), binary(), binary(), keyword()) ::
          {:ok, LaneDispatcher.drain_summary()} | {:error, term()}
  def drain_lane(organization_id, mission_id, queue_lane_key),
    do: drain_lane(organization_id, mission_id, queue_lane_key, [])

  def drain_lane(organization_id, mission_id, queue_lane_key, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_list(opts) do
    process_namespace =
      Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)

    drain_lane(process_namespace, organization_id, mission_id, queue_lane_key, opts)
  end

  @spec drain_lane(ProcessNamespace.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, LaneDispatcher.drain_summary()} | {:error, term()}
  def drain_lane(
        %ProcessNamespace{} = process_namespace,
        organization_id,
        mission_id,
        queue_lane_key
      ),
      do: drain_lane(process_namespace, organization_id, mission_id, queue_lane_key, [])

  def drain_lane(
        %ProcessNamespace{} = process_namespace,
        organization_id,
        mission_id,
        queue_lane_key,
        opts
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_list(opts) do
    call_dispatcher(
      process_namespace,
      {:drain_lane, organization_id, mission_id, queue_lane_key, opts}
    )
  end

  defp drain_owned_lane(state, organization_id, mission_id, queue_lane_key, opts) do
    lane_opts =
      opts
      |> Keyword.delete(:process_namespace)
      |> Keyword.merge(state.lane_dispatcher_opts)
      |> Keyword.put(:safety_poll_interval_ms, state.lane_safety_poll_interval_ms)
      |> Keyword.put(:run_on_boot?, false)

    with :ok <-
           DispatchSupervisor.ensure_lane_dispatcher_started(
             state.process_namespace,
             organization_id,
             mission_id,
             queue_lane_key,
             lane_opts
           ),
         {:ok, lane_dispatcher} <-
           DispatchSupervisor.lane_dispatcher(
             state.process_namespace,
             organization_id,
             mission_id,
             queue_lane_key
           ) do
      LaneDispatcher.drain(lane_dispatcher)
    else
      :error -> {:error, :dispatcher_not_running}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def init(opts) do
    state = %{
      process_namespace: process_namespace(opts),
      requeue_release_pending_fun:
        Keyword.get(
          opts,
          :requeue_release_pending_fun,
          &Commanding.requeue_release_pending_queue_entries/0
        ),
      list_pending_queue_lanes_fun:
        Keyword.get(opts, :list_pending_queue_lanes_fun, &Commanding.list_pending_queue_lanes/0),
      lane_dispatcher_opts: lane_dispatcher_opts(opts),
      safety_poll_interval_ms:
        Keyword.get(opts, :safety_poll_interval_ms, @default_safety_poll_interval_ms),
      lane_safety_poll_interval_ms:
        Keyword.get(opts, :lane_safety_poll_interval_ms, @default_safety_poll_interval_ms),
      auto_schedule?: Keyword.get(opts, :auto_schedule?, true),
      run_on_boot?: Keyword.get(opts, :run_on_boot?, true)
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    _ = state.requeue_release_pending_fun.()

    if state.run_on_boot? do
      _ = reconcile_dispatch_lanes(state, :boot)
    end

    schedule_next_reconcile(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:reconcile_now, _from, state) do
    summary = reconcile_dispatch_lanes(state, :manual)
    {:reply, {:ok, summary}, state}
  end

  def handle_call(
        {:drain_lane, organization_id, mission_id, queue_lane_key, opts},
        _from,
        state
      ) do
    result = drain_owned_lane(state, organization_id, mission_id, queue_lane_key, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:reconcile, state) do
    _ = reconcile_dispatch_lanes(state, :safety)
    schedule_next_reconcile(state)
    {:noreply, state}
  end

  defp reconcile_dispatch_lanes(state, reason) do
    pending_lanes = state.list_pending_queue_lanes_fun.()

    Enum.each(pending_lanes, fn lane ->
      :ok =
        DispatchSupervisor.ensure_lane_dispatcher_started(
          state.process_namespace,
          lane.organization_id,
          lane.mission_id,
          lane.queue_lane_key,
          Keyword.put(
            state.lane_dispatcher_opts,
            :safety_poll_interval_ms,
            state.lane_safety_poll_interval_ms
          )
        )
    end)

    summary = %{pending_lane_count: length(pending_lanes)}
    emit(:reconcile, state, summary, %{reason: reason})
    summary
  end

  defp schedule_next_reconcile(%{
         auto_schedule?: true,
         safety_poll_interval_ms: safety_poll_interval_ms
       }) do
    Process.send_after(self(), :reconcile, safety_poll_interval_ms)
  end

  defp schedule_next_reconcile(_state), do: :ok

  defp emit(event, state, measurements, metadata) when is_atom(event) do
    :telemetry.execute(
      @event_prefix ++ [event],
      measurements,
      Map.merge(metadata, %{
        safety_poll_interval_ms: state.safety_poll_interval_ms,
        lane_safety_poll_interval_ms: state.lane_safety_poll_interval_ms
      })
    )
  end

  defp dispatcher_server(%ProcessNamespace{} = process_namespace),
    do: process_namespace.dispatcher

  defp dispatcher_server(server), do: server

  defp call_dispatcher(process_namespace, request) do
    case GenServer.whereis(process_namespace.dispatcher) do
      pid when is_pid(pid) -> GenServer.call(pid, request, :infinity)
      nil -> {:error, :dispatcher_not_running}
    end
  catch
    :exit, {:noproc, _details} -> {:error, :dispatcher_not_running}
    :exit, {:normal, _details} -> {:error, :dispatcher_not_running}
  end

  defp process_namespace(opts) do
    Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
  end

  defp lane_dispatcher_opts(opts) do
    process_namespace = process_namespace(opts)

    lane_opts =
      opts
      |> Keyword.get(:lane_dispatcher_opts, [])
      |> Keyword.put_new(
        :reference_time_fun,
        Keyword.get(opts, :reference_time_fun, &DateTime.utc_now/0)
      )

    dispatch_fun =
      Keyword.get(
        lane_opts,
        :dispatch_fun,
        Keyword.get(opts, :dispatch_fun, &Commanding.dispatch_queue_lane/5)
      )

    owned_dispatch_fun = fn organization_id,
                            mission_id,
                            queue_lane_key,
                            released_by,
                            dispatch_opts ->
      dispatch_fun.(
        organization_id,
        mission_id,
        queue_lane_key,
        released_by,
        Keyword.put(dispatch_opts, :process_namespace, process_namespace)
      )
    end

    Keyword.put(lane_opts, :dispatch_fun, owned_dispatch_fun)
  end
end
