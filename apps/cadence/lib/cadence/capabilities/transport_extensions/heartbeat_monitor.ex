defmodule Cadence.Capabilities.TransportExtensions.HeartbeatMonitor do
  @moduledoc """
  Simple first-party transport extension used to exercise the transport runtime
  and its clock-aware timer behavior.
  """

  @behaviour Cadence.Capabilities.Family
  @behaviour Cadence.Capabilities.TransportExtension

  alias Cadence.ActionRequests.{CancelTimer, ScheduleTimer}

  alias Cadence.Capabilities.{
    Descriptor,
    ExecutionContext,
    ExecutionResult,
    ValidationContext
  }

  @heartbeat_timer_key "heartbeat"

  @impl true
  def descriptor do
    Descriptor.new(%{
      family_key: :heartbeat_monitor,
      kind: :transport_extension,
      supported_scopes: [:path, :transport],
      input_stages: [],
      partition_affinity: :path,
      config_schema: nil,
      emitted_record_kinds: [],
      emitted_action_kinds: [:schedule_timer, :cancel_timer],
      replay_mode: :deterministic,
      state_mode: :stateful
    })
  end

  @impl true
  def validate_config(configuration, %ValidationContext{}) do
    with {:ok, normalized_configuration} <- normalize_configuration(configuration) do
      validate_interval(normalized_configuration.heartbeat_interval_ms)
    end
  end

  @impl true
  def build_instance(configuration, _activation_context) do
    normalize_configuration(configuration)
  end

  @impl true
  def init_transport(configuration, %ExecutionContext{}) do
    with {:ok, normalized_configuration} <- normalize_configuration(configuration) do
      {:ok,
       ExecutionResult.new(%{
         state: %{
           heartbeat_interval_ms: normalized_configuration.heartbeat_interval_ms,
           heartbeat_count: 0,
           last_transport_event_at: nil,
           last_transport_event_kind: nil,
           last_control_command: nil,
           active?: true
         },
         action_requests: [schedule_heartbeat(normalized_configuration.heartbeat_interval_ms)]
       })}
    end
  end

  @impl true
  def handle_transport_event(_event, app_state, %ExecutionContext{}) when not is_map(app_state) do
    {:error, {:invalid_heartbeat_monitor_state, app_state}}
  end

  def handle_transport_event(event, app_state, %ExecutionContext{} = execution_context) do
    {:ok,
     ExecutionResult.new(%{
       state: %{
         app_state
         | last_transport_event_at: execution_context.current_time,
           last_transport_event_kind: event_kind(event)
       }
     })}
  end

  @impl true
  def handle_control_input(_control_input, app_state, %ExecutionContext{})
      when not is_map(app_state) do
    {:error, {:invalid_heartbeat_monitor_state, app_state}}
  end

  def handle_control_input(control_input, app_state, %ExecutionContext{}) do
    case control_command(control_input) do
      :pause ->
        {:ok,
         ExecutionResult.new(%{
           state: %{app_state | active?: false, last_control_command: :pause},
           action_requests: [CancelTimer.new(%{timer_key: @heartbeat_timer_key})]
         })}

      :resume ->
        if app_state.active? do
          {:ok, ExecutionResult.new(%{state: %{app_state | last_control_command: :resume}})}
        else
          {:ok,
           ExecutionResult.new(%{
             state: %{app_state | active?: true, last_control_command: :resume},
             action_requests: [schedule_heartbeat(app_state.heartbeat_interval_ms)]
           })}
        end

      :unknown ->
        {:error, {:unsupported_heartbeat_control_input, control_input}}
    end
  end

  @impl true
  def handle_timer(@heartbeat_timer_key, app_state, %ExecutionContext{})
      when is_map(app_state) do
    if app_state.active? do
      {:ok,
       ExecutionResult.new(%{
         state: %{app_state | heartbeat_count: app_state.heartbeat_count + 1},
         action_requests: [schedule_heartbeat(app_state.heartbeat_interval_ms)]
       })}
    else
      {:ok, ExecutionResult.new(%{state: app_state})}
    end
  end

  def handle_timer(timer_key, _app_state, %ExecutionContext{}) do
    {:error, {:unknown_transport_timer, timer_key}}
  end

  @impl true
  def snapshot_state(app_state, %ExecutionContext{}) when is_map(app_state) do
    {:ok, app_state}
  end

  def snapshot_state(app_state, %ExecutionContext{}) do
    {:error, {:invalid_heartbeat_monitor_state, app_state}}
  end

  defp normalize_configuration(%{heartbeat_interval_ms: heartbeat_interval_ms}) do
    {:ok, %{heartbeat_interval_ms: heartbeat_interval_ms}}
  end

  defp normalize_configuration(%{"heartbeat_interval_ms" => heartbeat_interval_ms}) do
    {:ok, %{heartbeat_interval_ms: heartbeat_interval_ms}}
  end

  defp normalize_configuration(configuration) do
    {:error, {:unsupported_heartbeat_monitor_configuration, configuration}}
  end

  defp validate_interval(interval_ms) when is_integer(interval_ms) and interval_ms > 0, do: :ok
  defp validate_interval(interval_ms), do: {:error, {:invalid_heartbeat_interval_ms, interval_ms}}

  defp schedule_heartbeat(heartbeat_interval_ms) do
    ScheduleTimer.new(%{
      timer_key: @heartbeat_timer_key,
      delay_ms: heartbeat_interval_ms,
      metadata: %{kind: :heartbeat}
    })
  end

  defp event_kind(%{kind: kind}) when is_atom(kind), do: kind
  defp event_kind(%{"kind" => kind}) when is_binary(kind), do: kind
  defp event_kind(event), do: inspect(event)

  defp control_command(%{command: command}) when command in [:pause, :resume], do: command
  defp control_command(%{"command" => "pause"}), do: :pause
  defp control_command(%{"command" => "resume"}), do: :resume
  defp control_command(_control_input), do: :unknown
end
