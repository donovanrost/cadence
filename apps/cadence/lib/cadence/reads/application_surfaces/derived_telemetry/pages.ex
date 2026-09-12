defmodule Cadence.Reads.ApplicationSurfaces.DerivedTelemetry.Pages do
  @moduledoc false
  @numbers ~w(page history_page values_page sources_page spacecraft_page)
  @text ~w(q values_q definition spacecraft spacecraft_q)
  @keys @numbers ++ @text ++ ["version"]
  def parse(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @keys)),
         {:ok, numbers} <- numbers(params),
         true <-
           Enum.all?(
             @text,
             &(is_nil(params[&1]) or (is_binary(params[&1]) and byte_size(params[&1]) <= 240))
           ),
         {:ok, version} <- optional_version(params["version"]) do
      {:ok,
       numbers
       |> Map.merge(Map.new(@text, &{&1, params[&1] || ""}))
       |> Map.put("version", version)}
    else
      _ -> {:error, :invalid_application_surface_query}
    end
  end

  def parse(_), do: {:error, :invalid_application_surface_query}

  def href(base, query),
    do: base <> "?" <> URI.encode_query(Map.reject(query, fn {_, value} -> is_nil(value) end))

  def envelope(%{items: items, page: page, total_count: total}, base, query, key) do
    %{
      "items" => items,
      "page" => page,
      "total_count" => total,
      "page_size" => 25,
      "previous_href" => if(page > 1, do: href(base, Map.put(query, key, page - 1))),
      "next_href" => if(page * 25 < total, do: href(base, Map.put(query, key, page + 1)))
    }
  end

  def slice(items, requested) do
    total = length(items)
    page = min(requested, max(1, ceil(total / 25)))
    %{items: Enum.slice(items, (page - 1) * 25, 25), page: page, total_count: total}
  end

  defp numbers(params) do
    Enum.reduce_while(@numbers, {:ok, %{}}, fn key, {:ok, acc} ->
      case number(params[key] || 1) do
        {:ok, n} -> {:cont, {:ok, Map.put(acc, key, n)}}
        _ -> {:halt, :error}
      end
    end)
  end

  defp optional_version(value) when value in [nil, ""], do: {:ok, nil}
  defp optional_version(value), do: number(value)
  defp number(n) when is_integer(n) and n in 1..100_000, do: {:ok, n}

  defp number(n) when is_binary(n) and byte_size(n) <= 6 do
    case Integer.parse(n) do
      {n, ""} -> number(n)
      _ -> :error
    end
  end

  defp number(_), do: :error
end
