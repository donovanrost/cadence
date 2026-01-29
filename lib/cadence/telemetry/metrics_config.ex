defmodule Cadence.Telemetry.MetricsConfig do
  @moduledoc """
  Runtime configuration for telemetry metrics sampling and feature flags.
  """

  @type config_key ::
          :enable_pipeline_timings?
          | :timing_sample_rate
          | :end_to_end_sample_rate
          | :queue_snapshot_interval_ms
          | :enable_process_queue_sampling?

  @default_enable_pipeline_timings? true

  @defaults %{
    enable_pipeline_timings?: @default_enable_pipeline_timings?,
    timing_sample_rate: 0.01,
    end_to_end_sample_rate: 0.01,
    queue_snapshot_interval_ms: 5_000,
    enable_process_queue_sampling?: false
  }

  @env_overrides %{
    enable_pipeline_timings?: "CADENCE_ENABLE_PIPELINE_TIMINGS",
    timing_sample_rate: "CADENCE_TIMING_SAMPLE_RATE",
    end_to_end_sample_rate: "CADENCE_END_TO_END_SAMPLE_RATE",
    queue_snapshot_interval_ms: "CADENCE_QUEUE_SNAPSHOT_INTERVAL_MS",
    enable_process_queue_sampling?: "CADENCE_ENABLE_PROCESS_QUEUE_SAMPLING"
  }

  @bool_values %{
    "true" => true,
    "1" => true,
    "yes" => true,
    "y" => true,
    "false" => false,
    "0" => false,
    "no" => false,
    "n" => false
  }

  @doc """
  Clears cached config values (useful in tests).
  """
  def refresh do
    Enum.each(Map.keys(@defaults), fn key ->
      :persistent_term.erase({__MODULE__, key})
    end)

    :ok
  rescue
    ArgumentError -> :ok
  end

  def enable_pipeline_timings? do
    get_bool(:enable_pipeline_timings?, @defaults.enable_pipeline_timings?)
  end

  def timing_sample_rate do
    get_float(:timing_sample_rate, @defaults.timing_sample_rate)
  end

  def end_to_end_sample_rate do
    get_float(:end_to_end_sample_rate, @defaults.end_to_end_sample_rate)
  end

  def queue_snapshot_interval_ms do
    get_integer(:queue_snapshot_interval_ms, @defaults.queue_snapshot_interval_ms)
  end

  def enable_process_queue_sampling? do
    get_bool(:enable_process_queue_sampling?, @defaults.enable_process_queue_sampling?)
  end

  def timing_sample? do
    enable_pipeline_timings?() and sample?(timing_sample_rate())
  end

  def end_to_end_sample? do
    enable_pipeline_timings?() and sample?(end_to_end_sample_rate())
  end

  @doc """
  Returns true when a sample should be taken for the given rate.
  """
  def sample?(rate) when is_number(rate) do
    cond do
      rate >= 1.0 -> true
      rate <= 0.0 -> false
      true -> :rand.uniform() <= rate
    end
  end

  defp get_bool(key, default) do
    cached(key, fn ->
      env = Map.get(@env_overrides, key)
      config = app_config(key)

      cond do
        is_boolean(config) -> config
        env_value = env && System.get_env(env) -> parse_bool(env_value, default)
        true -> default
      end
    end)
  end

  defp get_float(key, default) do
    cached(key, fn ->
      env = Map.get(@env_overrides, key)
      config = app_config(key)

      cond do
        is_number(config) -> clamp_rate(config)
        env_value = env && System.get_env(env) -> parse_float(env_value, default) |> clamp_rate()
        true -> default
      end
    end)
  end

  defp get_integer(key, default) do
    cached(key, fn ->
      env = Map.get(@env_overrides, key)
      config = app_config(key)

      cond do
        is_integer(config) -> max(config, 0)
        env_value = env && System.get_env(env) -> parse_integer(env_value, default)
        true -> default
      end
    end)
  end

  defp app_config(key) do
    :cadence
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key)
  end

  defp cached(key, fun) do
    case :persistent_term.get({__MODULE__, key}, :undefined) do
      :undefined ->
        value = fun.()
        :persistent_term.put({__MODULE__, key}, value)
        value

      value ->
        value
    end
  end

  defp parse_bool(value, default) when is_binary(value) do
    case Map.fetch(@bool_values, String.downcase(value)) do
      {:ok, parsed} -> parsed
      :error -> default
    end
  end

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> parsed
      :error -> default
    end
  end

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> max(parsed, 0)
      :error -> default
    end
  end

  defp clamp_rate(rate) when is_number(rate) do
    cond do
      rate < 0.0 -> 0.0
      rate > 1.0 -> 1.0
      true -> rate
    end
  end
end
