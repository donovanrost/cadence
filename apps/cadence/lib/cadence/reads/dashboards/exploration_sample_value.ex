defmodule Cadence.Reads.Dashboards.ExplorationSampleValue do
  @moduledoc "Bounded literal display of physical values; never inspects arbitrary runtime terms."
  @max_bytes 4096
  @max_nodes 64

  def project(nil), do: state("not_recorded")

  def project(value) when is_binary(value) do
    cond do
      byte_size(value) > @max_bytes -> state("limited")
      String.valid?(value) -> json(value)
      byte_size(value) <= div(@max_bytes, 2) -> ready(Base.encode16(value, case: :lower), "hex")
      true -> state("limited")
    end
  end

  def project(value), do: json(value)

  defp json(value) do
    with {:ok, _remaining} <- bounded(value, 0, @max_nodes),
         {:ok, encoded} <- Jason.encode(value),
         true <- byte_size(encoded) <= @max_bytes do
      ready(encoded, "json")
    else
      :limited -> state("limited")
      false -> state("limited")
      _ -> state("unsupported")
    end
  rescue
    _ -> state("unsupported")
  end

  defp bounded(_value, depth, remaining) when depth > 4 or remaining <= 0, do: :limited

  defp bounded(value, _depth, remaining) when value in [nil, true, false],
    do: {:ok, remaining - 1}

  defp bounded(value, _depth, remaining) when is_number(value) do
    if :erlang.external_size(value) <= 2048, do: {:ok, remaining - 1}, else: :limited
  end

  defp bounded(value, _depth, remaining) when is_binary(value) do
    cond do
      byte_size(value) > @max_bytes -> :limited
      String.valid?(value) -> {:ok, remaining - 1}
      true -> :unsupported
    end
  end

  defp bounded(%_struct{}, _depth, _remaining), do: :unsupported

  defp bounded(value, depth, remaining) when is_map(value) and map_size(value) <= @max_nodes do
    Enum.reduce_while(value, {:ok, remaining - 1}, fn {key, value}, {:ok, remaining} ->
      with true <- is_binary(key) or is_atom(key),
           key = to_string(key),
           true <- byte_size(key) <= 128,
           {:ok, remaining} <- bounded(key, depth + 1, remaining),
           {:ok, remaining} <- bounded(value, depth + 1, remaining) do
        {:cont, {:ok, remaining}}
      else
        :limited -> {:halt, :limited}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  defp bounded(value, _depth, _remaining) when is_map(value), do: :limited

  defp bounded(value, depth, remaining) when is_list(value) do
    Enum.reduce_while(value, {:ok, remaining - 1}, fn value, {:ok, remaining} ->
      case bounded(value, depth + 1, remaining) do
        {:ok, remaining} -> {:cont, {:ok, remaining}}
        error -> {:halt, error}
      end
    end)
  end

  defp bounded(_value, _depth, _remaining), do: :unsupported
  defp ready(text, format), do: %{state: "ready", text: text, format: format}
  defp state(state), do: %{state: state, text: nil, format: nil}
end
