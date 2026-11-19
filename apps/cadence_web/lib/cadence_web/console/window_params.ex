defmodule CadenceWeb.Console.WindowParams do
  @moduledoc """
  Parses the console's time-window query: `from`, `to` (ISO-8601, default the
  last hour, or `default_span_s:`), `spacecraft_id`, and optionally `max_points` (default 500, at
  most 2000). Windows are capped at 31 days unless `max_span_s: nil` is given.
  """

  @default_span_s 3_600
  @max_span_s 31 * 86_400
  @default_points 500
  @max_points 2_000

  @spec parse(map(), keyword()) :: {:ok, map()} | {:error, {:invalid_params, map()}}
  def parse(params, opts \\ []) do
    now = opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.truncate(:millisecond)

    with {:ok, to} <- time(params, "to", now),
         {:ok, from} <-
           time(
             params,
             "from",
             DateTime.add(to, -Keyword.get(opts, :default_span_s, @default_span_s))
           ),
         :ok <- span(from, to, Keyword.get(opts, :max_span_s, @max_span_s)),
         {:ok, max_points} <- max_points(params, Keyword.get(opts, :max_points, false)) do
      {:ok,
       %{
         from: from,
         to: to,
         max_points: max_points,
         spacecraft_id: blank_to_nil(params["spacecraft_id"])
       }}
    end
  end

  defp time(params, key, default) do
    case params[key] do
      nil ->
        {:ok, default}

      "" ->
        {:ok, default}

      value ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :millisecond)}
          {:error, _} -> invalid(key, "must be an ISO-8601 timestamp")
        end
    end
  end

  defp span(from, to, max_span_s) do
    diff = DateTime.diff(to, from)

    cond do
      diff <= 0 -> invalid("from", "must be before to")
      is_integer(max_span_s) and diff > max_span_s -> invalid("from", "window is too long")
      true -> :ok
    end
  end

  defp max_points(_params, false), do: {:ok, nil}

  defp max_points(params, true) do
    case params["max_points"] do
      nil ->
        {:ok, @default_points}

      value ->
        case Integer.parse(to_string(value)) do
          {n, ""} when n > 0 and n <= @max_points -> {:ok, n}
          _other -> invalid("max_points", "must be an integer from 1 to #{@max_points}")
        end
    end
  end

  defp invalid(key, message), do: {:error, {:invalid_params, %{key => message}}}

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
