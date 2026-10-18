defmodule Cadence.Reads.ApplicationSurfaces.Limits.Pages do
  @moduledoc false
  @numbers ~w(page history_page activation_page points_page spacecraft_page)
  @text ~w(q points_q spacecraft_q spacecraft definition point set severity)
  @aliases %{
    "limit_definition_id" => "definition",
    "limit_definition_version" => "version",
    "point_id" => "point"
  }
  @keys @numbers ++ @text ++ ["version"]

  def parse(params) when is_map(params) do
    with {:ok, params} <- aliases(params),
         true <- Enum.all?(Map.keys(params), &(&1 in @keys)),
         {:ok, numbers} <- numbers(params),
         true <-
           Enum.all?(
             @text,
             &(is_nil(params[&1]) or
                 (is_binary(params[&1]) and String.valid?(params[&1]) and
                    byte_size(params[&1]) <= 240))
           ),
         {:ok, version} <- optional_version(params["version"]),
         true <- Map.get(params, "severity", "") in ["", "red", "yellow", "blue", "green"] do
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
    do: base <> "?" <> URI.encode_query(Map.reject(query, fn {_, v} -> v in [nil, ""] end))

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
    %{items: Enum.slice(items, (page - 1) * 25, 25), total_count: total, page: page}
  end

  def stamp(nil), do: nil
  def stamp(time), do: DateTime.to_iso8601(time)

  defp aliases(params) do
    Enum.reduce_while(@aliases, {:ok, params}, fn {old, new}, {:ok, acc} ->
      cond do
        not Map.has_key?(acc, old) -> {:cont, {:ok, acc}}
        Map.has_key?(acc, new) and to_string(acc[old]) != to_string(acc[new]) -> {:halt, :error}
        true -> {:cont, {:ok, acc |> Map.put(new, acc[old]) |> Map.delete(old)}}
      end
    end)
  end

  defp numbers(params) do
    Enum.reduce_while(@numbers, {:ok, %{}}, fn key, {:ok, acc} ->
      case number(params[key] || 1) do
        {:ok, n} -> {:cont, {:ok, Map.put(acc, key, n)}}
        _ -> {:halt, :error}
      end
    end)
  end

  defp optional_version(n) when n in [nil, ""], do: {:ok, nil}
  defp optional_version(n), do: number(n)
  defp number(n) when is_integer(n) and n in 1..100_000, do: {:ok, n}

  defp number(n) when is_binary(n) and byte_size(n) <= 6 do
    case Integer.parse(n) do
      {n, ""} -> number(n)
      _ -> :error
    end
  end

  defp number(_), do: :error
end
