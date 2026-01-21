defmodule Cadence.Runtime.Transport.COP1.Stream do
  @moduledoc """
  COP-1 stream state for uplink windowing and timers.
  """

  require Logger

  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Runtime.Transport.COP1.Context
  alias Cadence.Runtime.Uplink.ReleasedUplinkFrame
  alias Cadence.Time.Timer, as: TimeTimer

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
          bypass_flag: 0 | 1,
          control_command_flag: 0 | 1,
          segment_header_flag: 0 | 1,
          correlation_tracker: map()
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
    bypass_flag: 0,
    control_command_flag: 0,
    segment_header_flag: 0,
    correlation_tracker: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = state) do
    %{
      enabled: state.enabled,
      pending_count: :queue.len(state.pending),
      in_flight_count: length(state.in_flight),
      lockout: state.lockout,
      wait: state.wait,
      retransmit: state.retransmit,
      unlock_pending: state.unlock_pending,
      last_report_value: state.last_report_value
    }
  end

  @spec send_frames(t(), [map()], Context.t()) :: {:ok, t()} | {:error, term(), t()}
  def send_frames(%__MODULE__{enabled: false} = state, _frames, _context),
    do: {:error, :cop1_disabled, state}

  def send_frames(%__MODULE__{} = state, frames, %Context{} = context)
      when is_list(frames) do
    with {:ok, context} <- prepare_context(state, context),
         :ok <- ensure_send_allowed(state, context),
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
      {:error, reason} ->
        {:error, reason, state}

      {:error, reason, next_state} ->
        {:error, reason, next_state}
    end
  end

  def send_frames(%__MODULE__{} = state, _frames, _context),
    do: {:error, :invalid_payload, state}

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
            |> emit_command_failures(:timeout, reason: :max_retransmit)
            |> cancel_all_timers()
            |> clear_queues()

          state
        else
          retransmit_frame(state, frame)
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
      {state, :ok}
    else
      {frames, pending} = take_pending(state.pending, available)
      state = %{state | pending: pending}
      send_frames(state, frames)
    end
  end

  defp ensure_send_allowed(%__MODULE__{lockout: true} = state, %Context{} = context) do
    if bypass_mode?(context, state) do
      :ok
    else
      {:error, :lockout}
    end
  end

  defp ensure_send_allowed(_state, _context), do: :ok

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
  end

  defp bypass_mode?(%Context{} = context, state) do
    bypass_flag = Context.normalize_flag(context.bypass_flag, state.bypass_flag)

    control_flag =
      Context.normalize_flag(context.control_command_flag, state.control_command_flag)

    bypass = context.bypass == true

    bypass_flag == 1 or control_flag == 1 or bypass
  end

  defp prepare_context(state, %Context{} = context) do
    context = Context.normalize_control(context)

    context =
      context
      |> Context.put_if_nil(:stream_id, state.stream_id)
      |> Context.put_if_nil(:initial_seq, state.initial_seq || 0)
      |> Context.put_if_nil(:bypass_flag, state.bypass_flag)
      |> Context.put_if_nil(:control_command_flag, state.control_command_flag)
      |> Context.put_if_nil(:segment_header_flag, state.segment_header_flag)

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
          {%{state | in_flight: remaining}, acked}
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

  defp seq_distance(base, seq) do
    rem(seq - base + 256, 256)
  end
end
