defmodule Cadence.Dashboards.AuthoringDefaults do
  @moduledoc "Bounded, lossless JSON admission for authored dashboard runtime defaults."

  @max_bytes 32_768
  @max_number 9_007_199_254_740_991

  alias Cadence.Dashboards.{DataContext, LimitContext, ScopeContext, TimeContext}

  def validate(defaults) do
    valid? =
      Enum.all?(
        [
          {"time", TimeContext},
          {"scope", ScopeContext},
          {"data", DataContext},
          {"limits", LimitContext}
        ],
        fn {key, module} ->
          case Map.get(defaults, key) do
            nil -> true
            attrs when is_map(attrs) -> module.validate(module.from_map(attrs)) == []
            _ -> false
          end
        end
      )

    if valid?, do: :ok, else: {:error, :invalid_defaults}
  rescue
    _ -> {:error, :invalid_defaults}
  end

  def decode(value) when is_binary(value) and byte_size(value) <= @max_bytes do
    with true <- String.valid?(value),
         {:ok, defaults} when is_map(defaults) <- Jason.decode(value),
         true <- bounded?(defaults, 0) do
      {:ok, defaults}
    else
      _ -> {:error, :invalid_defaults}
    end
  end

  def decode(_), do: {:error, :invalid_defaults}

  def encode(defaults) do
    with {:ok, json} <- Jason.encode(defaults),
         {:ok, _} <- decode(json) do
      {:ok, json}
    else
      _ -> {:error, :invalid_defaults}
    end
  end

  defp bounded?(_, depth) when depth > 8, do: false
  defp bounded?(nil, _), do: true
  defp bounded?(value, _) when is_boolean(value), do: true
  defp bounded?(value, _) when is_number(value), do: abs(value) <= @max_number
  defp bounded?(value, _) when is_binary(value), do: byte_size(value) <= 4096

  defp bounded?(value, depth) when is_list(value),
    do: length(value) <= 100 and Enum.all?(value, &bounded?(&1, depth + 1))

  defp bounded?(value, depth) when is_map(value),
    do:
      map_size(value) <= 64 and
        Enum.all?(value, fn {key, item} ->
          byte_size(key) <= 256 and bounded?(item, depth + 1)
        end)

  defp bounded?(_, _), do: false
end
