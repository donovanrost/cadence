defmodule Cadence.Platform.RedactedJson do
  @moduledoc "Converts evidence to JSON-safe values while redacting credential material."

  alias Cadence.Persistence.JsonDocument

  @sensitive_key_fragments ~w(api_key authorization credential password private_key secret token)

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
