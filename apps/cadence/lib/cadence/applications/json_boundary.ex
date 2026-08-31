defmodule Cadence.Applications.JSONBoundary do
  @moduledoc """
  The one recursive JSON boundary for generic application-host data.

  The boundary deliberately validates before encoding.  Callers that need to
  retain their DTO's in-memory shape should use `validate/1`; callers crossing
  a JSON transport should use `safe/1` to receive string-keyed JSON values.

  The depth cap applies to structural containers. Scalar leaves may occur at
  the terminal level immediately below the deepest allowed container.
  """

  @max_map_items 64
  @max_list_items 100
  @max_depth 8
  @max_string_bytes 240
  @max_document_bytes 65_536
  @max_json_integer 9_007_199_254_740_991
  @min_json_integer -9_007_199_254_740_991

  @type reason ::
          :depth
          | :map_items
          | :list_items
          | :string
          | :key
          | :number
          | :unsupported
          | :document_bytes
          | :duplicate_key

  @spec validate(term()) :: :ok | {:error, reason()}
  def validate(value) do
    case safe_value(value) do
      {:ok, _safe} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec safe(term()) :: {:ok, term()} | {:error, reason()}
  def safe(value), do: safe_value(value)

  defp safe_value(value) do
    safe_value_result(value)
  rescue
    _exception -> {:error, :unsupported}
  catch
    _kind, _value -> {:error, :unsupported}
  end

  defp safe_value_result(value) do
    with {:ok, safe} <- normalize(value, 0),
         {:ok, encoded} <- Jason.encode(safe),
         true <- byte_size(encoded) <= @max_document_bytes do
      {:ok, safe}
    else
      false -> {:error, :document_bytes}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :unsupported}
    end
  end

  defp normalize(value, depth) when is_list(value) and depth > @max_depth,
    do: {:error, :depth}

  defp normalize(value, depth) when is_map(value) and depth > @max_depth,
    do: {:error, :depth}

  defp normalize(_value, depth) when depth > @max_depth + 1, do: {:error, :depth}
  defp normalize(nil, _depth), do: {:ok, nil}
  defp normalize(value, _depth) when is_boolean(value), do: {:ok, value}

  defp normalize(value, _depth) when is_integer(value) do
    if bounded_integer?(value), do: {:ok, value}, else: {:error, :number}
  end

  defp normalize(value, _depth) when is_float(value) do
    if finite_float?(value), do: {:ok, value}, else: {:error, :number}
  end

  defp normalize(value, _depth) when is_binary(value) do
    if byte_size(value) <= @max_string_bytes and String.valid?(value),
      do: {:ok, value},
      else: {:error, :string}
  end

  defp normalize(%DateTime{} = value, depth), do: normalize(DateTime.to_iso8601(value), depth)

  defp normalize(%NaiveDateTime{} = value, depth),
    do: normalize(NaiveDateTime.to_iso8601(value), depth)

  defp normalize(%_{} = _value, _depth), do: {:error, :unsupported}

  defp normalize(value, depth) when is_list(value),
    do: normalize_list(value, depth, 0, [])

  defp normalize(value, depth) when is_map(value),
    do: normalize_map(value, depth)

  defp normalize(_value, _depth), do: {:error, :unsupported}

  defp normalize_list([], _depth, _count, acc), do: {:ok, Enum.reverse(acc)}

  defp normalize_list(_items, _depth, count, _acc) when count >= @max_list_items,
    do: {:error, :list_items}

  defp normalize_list([item | rest], depth, count, acc) do
    with {:ok, safe_item} <- normalize(item, depth + 1) do
      normalize_list(rest, depth, count + 1, [safe_item | acc])
    end
  end

  defp normalize_list(_improper_list, _depth, _count, _acc), do: {:error, :unsupported}

  defp normalize_map(value, _depth) when map_size(value) > @max_map_items,
    do: {:error, :map_items}

  defp normalize_map(value, depth) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, acc} ->
      with {:ok, json_key} <- normalize_key(key),
           false <- Map.has_key?(acc, json_key),
           {:ok, safe_item} <- normalize(item, depth + 1) do
        {:cont, {:ok, Map.put(acc, json_key, safe_item)}}
      else
        false -> {:halt, {:error, :duplicate_key}}
        {:error, reason} -> {:halt, {:error, reason}}
        _invalid -> {:halt, {:error, :key}}
      end
    end)
  end

  defp normalize_key(key) when is_binary(key) do
    if byte_size(key) <= @max_string_bytes and String.valid?(key),
      do: {:ok, key},
      else: {:error, :key}
  end

  defp normalize_key(key) when is_atom(key), do: normalize_key(Atom.to_string(key))

  defp normalize_key(key) when is_integer(key) do
    if bounded_integer?(key), do: {:ok, Integer.to_string(key)}, else: {:error, :key}
  end

  defp normalize_key(_key), do: {:error, :key}

  defp bounded_integer?(value),
    do: value >= @min_json_integer and value <= @max_json_integer

  defp finite_float?(value) do
    rendered = :erlang.float_to_binary(value, [:short]) |> String.downcase()

    abs(value) <= @max_json_integer and
      rendered not in [
        "nan",
        "+nan",
        "-nan",
        "inf",
        "+inf",
        "-inf",
        "infinity",
        "+infinity",
        "-infinity"
      ]
  rescue
    _error -> false
  end
end
