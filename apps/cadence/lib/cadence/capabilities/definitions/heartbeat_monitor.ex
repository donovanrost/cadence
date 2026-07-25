defmodule Cadence.Capabilities.Definitions.HeartbeatMonitor do
  @moduledoc false

  alias Cadence.Capabilities.{Descriptor, ValidationContext}

  @spec descriptor() :: Descriptor.t()
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

  @spec validate_config(term(), ValidationContext.t()) :: :ok | {:error, term()}
  def validate_config(configuration, %ValidationContext{}) do
    with {:ok, normalized_configuration} <- normalize_config(configuration) do
      validate_interval(normalized_configuration.heartbeat_interval_ms)
    end
  end

  @spec normalize_config(term()) :: {:ok, map()} | {:error, term()}
  def normalize_config(%{heartbeat_interval_ms: heartbeat_interval_ms}) do
    {:ok, %{heartbeat_interval_ms: heartbeat_interval_ms}}
  end

  def normalize_config(%{"heartbeat_interval_ms" => heartbeat_interval_ms}) do
    {:ok, %{heartbeat_interval_ms: heartbeat_interval_ms}}
  end

  def normalize_config(configuration) do
    {:error, {:unsupported_heartbeat_monitor_configuration, configuration}}
  end

  defp validate_interval(interval_ms) when is_integer(interval_ms) and interval_ms > 0, do: :ok
  defp validate_interval(interval_ms), do: {:error, {:invalid_heartbeat_interval_ms, interval_ms}}
end
