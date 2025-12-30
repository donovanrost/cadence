defmodule Cadence.Test.Adapters.InMemoryExecutionPersistence do
  @moduledoc """
  In-memory persistence adapter for v1 procedure execution tests.

  Stores step events in an Agent and uses the in-memory execution repository
  for status updates and logs.
  """

  use Agent

  @behaviour Cadence.Ports.Persistence.Procedures.ExecutionPersistence

  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Ports.Repository.Procedures.ExecutionOperations
  alias Cadence.Procedures.Engine.ExecutionCore

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn ->
        %{
          step_events: %{}
        }
      end,
      name: name
    )
  end

  def stop(pid \\ __MODULE__) do
    try do
      Agent.stop(pid)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  def reset(pid \\ __MODULE__) do
    Agent.update(pid, fn _ -> %{step_events: %{}} end)
  end

  @impl true
  def update_status_with_log(
        execution,
        new_status,
        extra_attrs,
        log_level,
        log_message,
        _opts \\ []
      ) do
    attrs = Map.merge(%{status: new_status}, extra_attrs)
    execution_ops = ExecutionOperations.impl()

    case execution_ops.update_execution(execution.id, attrs) do
      {:ok, updated} ->
        _ = create_log_entry(updated.id, log_level, log_message, extra_attrs[:step_index])
        broadcast_status_change(updated, new_status)
        broadcast_log(updated.id, log_level, log_message)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def create_log_entry(execution_id, level, message, step_index \\ nil) do
    ExecutionOperations.impl().create_log(%{
      execution_id: execution_id,
      timestamp: DateTime.utc_now(),
      level: level,
      message: message,
      step_index: step_index
    })
  end

  @impl true
  def persist_and_broadcast_log(execution_id, level, message, step_index \\ nil) do
    _ = create_log_entry(execution_id, level, message, step_index)
    broadcast_log(execution_id, level, message)
    :ok
  end

  @impl true
  def save_checkpoint(execution, step_index, checkpoint_state \\ nil) do
    ExecutionOperations.impl().update_execution(execution.id, %{
      current_step_index: step_index,
      checkpoint_state: checkpoint_state
    })
  end

  @impl true
  def persist_step_event(execution, step_name, status, data, _opts \\ []) do
    event = %{
      event_type: ExecutionCore.step_event_type(status),
      payload: %{
        "step_name" => step_name,
        "data" => data
      }
    }

    Agent.update(__MODULE__, fn state ->
      events = Map.get(state.step_events, execution.id, [])
      %{state | step_events: Map.put(state.step_events, execution.id, events ++ [event])}
    end)

    {level, message} = ExecutionCore.step_status_to_log(status, step_name, data)
    _ = create_log_entry(execution.id, level, message, execution.current_step_index)

    broadcast_step_event(execution.id, status, step_name, data)
    broadcast_log(execution.id, level, message)
    :ok
  end

  @impl true
  def persist_dag_result(execution, final_status, result) do
    completed_at =
      if final_status in [:completed, :failed, :cancelled] do
        DateTime.utc_now()
      end

    attrs = %{
      status: final_status,
      completed_at: completed_at,
      completed_steps: result.completed_steps,
      skipped_steps: result.skipped_steps,
      failed_steps: result.failed_steps,
      blocked_steps: result.blocked_steps,
      step_results: result.step_results
    }

    attrs =
      if final_status == :failed do
        failed_names = Enum.join(result.failed_steps || [], ", ")
        Map.put(attrs, :error_message, "Steps failed: #{failed_names}")
      else
        attrs
      end

    case ExecutionOperations.impl().update_execution(execution.id, attrs) do
      {:ok, updated} ->
        broadcast_status_change(updated, final_status)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_step_events(execution_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.step_events, execution_id, [])
    end)
  end

  defp event_publisher, do: EventPublisher.impl()

  defp broadcast_status_change(execution, new_status) do
    topic = "procedure:#{execution.id}"
    event_publisher().publish(topic, {:status_changed, new_status, execution})
  end

  defp broadcast_log(execution_id, level, message) do
    topic = "procedure:#{execution_id}"
    event_publisher().publish(topic, {:log, level, message})
  end

  defp broadcast_step_event(execution_id, status, step_name, data) do
    topic = "procedure:#{execution_id}"
    event = ExecutionCore.dag_status_to_event(status, step_name, data)
    event_publisher().publish(topic, event)
  end
end
