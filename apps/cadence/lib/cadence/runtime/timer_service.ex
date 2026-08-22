defmodule Cadence.Runtime.TimerService do
  @moduledoc """
  Partition-owned timer state for managed applications.
  """

  alias Cadence.ActionRequests.{CancelTimer, ScheduleTimer}
  alias Cadence.Ids
  alias Cadence.Runtime.Clock

  @type timer_entry :: %{
          timer_id: binary(),
          timer_key: binary(),
          capability_instance_id: binary(),
          timer_ref: reference() | nil,
          due_at: DateTime.t(),
          metadata: map()
        }

  @type t :: %__MODULE__{
          clock: Clock.t(),
          timers: %{required({binary(), binary()}) => timer_entry()}
        }

  defstruct clock: Clock.new(), timers: %{}

  @timer_message :managed_application_timer

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    %__MODULE__{clock: Clock.new(opts)}
  end

  @spec current_time(t()) :: DateTime.t()
  def current_time(%__MODULE__{} = timer_service), do: timer_service.clock.current_time

  @spec live?(t()) :: boolean()
  def live?(%__MODULE__{} = timer_service), do: Clock.live?(timer_service.clock)

  @spec replay?(t()) :: boolean()
  def replay?(%__MODULE__{} = timer_service), do: Clock.replay?(timer_service.clock)

  @spec advance_to(t(), DateTime.t()) :: t()
  def advance_to(%__MODULE__{} = timer_service, %DateTime{} = target_time) do
    %__MODULE__{timer_service | clock: Clock.advance_to(timer_service.clock, target_time)}
  end

  @spec set_current_time(t(), DateTime.t()) :: t()
  def set_current_time(%__MODULE__{} = timer_service, %DateTime{} = current_time) do
    %__MODULE__{timer_service | clock: Clock.set_current_time(timer_service.clock, current_time)}
  end

  @spec schedule(t(), binary(), ScheduleTimer.t()) :: {:ok, t(), timer_entry()} | {:error, term()}
  def schedule(%__MODULE__{} = timer_service, capability_instance_id, %ScheduleTimer{} = request)
      when is_binary(capability_instance_id) do
    if is_binary(request.timer_key) and is_integer(request.delay_ms) and request.delay_ms > 0 do
      {cleared_service, _previous_entry} =
        cancel_existing(timer_service, capability_instance_id, request.timer_key)

      timer_id = Ids.new("timer")
      due_at = DateTime.add(current_time(cleared_service), request.delay_ms, :millisecond)

      timer_ref =
        if live?(cleared_service) do
          Process.send_after(
            self(),
            {@timer_message, capability_instance_id, request.timer_key, timer_id},
            request.delay_ms
          )
        end

      entry = %{
        timer_id: timer_id,
        timer_key: request.timer_key,
        capability_instance_id: capability_instance_id,
        timer_ref: timer_ref,
        due_at: due_at,
        metadata: request.metadata
      }

      {:ok,
       %__MODULE__{
         cleared_service
         | timers:
             Map.put(
               cleared_service.timers,
               timer_identifier(capability_instance_id, request.timer_key),
               entry
             )
       }, entry}
    else
      {:error, {:invalid_schedule_timer_request, request}}
    end
  end

  @spec cancel(t(), binary(), CancelTimer.t()) :: {:ok, t()} | {:error, term()}
  def cancel(%__MODULE__{} = timer_service, capability_instance_id, %CancelTimer{} = request)
      when is_binary(capability_instance_id) do
    if is_binary(request.timer_key) do
      {next_service, _entry} =
        cancel_existing(timer_service, capability_instance_id, request.timer_key)

      {:ok, next_service}
    else
      {:error, {:invalid_cancel_timer_request, request}}
    end
  end

  @spec cancel_capability_instance(t(), binary()) :: t()
  def cancel_capability_instance(%__MODULE__{} = timer_service, capability_instance_id)
      when is_binary(capability_instance_id) do
    timer_service.timers
    |> Enum.reduce(timer_service, fn
      {{^capability_instance_id, timer_key}, _entry}, %__MODULE__{} = acc ->
        {next_acc, _entry} = cancel_existing(acc, capability_instance_id, timer_key)
        next_acc

      {_timer_identifier, _entry}, %__MODULE__{} = acc ->
        acc
    end)
  end

  @spec cancel_all(t()) :: t()
  def cancel_all(%__MODULE__{} = timer_service) do
    Enum.each(timer_service.timers, fn {_timer_identifier, entry} ->
      cancel_timer_ref(entry.timer_ref)
    end)

    %__MODULE__{timer_service | timers: %{}}
  end

  @spec fire(t(), binary(), binary(), binary()) ::
          {:ok, t(), timer_entry()} | {:error, :stale_timer}
  def fire(%__MODULE__{} = timer_service, capability_instance_id, timer_key, timer_id)
      when is_binary(capability_instance_id) and is_binary(timer_key) and is_binary(timer_id) do
    case Map.get(timer_service.timers, timer_identifier(capability_instance_id, timer_key)) do
      %{timer_id: ^timer_id} = entry ->
        {:ok,
         %__MODULE__{
           timer_service
           | timers:
               Map.delete(
                 timer_service.timers,
                 timer_identifier(capability_instance_id, timer_key)
               )
         }, entry}

      _other ->
        {:error, :stale_timer}
    end
  end

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{} = timer_service), do: map_size(timer_service.timers)

  @spec snapshot(t()) :: [map()]
  def snapshot(%__MODULE__{} = timer_service) do
    timer_service.timers
    |> Map.values()
    |> Enum.sort_by(&{&1.capability_instance_id, &1.timer_key})
    |> Enum.map(fn entry ->
      %{
        capability_instance_id: entry.capability_instance_id,
        timer_key: entry.timer_key,
        timer_id: entry.timer_id,
        due_at: entry.due_at,
        metadata: entry.metadata
      }
    end)
  end

  defp cancel_existing(%__MODULE__{} = timer_service, capability_instance_id, timer_key) do
    timer_identifier = timer_identifier(capability_instance_id, timer_key)

    case Map.pop(timer_service.timers, timer_identifier) do
      {nil, _timers} ->
        {timer_service, nil}

      {entry, remaining_timers} ->
        cancel_timer_ref(entry.timer_ref)
        {%__MODULE__{timer_service | timers: remaining_timers}, entry}
    end
  end

  defp cancel_timer_ref(nil), do: 0
  defp cancel_timer_ref(timer_ref), do: Process.cancel_timer(timer_ref)

  defp timer_identifier(capability_instance_id, timer_key),
    do: {capability_instance_id, timer_key}
end
