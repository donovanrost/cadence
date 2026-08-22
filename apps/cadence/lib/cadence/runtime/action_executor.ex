defmodule Cadence.Runtime.ActionExecutor do
  @moduledoc """
  Executes platform-owned action requests on behalf of managed capabilities.
  """

  alias Cadence.ActionRequests.{CancelTimer, ProviderRequest, ScheduleTimer, UplinkRequest}
  alias Cadence.Runtime.TimerService

  @spec execute_many([term()], binary(), TimerService.t()) ::
          {:ok, %{timer_service: TimerService.t(), timer_events: [map()]}} | {:error, term()}
  def execute_many(action_requests, capability_instance_id, %TimerService{} = timer_service)
      when is_list(action_requests) and is_binary(capability_instance_id) do
    Enum.reduce_while(
      action_requests,
      {:ok, %{timer_service: timer_service, timer_events: []}},
      fn action_request, {:ok, acc} ->
        case execute(action_request, capability_instance_id, acc) do
          {:ok, next_acc} -> {:cont, {:ok, next_acc}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end
    )
  end

  defp execute(
         %ScheduleTimer{} = request,
         capability_instance_id,
         %{timer_service: %TimerService{} = timer_service, timer_events: timer_events}
       ) do
    case TimerService.schedule(timer_service, capability_instance_id, request) do
      {:ok, %TimerService{} = next_timer_service, entry} ->
        {:ok,
         %{
           timer_service: next_timer_service,
           timer_events:
             timer_events ++
               [
                 %{
                   event_kind: :scheduled,
                   timer_key: request.timer_key,
                   due_at: entry.due_at,
                   metadata: request.metadata
                 }
               ]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute(
         %CancelTimer{} = request,
         capability_instance_id,
         %{timer_service: %TimerService{} = timer_service, timer_events: timer_events}
       ) do
    case TimerService.cancel(timer_service, capability_instance_id, request) do
      {:ok, %TimerService{} = next_timer_service} ->
        {:ok,
         %{
           timer_service: next_timer_service,
           timer_events:
             timer_events ++
               [
                 %{
                   event_kind: :canceled,
                   timer_key: request.timer_key,
                   due_at: nil,
                   metadata: %{}
                 }
               ]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute(
         %UplinkRequest{},
         _capability_instance_id,
         %{timer_service: %TimerService{}} = acc
       ) do
    {:ok, acc}
  end

  defp execute(
         %ProviderRequest{},
         _capability_instance_id,
         %{timer_service: %TimerService{}} = acc
       ) do
    {:ok, acc}
  end

  defp execute(action_request, _capability_instance_id, %{timer_service: %TimerService{}}) do
    {:error, {:unsupported_action_request, action_request}}
  end
end
