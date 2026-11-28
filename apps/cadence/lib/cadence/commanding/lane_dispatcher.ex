defmodule Cadence.Commanding.LaneDispatcher do
  @moduledoc false

  use GenServer

  require Logger

  alias Cadence.Commanding.LaneDispatcher.Summary
  alias Cadence.Commanding.ProcessNamespace
  alias Cadence.Control.Commanding

  @default_safety_poll_interval_ms 60_000
  # #33: the uplink is busy with a COP-1 release in flight; retry soon (completion also kicks).
  @uplink_busy_retry_ms 500
  # An uplink session that just attached recovers its protocol state before it qualifies
  # (about a second); past this it falls back to the safety poll so a stuck one doesn't spin.
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

  @doc """
  What the lane last saw and when it dispatches next (#38), for operators: `last_result`
  (`%{result, at}` or nil before its first dispatch), `next_dispatch` (`%{reason, at}` or nil)
  and the wait it last logged. `{:error, :busy}` when the lane is mid-dispatch past `timeout`.
  """
  @spec status(GenServer.server(), timeout()) :: {:ok, map()} | {:error, :busy | :noproc}
  def status(server, timeout \\ 1_000) do
    GenServer.call(server, :status, timeout)
  catch
    :exit, {:timeout, _} -> {:error, :busy}
    :exit, _ -> {:error, :noproc}
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
      session_recovery_wait_ms:
        Keyword.get(opts, :session_recovery_wait_ms, @default_session_recovery_wait_ms),
      reference_time_fun: Keyword.get(opts, :reference_time_fun, &DateTime.utc_now/0),
      dispatch_fun: Keyword.get(opts, :dispatch_fun, &Commanding.dispatch_queue_lane/5),
      run_on_boot?: Keyword.get(opts, :run_on_boot?, true),
      dispatch_timer: nil,
      last_result: nil,
      # What the lane last waited on, so a wait is logged once, not every poll.
      waiting: nil,
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
  def handle_call(:status, _from, state) do
    next =
      case state.dispatch_timer do
        %{reason: reason, at: at} -> %{reason: reason, at: at}
        nil -> nil
      end

    {:reply,
     {:ok, %{last_result: state.last_result, next_dispatch: next, waiting: state.waiting}}, state}
  end

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

    result =
      state.dispatch_fun.(
        state.organization_id,
        state.mission_id,
        state.queue_lane_key,
        state.released_by,
        attempted_at: attempted_at
      )

    state = %{state | last_result: %{result: Summary.result(result), at: attempted_at}}

    case result do
      {:ok, _release_result} ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :released})
        drain_available(%{state | waiting: nil}, :continuation, released_count + 1)

      {:error, :command_queue_lane_empty} ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :empty})
        {:stop, Summary.quiescence(:empty, released_count), %{state | waiting: nil}}

      {:error, {:command_queue_lane_waiting_for_not_before, _, %DateTime{} = next_not_before}} =
          _result ->
        delay_ms = max(datetime_diff_ms(next_not_before, attempted_at), 0)

        emit(:dispatch_result, state, %{count: 1}, %{
          result: :waiting_for_not_before,
          next_not_before: next_not_before
        })

        state =
          state
          |> waiting({:not_before, next_not_before}, fn ->
            "command lane #{state.queue_lane_key}: waiting for the head's not_before " <>
              DateTime.to_iso8601(next_not_before)
          end)
          |> schedule_dispatch(delay_ms, :not_before)

        {:quiescent, Summary.quiescence(:waiting_for_not_before, released_count, next_not_before),
         state}

      {:error, {:uplink_busy, _busy} = wait} ->
        state = uplink_wait(state, wait, attempted_at)
        {:quiescent, Summary.quiescence(:waiting_for_release_target, released_count), state}

      # The uplink refused it before sending (#33): it failed and closed; go on to the next,
      # so stop-on-failure settles the rest of a group now.
      {:error, {:command_release_refused, attempt_id, reason}} ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :release_refused})

        Logger.warning(
          "command lane #{state.queue_lane_key}: release #{attempt_id} refused before send: " <>
            inspect(reason)
        )

        drain_available(state, :continuation, released_count)

      # The head was failed closed (stop-on-failure, or a basis that can't release): its entry
      # is closed, so the lane moves on instead of waiting for the safety poll.
      {:error, reason}
      when reason in [
             :earlier_command_failed,
             :release_basis_changed,
             :model_approval_withdrawn_after_go
           ] ->
        emit(:dispatch_result, state, %{count: 1}, %{result: reason})
        drain_available(state, :continuation, released_count)

      {:error, {:command_queue_lane_no_release_target, source_endpoint_ref, _mission_id}} =
          _result ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :no_release_target})

        state =
          state
          |> waiting(:no_release_target, fn ->
            "command lane #{state.queue_lane_key}: waiting, no releasable uplink of " <>
              "#{source_endpoint_ref}'s spacecraft (no active pass of its own, or not qualified)"
          end)
          |> schedule_dispatch(state.safety_poll_interval_ms, :safety)

        {:quiescent, Summary.quiescence(:waiting_for_release_target, released_count), state}

      {:error, reason} ->
        failed_or_waiting(state, reason, released_count, attempted_at)
    end
  end

  defp failed_or_waiting(
         state,
         {:uplink_session_blocked, :protocol_recovery_required} = wait,
         released_count,
         attempted_at
       ) do
    state = uplink_wait(state, wait, attempted_at)
    {:quiescent, Summary.quiescence(:waiting_for_release_target, released_count), state}
  end

  defp failed_or_waiting(state, reason, released_count, _attempted_at) do
    emit(:dispatch_result, state, %{count: 1}, %{result: :error})
    Logger.warning("command lane #{state.queue_lane_key}: dispatch failed: #{inspect(reason)}")
    state = schedule_dispatch(state, state.safety_poll_interval_ms, :safety)
    {:error, %{released_count: released_count, reason: reason}, state}
  end

  defp uplink_wait(state, {:uplink_busy, busy}, _attempted_at) do
    emit(:dispatch_result, state, %{count: 1}, %{result: :uplink_busy})

    state
    |> waiting({:uplink_busy, busy}, fn ->
      "command lane #{state.queue_lane_key}: waiting, uplink busy (#{busy}); " <>
        "retrying every #{@uplink_busy_retry_ms}ms"
    end)
    |> schedule_dispatch(@uplink_busy_retry_ms, :uplink_busy)
  end

  # Expected before qualification, not a failure (023 and 001, 11-11): retried like a busy
  # uplink until the session recovers, logged once at info.
  defp uplink_wait(state, {:uplink_session_blocked, :protocol_recovery_required}, attempted_at) do
    emit(:dispatch_result, state, %{count: 1}, %{result: :session_recovering})
    session_recovering(state, attempted_at)
  end

  defp session_recovering(state, attempted_at) do
    since =
      case state.waiting do
        {:session_recovery, since} -> since
        {:session_recovery_stalled, since} -> since
        _other -> attempted_at
      end

    if datetime_diff_ms(attempted_at, since) < state.session_recovery_wait_ms do
      state
      |> waiting({:session_recovery, since}, fn ->
        "command lane #{state.queue_lane_key}: waiting, uplink session recovering its " <>
          "protocol state; retrying every #{@uplink_busy_retry_ms}ms"
      end)
      |> schedule_dispatch(@uplink_busy_retry_ms, :session_recovery)
    else
      state
      |> waiting(
        {:session_recovery_stalled, since},
        fn ->
          "command lane #{state.queue_lane_key}: uplink session still recovering after " <>
            "#{div(state.session_recovery_wait_ms, 1_000)}s; retrying on the safety poll"
        end,
        :warning
      )
      |> schedule_dispatch(state.safety_poll_interval_ms, :safety)
    end
  end

  # Logs a wait when the lane starts waiting on it (not on every poll), at info by default.
  defp waiting(state, kind, message, level \\ :info)
  defp waiting(%{waiting: kind} = state, kind, _message, _level), do: state

  defp waiting(state, kind, message, level) do
    Logger.log(level, message.())
    %{state | waiting: kind}
  end

  defp schedule_dispatch(state, delay_ms, reason) when is_integer(delay_ms) and delay_ms >= 0 do
    state = cancel_dispatch_timer(state)
    token = make_ref()
    ref = Process.send_after(self(), {:dispatch, token}, delay_ms)

    emit(:timer_scheduled, state, %{count: 1, delay_ms: delay_ms}, %{reason: reason})

    at = DateTime.add(state.reference_time_fun.(), delay_ms, :millisecond)
    %{state | dispatch_timer: %{ref: ref, token: token, reason: reason, at: at}}
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
