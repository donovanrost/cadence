defmodule Cadence.Reads.ApplicationSurfaces.TablePagination do
  @moduledoc "Host-owned bounded pagination for application surface query providers."

  alias Cadence.Listing.Page

  @default_page_size 20
  @max_page_size 50

  @spec paginate(list(), map(), keyword()) ::
          {:ok, Page.t()} | {:error, :invalid_application_surface_page_size}
  def paginate(items, params, opts \\ []) when is_list(items) and is_map(params) do
    page_size = Keyword.get(opts, :page_size, @default_page_size)

    if is_integer(page_size) and page_size > 0 and page_size <= @max_page_size do
      total_count = length(items)
      last_page = max(ceil(total_count / page_size), 1)
      page = params |> requested_page() |> min(last_page)
      offset = (page - 1) * page_size

      {:ok,
       %Page{
         items: Enum.slice(items, offset, page_size),
         total_count: total_count,
         page: page,
         page_size: page_size
       }}
    else
      {:error, :invalid_application_surface_page_size}
    end
  end

  defp requested_page(params) do
    params
    |> Map.get("page", Map.get(params, :page, 1))
    |> normalize_page()
  end

  defp normalize_page(page) when is_integer(page), do: max(page, 1)

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {parsed, ""} -> max(parsed, 1)
      _invalid -> 1
    end
  end

  defp normalize_page(_page), do: 1
end
