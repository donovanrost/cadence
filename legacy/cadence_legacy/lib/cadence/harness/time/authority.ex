defmodule Cadence.Harness.Time.Authority do
  @moduledoc false

  use GenServer

  defstruct system_ms: 0,
            mono_ms: 0,
            timers: :gb_trees.empty(),
            timer_index: %{},
            paused: false

  @type timer_entry :: %{
          ref: reference(),
          pid: pid(),
          msg: term(),
          due_ms: non_neg_integer(),
          interval_ms: non_neg_integer() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, default_name())
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    start_time = Keyword.get(opts, :start_time, DateTime.utc_now())

    case normalize_time_ms(start_time) do
      {:ok, ms} ->
        {:ok, %__MODULE__{system_ms: ms, mono_ms: ms}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:now, _from, state) do
    {:reply, DateTime.from_unix!(state.system_ms, :millisecond), state}
  end

  @impl true
  def handle_call({:monotonic, unit}, _from, state) do
    {:reply, System.convert_time_unit(state.mono_ms, :millisecond, unit), state}
  end

  @impl true
  def handle_call({:system_time, unit}, _from, state) do
    {:reply, System.convert_time_unit(state.system_ms, :millisecond, unit), state}
  end

  @impl true
  def handle_call({:advance, ms}, _from, state) when is_integer(ms) and ms >= 0 do
    state = %{state | system_ms: state.system_ms + ms, mono_ms: state.mono_ms + ms}
    {:reply, :ok, dispatch_due_timers(state)}
  end

  def handle_call({:advance, _ms}, _from, state) do
    {:reply, {:error, :invalid_advance}, state}
  end

  @impl true
  def handle_call({:set, time}, _from, state) do
    case normalize_time_ms(time) do
      {:ok, ms} when ms >= state.system_ms ->
        state = %{state | system_ms: ms, mono_ms: max(state.mono_ms, ms)}
        {:reply, :ok, dispatch_due_timers(state)}

      {:ok, _ms} ->
        {:reply, {:error, :time_travel_not_supported}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | paused: true}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    {:reply, :ok, %{state | paused: false}}
  end

  @impl true
  def handle_call({:send_after, pid, msg, timeout_ms}, _from, state)
      when is_integer(timeout_ms) and timeout_ms >= 0 do
    {ref, state} = schedule_timer(state, pid, msg, timeout_ms, nil)
    {:reply, ref, dispatch_due_timers(state)}
  end

  def handle_call({:send_after, _pid, _msg, _timeout_ms}, _from, state) do
    {:reply, {:error, :invalid_timeout}, state}
  end

  @impl true
  def handle_call({:send_interval, interval_ms, pid, msg}, _from, state)
      when is_integer(interval_ms) and interval_ms > 0 do
    {ref, state} = schedule_timer(state, pid, msg, interval_ms, interval_ms)
    {:reply, ref, dispatch_due_timers(state)}
  end

  def handle_call({:send_interval, _interval_ms, _pid, _msg}, _from, state) do
    {:reply, {:error, :invalid_interval}, state}
  end

  @impl true
  def handle_call({:cancel, ref}, _from, state) do
    {state, result} = cancel_timer(state, ref)
    {:reply, result, state}
  end

  defp default_name do
    Application.get_env(:cadence, Cadence.Harness.Time, [])
    |> Keyword.get(:authority_name, {:global, __MODULE__})
  end

  defp normalize_time_ms(%DateTime{} = dt), do: {:ok, DateTime.to_unix(dt, :millisecond)}
  defp normalize_time_ms(ms) when is_integer(ms), do: {:ok, ms}
  defp normalize_time_ms(_), do: {:error, :invalid_time}

  defp schedule_timer(state, pid, msg, delay_ms, interval_ms) do
    ref = make_ref()
    due_ms = state.system_ms + delay_ms

    timer = %{
      ref: ref,
      pid: pid,
      msg: msg,
      due_ms: due_ms,
      interval_ms: interval_ms
    }

    {ref, insert_timer(state, timer)}
  end

  defp insert_timer(state, %{} = timer) do
    timers =
      case :gb_trees.lookup(timer.due_ms, state.timers) do
        :none -> :gb_trees.enter(timer.due_ms, [timer], state.timers)
        {:value, existing} -> :gb_trees.update(timer.due_ms, [timer | existing], state.timers)
      end

    timer_index = Map.put(state.timer_index, timer.ref, timer)
    %{state | timers: timers, timer_index: timer_index}
  end

  defp insert_timers(state, timers) do
    Enum.reduce(timers, state, &insert_timer(&2, &1))
  end

  defp cancel_timer(state, ref) do
    case Map.pop(state.timer_index, ref) do
      {nil, _timer_index} ->
        {state, false}

      {timer, timer_index} ->
        timers = remove_timer_from_tree(state.timers, timer)
        remaining_ms = max(0, timer.due_ms - state.system_ms)
        {%{state | timers: timers, timer_index: timer_index}, remaining_ms}
    end
  end

  defp dispatch_due_timers(state) do
    case next_due_batch(state) do
      {:none, state} ->
        state

      {:pending, state} ->
        state

      {:due, timers_at_due, state} ->
        state
        |> fire_timers(timers_at_due)
        |> dispatch_due_timers()
    end
  end

  defp remove_timer_from_tree(timers, timer) do
    case :gb_trees.lookup(timer.due_ms, timers) do
      :none ->
        timers

      {:value, entries} ->
        remaining = Enum.reject(entries, &(&1.ref == timer.ref))

        if remaining == [] do
          :gb_trees.delete(timer.due_ms, timers)
        else
          :gb_trees.update(timer.due_ms, remaining, timers)
        end
    end
  end

  defp next_due_batch(state) do
    if :gb_trees.is_empty(state.timers) do
      {:none, state}
    else
      {due_ms, timers_at_due, rest} = :gb_trees.take_smallest(state.timers)

      if due_ms <= state.system_ms do
        {:due, timers_at_due, %{state | timers: rest}}
      else
        state = %{state | timers: :gb_trees.insert(due_ms, timers_at_due, rest)}
        {:pending, state}
      end
    end
  end

  defp fire_timers(state, timers_at_due) do
    {timer_index, rescheduled} =
      Enum.reduce(timers_at_due, {state.timer_index, []}, &fire_timer/2)

    state
    |> Map.put(:timer_index, timer_index)
    |> insert_timers(rescheduled)
  end

  defp fire_timer(timer, {index, acc}) do
    send(timer.pid, timer.msg)
    index = Map.delete(index, timer.ref)
    {index, reschedule_timer(timer, acc)}
  end

  defp reschedule_timer(%{interval_ms: nil}, acc), do: acc

  defp reschedule_timer(%{interval_ms: interval_ms} = timer, acc) do
    [%{timer | due_ms: timer.due_ms + interval_ms} | acc]
  end
end
