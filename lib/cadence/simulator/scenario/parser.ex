defmodule Cadence.Simulator.Scenario.Parser do
  @moduledoc """
  Parses YAML scenario files for simulation.

  ## Scenario Format

  ```yaml
  version: "1.0"
  name: "Battery Low Voltage Test"
  description: "Tests battery voltage alarm triggering"
  target_id: "SIM-1"
  step_rate_hz: 1.0

  baseline:
    HEALTH.cpu_temp: 25.0
    HEALTH.battery_voltage: 14.5

  timeline:
    - step: 0
      hold_steps: 10
      description: "Normal operation"

    - step: 10
      inject:
        HEALTH.battery_voltage: 13.0
      description: "Voltage drops to warning"

    - step: 20
      end: true
  ```
  """

  require Logger

  @type scenario :: %{
          version: String.t(),
          name: String.t(),
          description: String.t() | nil,
          target_id: String.t(),
          step_rate_hz: float(),
          baseline: %{String.t() => number() | String.t()},
          timeline: [timeline_event()]
        }

  @type timeline_event :: %{
          step: non_neg_integer(),
          hold_steps: non_neg_integer() | nil,
          inject: %{String.t() => injection_value()} | nil,
          description: String.t() | nil,
          end: boolean() | nil
        }

  @type injection_value :: number() | String.t() | injection_pattern()

  @type injection_pattern :: %{
          type: :ramp | :spike | :sine,
          from: number(),
          to: number(),
          steps: non_neg_integer(),
          noise: number() | nil
        }

  @doc """
  Parses a scenario from a YAML file path.
  """
  @spec parse_file(String.t()) :: {:ok, scenario()} | {:error, term()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} ->
        parse_string(content)

      {:error, reason} ->
        {:error, {:file_read_error, path, reason}}
    end
  end

  @doc """
  Parses a scenario from a YAML string.
  """
  @spec parse_string(String.t()) :: {:ok, scenario()} | {:error, term()}
  def parse_string(yaml_content) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, data} ->
        validate_and_transform(data)

      {:error, reason} ->
        {:error, {:yaml_parse_error, reason}}
    end
  end

  defp validate_and_transform(data) when is_map(data) do
    with {:ok, version} <- get_required(data, "version"),
         {:ok, name} <- get_required(data, "name"),
         {:ok, target_id} <- get_required(data, "target_id"),
         {:ok, baseline} <- parse_baseline(data),
         {:ok, timeline} <- parse_timeline(data) do
      scenario = %{
        version: version,
        name: name,
        description: Map.get(data, "description"),
        target_id: target_id,
        step_rate_hz: Map.get(data, "step_rate_hz", 1.0),
        baseline: baseline,
        timeline: timeline
      }

      {:ok, scenario}
    end
  end

  defp validate_and_transform(_data) do
    {:error, :invalid_yaml_structure}
  end

  defp get_required(data, key) do
    case Map.get(data, key) do
      nil -> {:error, {:missing_required_field, key}}
      value -> {:ok, value}
    end
  end

  defp parse_baseline(data) do
    case Map.get(data, "baseline", %{}) do
      baseline when is_map(baseline) ->
        # Ensure all keys are strings (qualified item names)
        normalized =
          baseline
          |> Enum.map(fn {k, v} -> {to_string(k), v} end)
          |> Map.new()

        {:ok, normalized}

      _ ->
        {:error, {:invalid_baseline, "baseline must be a map"}}
    end
  end

  defp parse_timeline(data) do
    case Map.get(data, "timeline", []) do
      timeline when is_list(timeline) ->
        events =
          timeline
          |> Enum.with_index()
          |> Enum.map(fn {event, idx} -> parse_timeline_event(event, idx) end)

        errors = Enum.filter(events, &match?({:error, _}, &1))

        if Enum.empty?(errors) do
          sorted_events =
            events
            |> Enum.map(fn {:ok, e} -> e end)
            |> Enum.sort_by(& &1.step)

          {:ok, sorted_events}
        else
          {:error, {:timeline_errors, Enum.map(errors, fn {:error, e} -> e end)}}
        end

      _ ->
        {:error, {:invalid_timeline, "timeline must be a list"}}
    end
  end

  defp parse_timeline_event(event, index) when is_map(event) do
    case Map.get(event, "step") do
      nil ->
        {:error, {:missing_step, index}}

      step when is_integer(step) and step >= 0 ->
        parsed = %{
          step: step,
          hold_steps: Map.get(event, "hold_steps"),
          inject: parse_injections(Map.get(event, "inject")),
          description: Map.get(event, "description"),
          end: Map.get(event, "end", false)
        }

        {:ok, parsed}

      invalid ->
        {:error, {:invalid_step, index, invalid}}
    end
  end

  defp parse_timeline_event(_event, index) do
    {:error, {:invalid_event_format, index}}
  end

  defp parse_injections(nil), do: nil

  defp parse_injections(injections) when is_map(injections) do
    injections
    |> Enum.map(fn {key, value} ->
      {to_string(key), parse_injection_value(value)}
    end)
    |> Map.new()
  end

  defp parse_injections(_), do: nil

  # Simple scalar value
  defp parse_injection_value(value) when is_number(value) or is_binary(value) do
    value
  end

  # Pattern-based injection (ramp, spike, etc.)
  defp parse_injection_value(%{"type" => type} = pattern) when is_map(pattern) do
    %{
      type: parse_pattern_type(type),
      from: Map.get(pattern, "from"),
      to: Map.get(pattern, "to"),
      steps: Map.get(pattern, "steps", 10),
      noise: Map.get(pattern, "noise", 0.0)
    }
  end

  defp parse_injection_value(value) do
    Logger.warning("Unknown injection value format: #{inspect(value)}, using as-is")
    value
  end

  defp parse_pattern_type("ramp"), do: :ramp
  defp parse_pattern_type("spike"), do: :spike
  defp parse_pattern_type("sine"), do: :sine
  defp parse_pattern_type(other), do: String.to_atom(other)
end
