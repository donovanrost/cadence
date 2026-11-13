defmodule Cadence.Commanding.LaneDispatcher do
  @moduledoc false

  use GenServer

  require Logger

  alias Cadence.Commanding.ProcessNamespace
  alias Cadence.Control.Commanding

  @default_safety_poll_interval_ms 60_000
  # A session that just attached finishes protocol recovery about a second later: the lane
  # retries at this cadence, for at most session_recovery_wait_ms, before the safety poll.
  @session_recovery_retry_ms 500
  @default_session_recovery_wait_ms 30_000
  @event_prefix [:cadence, :commanding, :lane_dispatcher]

  @type quiescence_status ::
          :empty | :waiting_for_not_before | :waiting_for_release_target
  @type drain_summary :: %{
          released_count: non_neg_integer(),
          status: quiescence_status(),
          next_not_before: DateTime.t() | nil
        }
  @type drain_error :: %{released_count: non_neg_integer(), reason: term()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    organization_id = Keyword.fetch!(opts, :organization_id)
    mission_id = Keyword.fetch!(opts, :mission_id)
    queue_lane_key = Keyword.fetch!(opts, :queue_lane_key)
    process_namespace = process_namespace(opts)

    default_name =
      ProcessNamespace.via(
        process_namespace,
        {organization_id, mission_id, queue_lane_key}
      )

    case Keyword.get(opts, :name, default_name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec drain(GenServer.server()) :: {:ok, drain_summary()} | {:error, drain_error() | :noproc}
  def drain(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> drain_pid(pid)
      nil -> {:error, :noproc}
    end
  end

  @spec dispatch_now(GenServer.server()) ::
          {:ok, drain_summary()} | {:error, drain_error() | :noproc}
  def dispatch_now(server) do
    drain(server)
  end

  defp drain_pid(pid) do
    monitor = Process.monitor(pid)

    try do
      pid
      |> GenServer.call(:drain, :infinity)
      |> await_empty_lane_exit(monitor, pid)
    catch
      :exit, {:noproc, _details} -> {:error, :noproc}
      :exit, {:normal, _details} -> {:error, :noproc}
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp await_empty_lane_exit({:ok, %{status: :empty}} = result, monitor, pid) do
    receive do
      {:DOWN, ^monitor, :process, ^pid, :normal} -> result
      {:DOWN, ^monitor, :process, ^pid, _reason} -> {:error, :noproc}
    end
  end

  defp await_empty_lane_exit(result, _monitor, _pid), do: result

  @impl true
  def init(opts) do
    state = %{
      organization_id: Keyword.fetch!(opts, :organization_id),
      mission_id: Keyword.fetch!(opts, :mission_id),
      queue_lane_key: Keyword.fetch!(opts, :queue_lane_key),
      safety_poll_interval_ms:
        Keyword.get(opts, :safety_poll_interval_ms, @default_safety_poll_interval_ms),
      reference_time_fun: Keyword.get(opts, :reference_time_fun, &DateTime.utc_now/0),
      dispatch_fun: Keyword.get(opts, :dispatch_fun, &Commanding.dispatch_queue_lane/5),
      run_on_boot?: Keyword.get(opts, :run_on_boot?, true),
      session_recovery_wait_ms:
        Keyword.get(opts, :session_recovery_wait_ms, @default_session_recovery_wait_ms),
      dispatch_timer: nil,
      # {:waiting | :stalled, since} while the uplink session recovers, so each is logged once.
      session_recovery: nil,
      released_by:
        Keyword.get_lazy(opts, :released_by, fn ->
          %{
            "service" => "command_dispatcher",
            "organization_id" => Keyword.fetch!(opts, :organization_id),
            "mission_id" => Keyword.fetch!(opts, :mission_id),
            "queue_lane_key" => Keyword.fetch!(opts, :queue_lane_key)
          }
        end)
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    if state.run_on_boot? do
      {:noreply, schedule_dispatch(state, 0, :bootstrap)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:drain, _from, state) do
    state = cancel_dispatch_timer(state)

    case drain_available(state, :notification, 0) do
      {:stop, summary, state} ->
        {:stop, :normal, {:ok, summary}, state}

      {:quiescent, summary, state} ->
        {:reply, {:ok, summary}, state}

      {:error, error, state} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_info({:dispatch, token}, state) do
    case state.dispatch_timer do
      %{token: ^token} ->
        state = clear_dispatch_timer(state)

        case drain_available(state, :timer, 0) do
          {:stop, _summary, state} ->
            {:stop, :normal, state}

          {:quiescent, _summary, state} ->
            {:noreply, state}

          {:error, _error, state} ->
            {:noreply, state}
        end

      _stale_or_canceled_timer ->
        emit(:stale_timer, state, %{count: 1}, %{})
        {:noreply, state}
    end
  end

  defp drain_available(state, reason, released_count) do
    attempted_at = state.reference_time_fun.()

    emit(:dispatch_attempt, state, %{count: 1}, %{reason: reason})
    {recovery, state} = Map.get_and_update!(state, :session_recovery, &{&1, nil})

    case state.dispatch_fun.(
           state.organization_id,
           state.mission_id,
           state.queue_lane_key,
           state.released_by,
           attempted_at: attempted_at
         ) do
      {:ok, _release_result} ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :released})
        drain_available(state, :continuation, released_count + 1)

      {:error, :command_queue_lane_empty} ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :empty})
        {:stop, quiescence_summary(:empty, released_count), state}

      {:error, {:command_queue_lane_waiting_for_not_before, _, %DateTime{} = next_not_before}} =
          _result ->
        delay_ms = max(datetime_diff_ms(next_not_before, attempted_at), 0)

        emit(:dispatch_result, state, %{count: 1}, %{
          result: :waiting_for_not_before,
          next_not_before: next_not_before
        })

        state = schedule_dispatch(state, delay_ms, :not_before)

        {:quiescent, quiescence_summary(:waiting_for_not_before, released_count, next_not_before),
         state}

      {:error, {:command_queue_lane_no_release_target, _source_endpoint_ref, _mission_id}} =
          _result ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :no_release_target})
        state = schedule_dispatch(state, state.safety_poll_interval_ms, :safety)

        {:quiescent, quiescence_summary(:waiting_for_release_target, released_count), state}

      {:error, reason} ->
        failed_or_waiting(state, reason, released_count, {recovery, attempted_at})
    end
  end

  # Expected right after a session attaches, not a failure: retried every 500 ms and logged
  # once at info. Past session_recovery_wait_ms it falls back to the safety poll and warns once,
  # so a session that never recovers doesn't spin.
  defp failed_or_waiting(
         state,
         {:uplink_session_blocked, :protocol_recovery_required},
         released_count,
         {recovery, attempted_at}
       ) do
    emit(:dispatch_result, state, %{count: 1}, %{result: :session_recovering})
    since = recovery_since(recovery, attempted_at)

    state =
      if datetime_diff_ms(attempted_at, since) < state.session_recovery_wait_ms do
        state
        |> log_recovery(recovery, {:waiting, since}, :info, fn ->
          "command lane #{state.queue_lane_key}: waiting, uplink session recovering its " <>
            "protocol state; retrying every #{@session_recovery_retry_ms}ms"
        end)
        |> schedule_dispatch(@session_recovery_retry_ms, :session_recovery)
      else
        state
        |> log_recovery(recovery, {:stalled, since}, :warning, fn ->
          "command lane #{state.queue_lane_key}: uplink session still recovering after " <>
            "#{div(state.session_recovery_wait_ms, 1_000)}s; retrying on the safety poll"
        end)
        |> schedule_dispatch(state.safety_poll_interval_ms, :safety)
      end

    {:quiescent, quiescence_summary(:waiting_for_release_target, released_count), state}
  end

  defp failed_or_waiting(state, reason, released_count, _recovery) do
    emit(:dispatch_result, state, %{count: 1}, %{result: :error})
    state = schedule_dispatch(state, state.safety_poll_interval_ms, :safety)
    {:error, %{released_count: released_count, reason: reason}, state}
  end

  defp recovery_since({_phase, since}, _attempted_at), do: since
  defp recovery_since(nil, attempted_at), do: attempted_at

  defp log_recovery(state, recovery, recovery, _level, _message),
    do: %{state | session_recovery: recovery}

  defp log_recovery(state, _previous, recovery, level, message) do
    Logger.log(level, message.())
    %{state | session_recovery: recovery}
  end

  defp quiescence_summary(status, released_count, next_not_before \\ nil) do
    %{
      released_count: released_count,
      status: status,
      next_not_before: next_not_before
    }
  end

  defp schedule_dispatch(state, delay_ms, reason) when is_integer(delay_ms) and delay_ms >= 0 do
    state = cancel_dispatch_timer(state)
    token = make_ref()
    ref = Process.send_after(self(), {:dispatch, token}, delay_ms)

    emit(:timer_scheduled, state, %{count: 1, delay_ms: delay_ms}, %{reason: reason})

    %{state | dispatch_timer: %{ref: ref, token: token}}
  end

  defp cancel_dispatch_timer(%{dispatch_timer: nil} = state), do: state

  defp cancel_dispatch_timer(%{dispatch_timer: %{ref: ref}} = state) do
    _ = Process.cancel_timer(ref)
    %{state | dispatch_timer: nil}
  end

  defp clear_dispatch_timer(state), do: %{state | dispatch_timer: nil}

  defp emit(event, state, measurements, metadata) when is_atom(event) do
    :telemetry.execute(
      @event_prefix ++ [event],
      measurements,
      state
      |> scheduler_metadata()
      |> Map.merge(metadata)
    )
  end

  defp scheduler_metadata(state) do
    %{
      organization_id: state.organization_id,
      mission_id: state.mission_id,
      queue_lane_key: state.queue_lane_key,
      timer_count: if(is_nil(state.dispatch_timer), do: 0, else: 1)
    }
  end

  defp datetime_diff_ms(%DateTime{} = target_time, %DateTime{} = current_time) do
    DateTime.diff(target_time, current_time, :millisecond)
  end

  defp process_namespace(opts) do
    Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
  end
end
