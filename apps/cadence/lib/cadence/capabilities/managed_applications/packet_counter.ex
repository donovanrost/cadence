defmodule Cadence.Capabilities.ManagedApplications.PacketCounter do
  @moduledoc """
  Simple first-party managed application used to exercise partition-owned state
  and timer execution.
  """

  @behaviour Cadence.ApplicationDispatch.Handler
  @behaviour Cadence.Capabilities.Family
  @behaviour Cadence.Capabilities.ManagedApplication

  alias Cadence.ActionRequests.ScheduleTimer
  alias Cadence.ApplicationDispatch.WorkItem
  alias Cadence.Capabilities.Definitions.PacketCounter, as: Definition

  alias Cadence.Capabilities.{
    ExecutionContext,
    ExecutionResult
  }

  @flush_timer_key "flush"

  @impl true
  defdelegate descriptor(), to: Definition

  @impl true
  def handler_key, do: :packet_counter

  @impl true
  defdelegate validate_config(configuration, validation_context), to: Definition

  @impl true
  def build_instance(configuration, _activation_context) do
    Definition.normalize_config(configuration)
  end

  @impl true
  def init_instance(configuration, %ExecutionContext{}) do
    with {:ok, normalized_configuration} <- Definition.normalize_config(configuration) do
      {:ok,
       ExecutionResult.new(%{
         state: %{
           metric_name: normalized_configuration.metric_name,
           flush_interval_ms: normalized_configuration.flush_interval_ms,
           packet_count: 0,
           flush_count: 0,
           last_flushed_count: 0,
           timer_armed?: false
         }
       })}
    end
  end

  @impl true
  def handle_record(_record, app_state, %ExecutionContext{}) when not is_map(app_state) do
    {:error, {:invalid_packet_counter_state, app_state}}
  end

  def handle_record(_record, app_state, %ExecutionContext{}) do
    updated_state =
      app_state
      |> Map.update!(:packet_count, &(&1 + 1))

    if updated_state.timer_armed? do
      {:ok, ExecutionResult.new(%{state: updated_state})}
    else
      {:ok,
       ExecutionResult.new(%{
         state: %{updated_state | timer_armed?: true},
         action_requests: [
           ScheduleTimer.new(%{
             timer_key: @flush_timer_key,
             delay_ms: updated_state.flush_interval_ms,
             metadata: %{metric_name: updated_state.metric_name}
           })
         ]
       })}
    end
  end

  @impl true
  def handle_timer(@flush_timer_key, app_state, %ExecutionContext{})
      when is_map(app_state) do
    flushed_count = Map.get(app_state, :packet_count, 0)

    {:ok,
     ExecutionResult.new(%{
       state: %{
         app_state
         | packet_count: 0,
           flush_count: Map.get(app_state, :flush_count, 0) + 1,
           last_flushed_count: flushed_count,
           timer_armed?: false
       }
     })}
  end

  def handle_timer(timer_key, _app_state, %ExecutionContext{}) do
    {:error, {:unknown_packet_counter_timer, timer_key}}
  end

  @impl true
  def snapshot_state(app_state, %ExecutionContext{}) when is_map(app_state) do
    {:ok, app_state}
  end

  def snapshot_state(app_state, %ExecutionContext{}) do
    {:error, {:invalid_packet_counter_state, app_state}}
  end

  @impl true
  def handle(_packet_record, %WorkItem{}) do
    {:error, :runtime_execution_required}
  end
end
