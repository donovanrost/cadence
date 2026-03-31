defmodule CadenceSimulator.Scenario.Parser do
  @moduledoc """
  Parses YAML scenario files for deterministic simulator runs.
  """

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

  @spec parse_file(String.t()) :: {:ok, scenario()} | {:error, term()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse_string(content)
      {:error, reason} -> {:error, {:file_read_error, path, reason}}
    end
  end

  @spec parse_string(String.t()) :: {:ok, scenario()} | {:error, term()}
  def parse_string(yaml_content) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, data} -> validate_and_transform(data)
      {:error, reason} -> {:error, {:yaml_parse_error, reason}}
    end
  end

  defp validate_and_transform(data) when is_map(data) do
    with {:ok, version} <- get_required(data, "version"),
         {:ok, name} <- get_required(data, "name"),
         {:ok, target_id} <- get_required(data, "target_id"),
         {:ok, baseline} <- parse_baseline(data),
         {:ok, timeline} <- parse_timeline(data) do
      {:ok,
       %{
         version: version,
         name: name,
         description: Map.get(data, "description"),
         target_id: target_id,
         step_rate_hz: Map.get(data, "step_rate_hz", 1.0),
         baseline: baseline,
         timeline: timeline
       }}
    end
  end

  defp validate_and_transform(_data), do: {:error, :invalid_yaml_structure}

  defp get_required(data, key) do
    case Map.get(data, key) do
      nil -> {:error, {:missing_required_field, key}}
      value -> {:ok, value}
    end
  end

  defp parse_baseline(data) do
    case Map.get(data, "baseline", %{}) do
      baseline when is_map(baseline) ->
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
    timeline = Map.get(data, "timeline", [])

    if is_list(timeline) do
      parse_timeline_list(timeline)
    else
      {:error, {:invalid_timeline, "timeline must be a list"}}
    end
  end

  defp parse_timeline_list(timeline) do
    events =
      timeline
      |> Enum.with_index()
      |> Enum.map(fn {event, idx} -> parse_timeline_event(event, idx) end)

    case timeline_errors(events) do
      [] -> {:ok, sorted_timeline(events)}
      errors -> {:error, {:timeline_errors, errors}}
    end
  end

  defp timeline_errors(events) do
    Enum.flat_map(events, fn
      {:error, error} -> [error]
      _ -> []
    end)
  end

  defp sorted_timeline(events) do
    events
    |> Enum.flat_map(fn
      {:ok, event} -> [event]
      _ -> []
    end)
    |> Enum.sort_by(& &1.step)
  end

  defp parse_timeline_event(event, index) when is_map(event) do
    case Map.get(event, "step") do
      step when is_integer(step) and step >= 0 ->
        {:ok,
         %{
           step: step,
           hold_steps: Map.get(event, "hold_steps"),
           inject: parse_injections(Map.get(event, "inject")),
           description: Map.get(event, "description"),
           end: Map.get(event, "end", false)
         }}

      nil ->
        {:error, {:missing_step, index}}

      invalid ->
        {:error, {:invalid_step, index, invalid}}
    end
  end

  defp parse_timeline_event(_event, index), do: {:error, {:invalid_event_format, index}}

  defp parse_injections(nil), do: nil

  defp parse_injections(injections) when is_map(injections) do
    injections
    |> Enum.map(fn {key, value} ->
      {to_string(key), parse_injection_value(value)}
    end)
    |> Map.new()
  end

  defp parse_injections(_), do: nil

  defp parse_injection_value(value) when is_number(value) or is_binary(value), do: value

  defp parse_injection_value(%{"type" => type} = pattern) when is_map(pattern) do
    %{
      type: normalize_pattern_type(type),
      from: Map.get(pattern, "from", 0.0),
      to: Map.get(pattern, "to", Map.get(pattern, "from", 0.0)),
      steps: Map.get(pattern, "steps", 10),
      noise: Map.get(pattern, "noise")
    }
  end

  defp parse_injection_value(%{type: type} = pattern) when is_map(pattern) do
    %{
      type: normalize_pattern_type(type),
      from: Map.get(pattern, :from, 0.0),
      to: Map.get(pattern, :to, Map.get(pattern, :from, 0.0)),
      steps: Map.get(pattern, :steps, 10),
      noise: Map.get(pattern, :noise)
    }
  end

  defp parse_injection_value(value), do: value

  defp normalize_pattern_type(type) when type in [:ramp, :spike, :sine], do: type
  defp normalize_pattern_type("ramp"), do: :ramp
  defp normalize_pattern_type("spike"), do: :spike
  defp normalize_pattern_type("sine"), do: :sine
  defp normalize_pattern_type(_), do: :ramp
end
