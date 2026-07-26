defmodule Cadence.Capabilities.Definitions.PacketCounter do
  @moduledoc false

  alias Cadence.Capabilities.{Descriptor, ValidationContext}

  @spec descriptor() :: Descriptor.t()
  def descriptor do
    Descriptor.new(%{
      family_key: :packet_counter,
      version: 1,
      kind: :managed_application,
      supported_scopes: [:mission, :source_endpoint],
      input_stages: [:space_packet],
      partition_affinity: :source_endpoint,
      config_schema: nil,
      emitted_record_kinds: [],
      emitted_action_kinds: [:schedule_timer, :cancel_timer],
      replay_mode: :deterministic,
      state_mode: :stateful
    })
  end

  @spec validate_config(term(), ValidationContext.t()) :: :ok | {:error, term()}
  def validate_config(configuration, %ValidationContext{}) do
    with {:ok, normalized_configuration} <- normalize_config(configuration),
         :ok <- validate_metric_name(normalized_configuration.metric_name) do
      validate_flush_interval(normalized_configuration.flush_interval_ms)
    end
  end

  @spec normalize_config(term()) :: {:ok, map()} | {:error, term()}
  def normalize_config(%{metric_name: metric_name, flush_interval_ms: flush_interval_ms}) do
    {:ok, %{metric_name: metric_name, flush_interval_ms: flush_interval_ms}}
  end

  def normalize_config(%{
        "metric_name" => metric_name,
        "flush_interval_ms" => flush_interval_ms
      }) do
    {:ok, %{metric_name: metric_name, flush_interval_ms: flush_interval_ms}}
  end

  def normalize_config(configuration) do
    {:error, {:unsupported_packet_counter_configuration, configuration}}
  end

  defp validate_metric_name(metric_name) when is_binary(metric_name) and metric_name != "",
    do: :ok

  defp validate_metric_name(metric_name), do: {:error, {:invalid_metric_name, metric_name}}

  defp validate_flush_interval(flush_interval_ms)
       when is_integer(flush_interval_ms) and flush_interval_ms > 0,
       do: :ok

  defp validate_flush_interval(flush_interval_ms),
    do: {:error, {:invalid_flush_interval_ms, flush_interval_ms}}
end
