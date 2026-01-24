defmodule Cadence.Runtime.Transport.COP1.Stream do
  @moduledoc """
  COP-1 stream state for uplink windowing and timers.
  """

  require Logger

  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Runtime.Transport.COP1.Context
  alias Cadence.Runtime.Transport.COP1.Metrics
  alias Cadence.Runtime.Transport.COP1.Report
  alias Cadence.Runtime.Transport.COP1.StreamServer
  alias Cadence.Runtime.Uplink.ReleasedUplinkFrame
  alias Cadence.Time.Timer, as: TimeTimer
  alias Cadence.Transport.TCStreamId

  @type release_fun :: (ReleasedUplinkFrame.t() -> :ok | {:error, term()})
  @type event_fun :: (map() -> any())

  @type t :: %__MODULE__{
          mission_id: String.t() | nil,
          interface_id: String.t() | nil,
          stream_id: term() | nil,
          release_fun: release_fun() | nil,
          event_fun: event_fun() | nil,
          enabled: boolean() | nil,
          frame_size: non_neg_integer() | nil,
          default_scid: non_neg_integer() | nil,
          default_vcid: non_neg_integer() | nil,
          window_size: non_neg_integer() | nil,
          timeout_ms: non_neg_integer() | nil,
          max_retransmit: non_neg_integer() | nil,
          initial_seq: non_neg_integer() | nil,
          pending: :queue.queue(),
          in_flight: list(),
          timers: map(),
          lockout: boolean(),
          wait: boolean(),
          retransmit: boolean(),
          unlock_pending: boolean(),
          last_report_value: non_neg_integer() | nil,
          correlation_tracker: map(),
          held: boolean(),
          hold_emitted: boolean()
        }

  defstruct [
    :mission_id,
    :interface_id,
    :stream_id,
    :release_fun,
    :event_fun,
    :enabled,
    :frame_size,
    :default_scid,
    :default_vcid,
    :window_size,
    :timeout_ms,
    :max_retransmit,
    :initial_seq,
    pending: :queue.new(),
    in_flight: [],
    timers: %{},
    lockout: false,
    wait: false,
    retransmit: false,
    unlock_pending: false,
    last_report_value: nil,
    correlation_tracker: %{},
    held: true,
    hold_emitted: false
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @spec resync(TCStreamId.t()) :: :ok | {:error, :stream_not_found}
  def resync(%TCStreamId{} = tc_stream_id) do
    StreamServer.resync(tc_stream_id)
  end

  @spec on_restart(t()) :: t()
  def on_restart(%__MODULE__{} = state) do
    state
    |> emit_stream_event(:cop1_stream_restarted, reason: %{policy: :hold_on_restart})
    |> set_held_gauge(1)
    |> set_in_flight_gauge()
  end

  @spec resync_state(t(), term()) :: t()
  def resync_state(%__MODULE__{} = state, reason \\ :manual) do
    state
    |> Map.put(:held, false)
    |> Map.put(:hold_emitted, false)
    |> emit_stream_event(:cop1_stream_resynced, reason: reason)
    |> set_held_gauge(0)
  end

  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = state) do
    %{
      enabled: state.enabled,
      pending_count: :queue.len(state.pending),
      in_flight_count: length(state.in_flight),
      lockout: state.lockout,
      held: state.held,
      wait: state.wait,
      retransmit: state.retransmit,
      unlock_pending: state.unlock_pending,
      last_report_value: state.last_report_value
    }
  end

  @spec send_frames(t(), [map()], Context.t()) ::
          {:ok, t()} | {:error, term(), t()} | {:defer, term(), t()}
  def send_frames(%__MODULE__{enabled: false} = state, _frames, _context),
    do: {:error, :cop1_disabled, state}

  def send_frames(%__MODULE__{} = state, frames, %Context{} = context)
      when is_list(frames) do
    with {:ok, context} <- prepare_context(state, context),
         {:ok, state} <- ensure_send_allowed(state, context),
         frames = attach_correlation_id(frames, context),
         {:ok, final_state} <- dispatch_frames(state, frames, context) do
      final_state =
        if bypass_mode?(context, state) do
          emit_bypass_accepts(final_state, frames)
        else
          register_correlation(final_state, frames, context)
        end

      {:ok, final_state}
    else
      {:defer, reason, next_state} ->
        {:defer, reason, next_state}

      {:error, reason} ->
        {:error, reason, state}

      {:error, reason, next_state} ->
        {:error, reason, next_state}
    end
  end

  def send_frames(%__MODULE__{} = state, _frames, _context),
    do: {:error, :invalid_payload, state}

  @spec apply_report(t(), Report.t()) :: t()
  def apply_report(%__MODULE__{} = state, %Report{raw: %CLCW{} = clcw} = report) do
    state
    |> maybe_resync(report)
    |> apply_report_with_status(report, clcw)
  end

  defp apply_report_with_status(state, %Report{status: :reject, seq: seq}, _clcw) do
    handle_reject(state, seq, :reject)
  end

  defp apply_report_with_status(state, _report, clcw) do
    apply_clcw(state, clcw)
  end

  @spec apply_clcw(t(), CLCW.t()) :: t()
  def apply_clcw(%__MODULE__{enabled: false} = state, _clcw), do: state

  def apply_clcw(%__MODULE__{} = state, %CLCW{} = clcw) do
    if vcid_mismatch?(state, clcw) do
      state
    else
      was_lockout = state.lockout
      state = update_flags(state, clcw)
      state = maybe_handle_lockout(state, was_lockout, clcw)
      state = maybe_apply_report_value(state, clcw.report_value)
      state = maybe_clear_unlock_pending(state)
      state = maybe_retransmit(state, clcw)
      state
    end
  end

  @spec handle_timeout(t(), non_neg_integer()) :: t()
  def handle_timeout(%__MODULE__{lockout: true} = state, _seq), do: state

  def handle_timeout(%__MODULE__{wait: true} = state, seq) do
    reschedule_timeout(state, seq)
  end

  def handle_timeout(%__MODULE__{} = state, seq) do
    case Enum.find(state.in_flight, fn frame -> frame.seq == seq end) do
      nil ->
        state

      frame ->
        if frame.retries >= state.max_retransmit do
          Logger.warning(
            "COP-1 FOP lockout: exceeded max retransmit for interface=#{state.interface_id} seq=#{seq}"
          )

          state =
            state
            |> Map.put(:lockout, true)
            |> emit_stream_event(:cop1_stream_lockout, reason: :max_retransmit)
            |> emit_metric(:cop1_timeouts_total, 1)
            |> emit_command_failures(:timeout, reason: :max_retransmit)
            |> cancel_all_timers()
            |> clear_queues()

          state
        else
          state
          |> emit_metric(:cop1_timeouts_total, 1)
          |> emit_stream_event(:cop1_timeout, seq: seq)
          |> retransmit_frame(frame)
        end
    end
  end

  @spec maybe_send_pending(t()) :: {t(), :ok | {:error, term()}}
  def maybe_send_pending(%__MODULE__{lockout: true} = state), do: {state, :ok}
  def maybe_send_pending(%__MODULE__{wait: true} = state), do: {state, :ok}
  def maybe_send_pending(%__MODULE__{retransmit: true} = state), do: {state, :ok}

  def maybe_send_pending(%__MODULE__{} = state) do
    available = state.window_size - length(state.in_flight)

    if available <= 0 do
      state = emit_stream_event(state, :cop1_window_full, reason: length(state.in_flight))
      state = emit_metric(state, :cop1_window_full_deferrals_total, 1)
      {state, :ok}
    else
      {frames, pending} = take_pending(state.pending, available)
      state = %{state | pending: pending}
      send_frames(state, frames)
    end
  end

  defp ensure_send_allowed(%__MODULE__{held: true} = state, _context) do
    state = emit_hold_event(state, :hold_pending_resync)
    {:defer, :hold_pending_resync, state}
  end

  defp ensure_send_allowed(%__MODULE__{lockout: true} = state, %Context{} = context) do
    if bypass_mode?(context, state) do
      {:ok, state}
    else
      {:error, :lockout}
    end
  end

  defp ensure_send_allowed(%__MODULE__{} = state, _context), do: {:ok, state}

  defp dispatch_frames(state, frames, %Context{} = context) do
    if bypass_mode?(context, state) do
      case send_bypass_frames(state, frames) do
        :ok -> {:ok, handle_control_command(state, context)}
        {:error, reason} -> {:error, reason, state}
      end
    else
      state = enqueue_frames(state, frames)
      {final_state, result} = maybe_send_pending(state)

      case result do
        :ok -> {:ok, final_state}
        {:error, reason} -> {:error, reason, final_state}
      end
    end
  end

  defp attach_correlation_id(frames, %Context{} = context) when is_list(frames) do
    case correlation_id_from_context(context) do
      nil ->
        frames

      correlation_id ->
        Enum.map(frames, fn frame ->
          Map.put(frame, :correlation_id, correlation_id)
        end)
    end
  end

  defp register_correlation(%__MODULE__{} = state, frames, %Context{} = context) do
    case correlation_id_from_context(context) do
      nil ->
        state

      correlation_id ->
        frame_count = length(frames)

        tracker =
          Map.update(
            state.correlation_tracker,
            correlation_id,
            %{correlation_id: correlation_id, remaining: frame_count},
            fn entry ->
              %{entry | remaining: entry.remaining + frame_count}
            end
          )

        %{state | correlation_tracker: tracker}
    end
  end

  defp emit_bypass_accepts(%__MODULE__{} = state, frames) do
    frames
    |> Enum.map(&Map.get(&1, :correlation_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(fn correlation_id ->
      emit_protocol_event(state, :accepted, correlation_id, seq: nil)
    end)

    state
  end

  defp handle_acked_frames(%__MODULE__{} = state, []), do: state

  defp handle_acked_frames(%__MODULE__{} = state, acked) do
    {tracker, accepted} =
      Enum.reduce(acked, {state.correlation_tracker, []}, &apply_ack/2)

    Enum.each(accepted, fn %{correlation_id: correlation_id, seq: seq} ->
      emit_protocol_event(state, :accepted, correlation_id, seq: seq)
    end)

    %{state | correlation_tracker: tracker}
  end

  defp handle_reject(%__MODULE__{} = state, nil, _reason), do: state

  defp handle_reject(%__MODULE__{} = state, seq, reason) do
    {rejected, remaining} = Enum.split_with(state.in_flight, &(&1.seq == seq))

    state =
      state
      |> cancel_timers(rejected)
      |> Map.put(:in_flight, remaining)
      |> set_in_flight_gauge()

    Enum.reduce(rejected, state, fn frame, acc ->
      reject_correlation(acc, frame, reason)
    end)
  end

  defp reject_correlation(state, frame, reason) do
    correlation_id = Map.get(frame, :correlation_id)

    cond do
      is_nil(correlation_id) ->
        state

      Map.has_key?(state.correlation_tracker, correlation_id) ->
        emit_protocol_event(state, :rejected, correlation_id, reason: reason, seq: frame.seq)
        %{state | correlation_tracker: Map.delete(state.correlation_tracker, correlation_id)}

      true ->
        state
    end
  end

  defp apply_ack(frame, {tracker, accepted}) do
    correlation_id = Map.get(frame, :correlation_id)

    if is_nil(correlation_id) do
      {tracker, accepted}
    else
      update_tracker(correlation_id, frame, tracker, accepted)
    end
  end

  defp update_tracker(correlation_id, frame, tracker, accepted) do
    case Map.get(tracker, correlation_id) do
      nil ->
        {tracker, accepted}

      entry ->
        update_tracker_entry(correlation_id, frame, tracker, accepted, entry)
    end
  end

  defp update_tracker_entry(
         correlation_id,
         frame,
         tracker,
         accepted,
         %{remaining: remaining} = entry
       ) do
    new_remaining = max(remaining - 1, 0)

    if new_remaining == 0 do
      {Map.delete(tracker, correlation_id),
       [%{correlation_id: entry.correlation_id, seq: frame.seq} | accepted]}
    else
      {Map.put(tracker, correlation_id, %{entry | remaining: new_remaining}), accepted}
    end
  end

  defp emit_command_failures(%__MODULE__{} = state, status, opts) do
    state.correlation_tracker
    |> Enum.map(fn {_key, entry} -> entry.correlation_id end)
    |> Enum.each(fn correlation_id ->
      emit_protocol_event(state, status, correlation_id, opts)
    end)

    %{state | correlation_tracker: %{}}
  end

  defp emit_protocol_event(
         %__MODULE__{event_fun: event_fun} = state,
         status,
         correlation_id,
         opts
       ) do
    if is_function(event_fun, 1) do
      event_fun.(%{
        mission_id: state.mission_id,
        interface_id: state.interface_id,
        stream_id: state.stream_id,
        protocol: :cop1,
        correlation_id: correlation_id,
        status: status,
        reason: Keyword.get(opts, :reason),
        seq: Keyword.get(opts, :seq)
      })
    end

    :ok
  end

  defp correlation_id_from_context(%Context{} = context) do
    context.correlation_id
  end

  defp enqueue_frames(state, frames) do
    pending =
      Enum.reduce(frames, state.pending, fn frame, acc ->
        :queue.in(frame, acc)
      end)

    %{state | pending: pending}
  end

  defp send_frames(state, []), do: {state, :ok}

  defp send_frames(state, [frame | rest]) do
    case send_frame(state, frame) do
      {:ok, next_state} ->
        send_frames(next_state, rest)

      {:error, reason, next_state} ->
        pending = requeue_front([frame | rest], next_state.pending)
        {%{next_state | pending: pending}, {:error, reason}}
    end
  end

  defp send_bypass_frames(state, frames) do
    Enum.reduce_while(frames, :ok, fn frame, _acc ->
      case emit_release(state, frame, :bypass) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp send_frame(state, frame) do
    case emit_release(state, frame, :initial) do
      :ok ->
        {:ok, add_in_flight(state, frame)}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp emit_release(%__MODULE__{release_fun: release_fun} = state, frame, kind)
       when is_function(release_fun, 1) do
    release =
      ReleasedUplinkFrame.from_frame(
        state.mission_id,
        state.interface_id,
        state.stream_id,
        frame,
        kind
      )

    case release_fun.(release) do
      :ok ->
        :ok

      {:error, :send_failed, reason} ->
        {:error, {:send_failed, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp emit_release(_state, _frame, _kind), do: {:error, :missing_release_fun}

  defp add_in_flight(state, frame) do
    timer_ref = TimeTimer.send_after(self(), {:fop_timeout, frame.seq}, state.timeout_ms)
    timers = Map.put(state.timers, frame.seq, timer_ref)
    in_flight = state.in_flight ++ [frame]

    %{state | in_flight: in_flight, timers: timers}
    |> set_in_flight_gauge()
  end

  defp bypass_mode?(%Context{} = context, _state) do
    # Bypass mode if:
    # 1. context.bypass is explicitly true (per-issuance emergency bypass)
    # 2. This is a COP-1 control command (e.g., unlock)
    context.bypass == true or Context.control_command?(context)
  end

  defp prepare_context(state, %Context{} = context) do
    # Set stream identity on the context
    context =
      context
      |> Context.put_if_nil(:stream_id, state.stream_id)

    {:ok, context}
  end

  defp handle_control_command(state, %Context{} = context) do
    case Context.normalize_control_value(context.cop1_control) do
      :unlock -> %{state | unlock_pending: true}
      _ -> state
    end
  end

  defp maybe_handle_lockout(%{lockout: true} = state, false, _clcw) do
    state
    |> emit_stream_event(:cop1_stream_lockout, reason: :clcw_lockout)
    |> emit_command_failures(:rejected, reason: :lockout)
    |> cancel_all_timers()
    |> clear_queues()
  end

  defp maybe_handle_lockout(state, _, _), do: state

  defp maybe_retransmit(state, %CLCW{retransmit: 1}) do
    retransmit_in_flight(state)
  end

  defp maybe_retransmit(state, _clcw), do: state

  defp retransmit_in_flight(state) do
    Enum.reduce(state.in_flight, state, fn frame, acc ->
      if acc.lockout do
        acc
      else
        retransmit_frame(acc, frame)
      end
    end)
  end

  defp retransmit_frame(state, frame) do
    case emit_release(state, frame, :retransmit) do
      :ok ->
        state
        |> emit_metric(:cop1_retransmits_total, 1)
        |> emit_stream_event(:cop1_retransmit,
          seq: frame.seq,
          reason: %{retry_count: frame.retries + 1}
        )
        |> cancel_timer(frame.seq)
        |> update_retry(frame.seq)
        |> add_timer(frame.seq)

      {:error, reason} ->
        Logger.warning(
          "COP-1 retransmit failed for interface=#{state.interface_id} seq=#{frame.seq}: #{inspect(reason)}"
        )

        state
    end
  end

  defp add_timer(state, seq) do
    timer_ref = TimeTimer.send_after(self(), {:fop_timeout, seq}, state.timeout_ms)
    %{state | timers: Map.put(state.timers, seq, timer_ref)}
  end

  defp update_retry(state, seq) do
    in_flight =
      Enum.map(state.in_flight, fn frame ->
        if frame.seq == seq do
          %{frame | retries: frame.retries + 1}
        else
          frame
        end
      end)

    %{state | in_flight: in_flight}
  end

  defp reschedule_timeout(state, seq) do
    state
    |> cancel_timer(seq)
    |> add_timer(seq)
  end

  defp ack_in_flight(state, report_value) do
    case state.in_flight do
      [] ->
        {state, []}

      [oldest | _] ->
        ack_distance = seq_distance(oldest.seq, report_value)

        if ack_distance >= length(state.in_flight) do
          {state, []}
        else
          {acked, remaining} = Enum.split(state.in_flight, ack_distance + 1)
          state = cancel_timers(state, acked)
          state = %{state | in_flight: remaining} |> set_in_flight_gauge()
          {state, acked}
        end
    end
  end

  defp cancel_timers(state, frames) do
    Enum.reduce(frames, state, fn frame, acc ->
      cancel_timer(acc, frame.seq)
    end)
  end

  defp cancel_timer(state, seq) do
    case Map.pop(state.timers, seq) do
      {nil, timers} ->
        %{state | timers: timers}

      {ref, timers} ->
        _ = TimeTimer.cancel(ref)
        %{state | timers: timers}
    end
  end

  defp cancel_all_timers(state) do
    Enum.each(state.timers, fn {_seq, ref} -> TimeTimer.cancel(ref) end)
    %{state | timers: %{}}
  end

  defp clear_queues(state) do
    %{state | pending: :queue.new(), in_flight: []}
    |> set_in_flight_gauge()
  end

  defp take_pending(queue, limit) do
    take_pending(queue, limit, [])
  end

  defp take_pending(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp take_pending(queue, limit, acc) do
    case :queue.out(queue) do
      {{:value, frame}, rest} ->
        take_pending(rest, limit - 1, [frame | acc])

      {:empty, _} ->
        {Enum.reverse(acc), queue}
    end
  end

  defp requeue_front(frames, queue) do
    frames
    |> Enum.reverse()
    |> Enum.reduce(queue, fn frame, acc -> :queue.in_r(frame, acc) end)
  end

  defp vcid_mismatch?(%{default_vcid: nil}, _clcw), do: false
  defp vcid_mismatch?(state, clcw), do: clcw.vcid != state.default_vcid

  defp update_flags(state, clcw) do
    wait =
      clcw.wait == 1 or clcw.no_rf_available == 1 or clcw.no_bit_lock == 1 or
        clcw.farm_busy == 1

    %{
      state
      | lockout: clcw.lockout == 1,
        wait: wait,
        retransmit: clcw.retransmit == 1
    }
  end

  defp maybe_apply_report_value(state, report_value) do
    if valid_report_value?(state, report_value) do
      {state, acked} = ack_in_flight(state, report_value)
      state = handle_acked_frames(state, acked)
      %{state | last_report_value: report_value}
    else
      Logger.warning(
        "COP-1 FOP received out-of-window CLCW report_value=#{report_value} for interface=#{state.interface_id}"
      )

      state
    end
  end

  defp valid_report_value?(%{in_flight: []} = state, report_value) do
    case state.last_report_value do
      nil -> true
      last -> seq_distance(last, report_value) <= 127
    end
  end

  defp valid_report_value?(state, report_value) do
    [oldest | _] = state.in_flight
    seq_distance(oldest.seq, report_value) < length(state.in_flight)
  end

  defp maybe_clear_unlock_pending(%{unlock_pending: true, lockout: false} = state) do
    %{state | unlock_pending: false}
  end

  defp maybe_clear_unlock_pending(state), do: state

  defp maybe_resync(%__MODULE__{held: true} = state, _report) do
    resync_state(state, :report)
  end

  defp maybe_resync(state, _report), do: state

  defp emit_hold_event(%__MODULE__{hold_emitted: true} = state, _reason), do: state

  defp emit_hold_event(state, reason) do
    state
    |> emit_stream_event(:cop1_stream_hold, reason: reason)
    |> set_held_gauge(1)
    |> Map.put(:hold_emitted, true)
  end

  defp emit_metric(state, metric, amount) do
    case state.stream_id do
      %TCStreamId{} = tc_stream_id ->
        Metrics.inc(
          tc_stream_id.mission_id,
          tc_stream_id.interface_id,
          tc_stream_id.scid,
          tc_stream_id.vcid,
          metric,
          amount
        )

      _ ->
        :ok
    end

    state
  end

  defp set_in_flight_gauge(state) do
    set_gauge(state, :cop1_in_flight, length(state.in_flight))
  end

  defp set_held_gauge(state, value) do
    set_gauge(state, :cop1_held, value)
  end

  defp set_gauge(state, metric, value) do
    case state.stream_id do
      %TCStreamId{} = tc_stream_id ->
        Metrics.set_gauge(
          tc_stream_id.mission_id,
          tc_stream_id.interface_id,
          tc_stream_id.scid,
          tc_stream_id.vcid,
          metric,
          value
        )

      _ ->
        :ok
    end

    state
  end

  defp emit_stream_event(%__MODULE__{event_fun: event_fun} = state, status, opts) do
    if is_function(event_fun, 1) do
      event_fun.(%{
        mission_id: state.mission_id,
        interface_id: state.interface_id,
        stream_id: state.stream_id,
        protocol: :cop1,
        status: status,
        reason: Keyword.get(opts, :reason),
        seq: Keyword.get(opts, :seq)
      })
    end

    state
  end

  defp seq_distance(base, seq) do
    rem(seq - base + 256, 256)
  end
end
