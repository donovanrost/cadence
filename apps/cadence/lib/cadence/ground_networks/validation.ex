defmodule Cadence.GroundNetworks.Validation do
  @moduledoc false

  alias Cadence.Persistence.JsonDocument

  @sensitive_key_fragments ~w(api_key authorization credential password private_key secret token)

  @spec required_string(map(), binary()) :: {:ok, binary()} | {:error, term()}
  def required_string(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> malformed(key)
    end
  end

  @spec optional_string(map(), binary()) :: {:ok, binary() | nil} | {:error, term()}
  def optional_string(map, key) do
    case map[key] do
      nil -> {:ok, nil}
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> malformed(key)
    end
  end

  @spec object(map(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def object(map, key, default \\ %{}) do
    case Map.get(map, key, default) do
      value when is_map(value) -> {:ok, value}
      _other -> malformed(key)
    end
  end

  @spec string_list(map(), binary(), list()) :: {:ok, [binary()]} | {:error, term()}
  def string_list(map, key, default \\ []) do
    case Map.get(map, key, default) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")),
          do: {:ok, values},
          else: malformed(key)

      _other ->
        malformed(key)
    end
  end

  @spec positive_integer(map(), binary()) :: {:ok, pos_integer()} | {:error, term()}
  def positive_integer(map, key) do
    case map[key] do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _other -> malformed(key)
    end
  end

  @spec non_negative_integer(map(), binary(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def non_negative_integer(map, key, default \\ 0) do
    case Map.get(map, key, default) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _other -> malformed(key)
    end
  end

  @spec boolean(map(), binary(), boolean()) :: {:ok, boolean()} | {:error, term()}
  def boolean(map, key, default \\ false) do
    case Map.get(map, key, default) do
      value when is_boolean(value) -> {:ok, value}
      _other -> malformed(key)
    end
  end

  @spec datetime(map(), binary()) :: {:ok, DateTime.t()} | {:error, term()}
  def datetime(map, key) do
    case map[key] do
      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          _error -> malformed(key)
        end

      _other ->
        malformed(key)
    end
  end

  @spec member(map(), binary(), map()) :: {:ok, term()} | {:error, term()}
  def member(map, key, values) when is_map(values) do
    case Map.fetch(values, map[key]) do
      {:ok, value} -> {:ok, value}
      :error -> malformed(key)
    end
  end

  @spec malformed(binary() | atom()) :: {:error, {:malformed_provider_response, term()}}
  def malformed(field), do: {:error, {:malformed_provider_response, field}}

  @doc "Converts external evidence to JSON-safe values and redacts credential material."
  @spec sanitize(term()) :: map()
  def sanitize(value) do
    case value |> JsonDocument.encode() |> redact() do
      encoded when is_map(encoded) -> encoded
      encoded -> %{"value" => encoded}
    end
  end

  defp redact(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      key = to_string(key)

      if sensitive_key?(key) do
        {key, "[REDACTED]"}
      else
        {key, redact(value)}
      end
    end)
  end

  defp redact(values) when is_list(values), do: Enum.map(values, &redact/1)
  defp redact(value), do: value

  defp sensitive_key?(key) do
    normalized = String.downcase(key)

    not String.ends_with?(normalized, "_ref") and
      Enum.any?(@sensitive_key_fragments, &String.contains?(normalized, &1))
  end
end
