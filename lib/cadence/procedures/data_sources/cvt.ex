defmodule Cadence.Procedures.DataSources.CVT do
  @moduledoc """
  Data source backed by the Current Value Table.

  This is the primary real-time data source for spacecraft telemetry.
  The CVT stores the most recent value for each telemetry point with
  sub-second update latency.

  ## Path Format

  Telemetry paths follow the format: `TARGET.PACKET.item`

  - `SC-001.EPS.battery_voltage` - Explicit target
  - `EPS.battery_voltage` - Uses context target_id
  - `target.EPS.battery_voltage` - Resolved by TelemetryResolver

  Note: The `target.` prefix should be resolved before calling this module.
  This module expects either explicit targets or context-based resolution.

  ## Quality Determination

  Quality is determined by:
  - `:good` - Value exists and is fresh (< stale_threshold)
  - `:stale` - Value exists but older than threshold
  - `:bad` - Limits state is :red
  - `:unknown` - Value not found

  ## Subscriptions

  Subscriptions are handled via Phoenix.PubSub. The CVT broadcasts
  updates on the topic `mission:<mission_id>:telemetry`.
  """

  @behaviour Cadence.Procedures.DataSources.DataSource

  alias Cadence.Procedures.DataSources.DataSource
  alias Cadence.Runtime.Telemetry.CurrentValueTable, as: CVTStore
  alias Cadence.Telemetry.Dictionary

  # Default stale threshold: 30 seconds
  @default_stale_threshold_ms 30_000

  # ─────────────────────────────────────────────────────────────
  # DataSource Callbacks
  # ─────────────────────────────────────────────────────────────

  @impl DataSource
  def get_value(item_path, context, opts \\ []) do
    mission_id = context[:mission_id]
    default_target = context[:target_id]
    stale_threshold = Keyword.get(opts, :stale_threshold_ms, @default_stale_threshold_ms)
    default_value = Keyword.get(opts, :default)

    case parse_item_path(item_path, default_target) do
      {:ok, target_id, packet_name, item_name} ->
        fetch_from_cvt(
          mission_id,
          target_id,
          packet_name,
          item_name,
          item_path,
          stale_threshold,
          default_value
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl DataSource
  def evaluate_condition(expression, context) do
    # Extract all telemetry references from the expression
    items = extract_telemetry_items(expression)

    # Fetch all values
    case build_bindings(items, context) do
      {:ok, bindings} ->
        evaluate_with_bindings(expression, bindings)

      {:error, {:missing_values, missing}} ->
        {:error, {:missing_values, resolve_missing_values(items, context, missing)}}

      {:error, _} = error ->
        error
    end
  end

  @impl DataSource
  def subscribe(item_path, context, callback_pid) do
    mission_id = context[:mission_id]
    topic = "mission:#{mission_id}:telemetry"

    # Subscribe to the mission telemetry topic
    Phoenix.PubSub.subscribe(Cadence.PubSub, topic)

    {:ok,
     %{
       id: Ecto.UUID.generate(),
       item_path: item_path,
       source_type: :cvt,
       pid: callback_pid,
       topic: topic,
       mission_id: mission_id
     }}
  end

  @impl DataSource
  def unsubscribe(%{topic: topic}) do
    Phoenix.PubSub.unsubscribe(Cadence.PubSub, topic)
    :ok
  end

  def unsubscribe(_), do: :ok

  @impl DataSource
  def list_items(context, filter \\ %{}) do
    mission_id = context[:mission_id]
    prefix = Map.get(filter, :prefix)
    limit = Map.get(filter, :limit, 1000)

    # Get items from telemetry dictionary
    # Note: Dictionary module may not exist yet, fallback to empty list
    case list_dictionary_items(mission_id, filter) do
      {:ok, items} ->
        filtered =
          items
          |> maybe_filter_prefix(prefix)
          |> Enum.take(limit)
          |> Enum.map(&to_item_metadata/1)

        {:ok, filtered}

      {:error, _} = error ->
        error
    end
  rescue
    # Dictionary might not exist or be accessible
    _ -> {:ok, []}
  end

  @impl DataSource
  def validate_item(item_path, context) do
    default_target = context[:target_id]

    case parse_item_path(item_path, default_target) do
      {:ok, _target_id, _packet_name, _item_name} ->
        # For now, just validate the path format is correct
        # Full dictionary validation would require checking against mission's telemetry dictionary
        :ok

      {:error, _} ->
        {:error, :invalid_format}
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Private Functions
  # ─────────────────────────────────────────────────────────────

  defp parse_item_path(item_path, default_target) do
    parts = String.split(item_path, ".")

    case parts do
      [target, packet, item] ->
        {:ok, target, packet, item}

      [packet, item] when not is_nil(default_target) ->
        {:ok, default_target, packet, item}

      [_packet, _item] when is_nil(default_target) ->
        {:error, {:no_target, "Path #{item_path} requires target context"}}

      _ ->
        {:error, {:invalid_path_format, item_path}}
    end
  end

  defp fetch_from_cvt(
         mission_id,
         target_id,
         packet_name,
         item_name,
         raw_path,
         stale_threshold,
         default_value
       ) do
    case CVTStore.get(mission_id, target_id, packet_name, item_name) do
      {:ok, %{value: value, received_time: timestamp, limits_state: limits_state} = _entry} ->
        quality = determine_quality(timestamp, limits_state, stale_threshold)

        {:ok,
         %{
           value: value,
           timestamp: timestamp,
           quality: quality,
           source: %{
             source_type: :cvt,
             source_id: mission_id,
             raw_path: raw_path
           }
         }}

      {:error, :not_found} when not is_nil(default_value) ->
        {:ok,
         %{
           value: default_value,
           timestamp: DateTime.utc_now(),
           quality: :unknown,
           source: %{
             source_type: :cvt,
             source_id: mission_id,
             raw_path: raw_path
           }
         }}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  rescue
    # CVT table might not exist
    ArgumentError -> {:error, :cvt_not_available}
  end

  defp determine_quality(timestamp, limits_state, stale_threshold) do
    age_ms = DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)

    cond do
      limits_state == :red -> :bad
      age_ms > stale_threshold -> :stale
      true -> :good
    end
  end

  defp extract_telemetry_items(expression) do
    # Extract paths like TARGET.PACKET.item or PACKET.item from expressions
    # Pattern matches dotted identifiers (2 or 3 parts)
    ~r/\b([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*){1,2})\b/
    |> Regex.scan(expression)
    |> Enum.map(fn [_, match] -> match end)
    |> Enum.uniq()
    |> Enum.filter(&valid_telemetry_path?/1)
  end

  defp valid_telemetry_path?(path) do
    parts = String.split(path, ".")
    # Must be 2 or 3 parts, and not look like a keyword
    length(parts) in [2, 3] and not keyword_like?(path)
  end

  defp keyword_like?(path) do
    # Filter out things that look like language keywords or operators
    String.downcase(path) in ["true", "false", "nil", "and", "or", "not"]
  end

  defp do_evaluate_condition(expression, bindings) do
    # Build a substitution map from paths to their values
    substituted =
      Enum.reduce(bindings, expression, fn {path, reading}, expr ->
        value = reading.value
        value_str = if is_binary(value), do: "\"#{value}\"", else: to_string(value)
        String.replace(expr, path, value_str)
      end)

    # Parse and evaluate the resulting expression
    case parse_boolean_expression(substituted) do
      {:ok, result} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  defp parse_boolean_expression(expr) do
    expr = String.trim(expr)

    cond do
      expr == "true" -> {:ok, true}
      expr == "false" -> {:ok, false}
      String.contains?(expr, " and ") -> parse_and_expression(expr)
      String.contains?(expr, " or ") -> parse_or_expression(expr)
      true -> parse_comparison_expression(expr)
    end
  end

  defp parse_and_expression(expr) do
    parts = String.split(expr, " and ")

    Enum.reduce_while(parts, {:ok, true}, fn part, {:ok, _} ->
      case parse_boolean_expression(part) do
        {:ok, true} -> {:cont, {:ok, true}}
        {:ok, false} -> {:halt, {:ok, false}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp parse_or_expression(expr) do
    parts = String.split(expr, " or ")

    Enum.reduce_while(parts, {:ok, false}, fn part, {:ok, _} ->
      case parse_boolean_expression(part) do
        {:ok, true} -> {:halt, {:ok, true}}
        {:ok, false} -> {:cont, {:ok, false}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @comparison_operators ~w(>= <= != == > <)

  defp parse_comparison_expression(expr) do
    case find_operator(expr) do
      {operator, left, right} ->
        left_val = parse_numeric_value(String.trim(left))
        right_val = parse_numeric_value(String.trim(right))

        if is_nil(left_val) or is_nil(right_val) do
          {:error, {:parse_error, "Could not parse values in: #{expr}"}}
        else
          {:ok, compare(left_val, operator, right_val)}
        end

      nil ->
        {:error, {:parse_error, "No comparison operator found in: #{expr}"}}
    end
  end

  defp find_operator(expr) do
    Enum.find_value(@comparison_operators, fn op ->
      case String.split(expr, op, parts: 2) do
        [left, right] when left != "" and right != "" ->
          {op, left, right}

        _ ->
          nil
      end
    end)
  end

  defp parse_numeric_value(str) do
    str = String.trim(str)

    case parse_boolean_literal(str) do
      {:ok, value} -> value
      :error -> parse_numeric_or_string(str)
    end
  end

  defp build_bindings(items, context) do
    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, acc} ->
      case get_value(item, context, []) do
        {:ok, reading} ->
          {:cont, {:ok, Map.put(acc, item, reading)}}

        {:error, :not_found} ->
          {:halt, {:error, {:missing_values, [item]}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp evaluate_with_bindings(expression, bindings) do
    case do_evaluate_condition(expression, bindings) do
      {:ok, result} ->
        {:ok,
         %{
           result: result,
           evaluated_at: DateTime.utc_now(),
           bindings: bindings
         }}

      {:error, _} = error ->
        error
    end
  end

  defp resolve_missing_values(items, context, missing) do
    all_missing =
      Enum.filter(items, fn item ->
        case get_value(item, context, []) do
          {:ok, _} -> false
          {:error, _} -> true
        end
      end)

    if all_missing == [], do: missing, else: all_missing
  end

  defp parse_boolean_literal("true"), do: {:ok, true}
  defp parse_boolean_literal("false"), do: {:ok, false}
  defp parse_boolean_literal(_), do: :error

  defp parse_numeric_or_string(str) do
    case parse_quoted_string(str) do
      {:ok, value} ->
        value

      :error ->
        case Float.parse(str) do
          {num, ""} -> num
          _ -> parse_integer_or_nil(str)
        end
    end
  end

  defp parse_quoted_string(str) do
    if String.starts_with?(str, "\"") and String.ends_with?(str, "\"") do
      {:ok, String.slice(str, 1..-2//1)}
    else
      :error
    end
  end

  defp parse_integer_or_nil(str) do
    case Integer.parse(str) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp compare(left, ">=", right) when is_number(left) and is_number(right), do: left >= right
  defp compare(left, "<=", right) when is_number(left) and is_number(right), do: left <= right
  defp compare(left, ">", right) when is_number(left) and is_number(right), do: left > right
  defp compare(left, "<", right) when is_number(left) and is_number(right), do: left < right
  defp compare(left, "==", right), do: left == right
  defp compare(left, "!=", right), do: left != right
  defp compare(_, _, _), do: false

  defp maybe_filter_prefix(items, nil), do: items

  defp maybe_filter_prefix(items, prefix) do
    Enum.filter(items, fn item ->
      path = item[:path] || item["path"] || ""
      String.starts_with?(path, prefix)
    end)
  end

  defp to_item_metadata(item) do
    %{
      path: item[:path] || item["path"],
      name: item[:name] || item["name"],
      type: item[:type] || item["type"],
      unit: item[:unit] || item["unit"],
      description: item[:description] || item["description"]
    }
  end

  # Try to get items from Dictionary module, with fallback for when module doesn't exist
  defp list_dictionary_items(mission_id, filter) do
    # Check if the Dictionary module exists and has the function
    if Code.ensure_loaded?(Dictionary) and function_exported?(Dictionary, :list_items, 2) do
      Dictionary.list_items(mission_id, filter)
    else
      # Dictionary module not available, return empty list
      {:ok, []}
    end
  end
end
