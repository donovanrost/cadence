defmodule Cadence.Reads.ApplicationSurfaces.TelemetryDecom.PacketPages do
  @moduledoc false

  @keys ~w(page endpoint_page resource_page q endpoint_q packet)
  @page_size 25

  def parse(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @keys)),
         {:ok, page} <- number(params["page"]),
         {:ok, endpoint_page} <- number(params["endpoint_page"]),
         {:ok, resource_page} <- number(params["resource_page"]),
         {:ok, search} <- text(params["q"], 128),
         {:ok, endpoint_search} <- text(params["endpoint_q"], 128),
         {:ok, packet} <- text(params["packet"], 256) do
      {:ok,
       %{
         "page" => page,
         "endpoint_page" => endpoint_page,
         "resource_page" => resource_page,
         "q" => search,
         "endpoint_q" => endpoint_search,
         "packet" => packet
       }}
    else
      _ -> {:error, :invalid_application_surface_query}
    end
  end

  def parse(_), do: {:error, :invalid_application_surface_query}
  def size, do: @page_size

  def slice(items, query, key) do
    total = length(items)
    page = min(query[key], max(1, ceil(total / @page_size)))
    {Enum.slice(items, (page - 1) * @page_size, @page_size), total, page}
  end

  def envelope(items, total, page, base, query, key) do
    last_page = max(1, ceil(total / @page_size))

    %{
      "items" => items,
      "total_count" => total,
      "page" => page,
      "page_size" => @page_size,
      "previous_href" => if(page > 1, do: href(base, Map.put(query, key, page - 1))),
      "next_href" => if(page < last_page, do: href(base, Map.put(query, key, page + 1)))
    }
  end

  def href(base, query), do: base <> "?" <> URI.encode_query(query)

  def matches?(values, search) do
    search = String.downcase(search)
    Enum.any?(values, &String.contains?(String.downcase(to_string(&1)), search))
  end

  defp number(nil), do: {:ok, 1}
  defp number(n) when is_integer(n) and n in 1..100_000, do: {:ok, n}

  defp number(n) when is_binary(n) and byte_size(n) <= 6 do
    case Integer.parse(n) do
      {n, ""} -> number(n)
      _ -> :error
    end
  end

  defp number(_), do: :error
  defp text(nil, _max), do: {:ok, ""}
  defp text(value, max) when is_binary(value) and byte_size(value) <= max, do: {:ok, value}
  defp text(_, _), do: :error
end
