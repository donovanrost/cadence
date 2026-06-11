defmodule CadenceWeb.ListParams do
  @moduledoc """
  Parses and serializes URL params for list pages (`?q=&sort=&dir=&page=`).

  LiveViews call `parse/2` in `handle_params`, translate toolbar events
  into `push_patch` with `to_query/2`, and map the whitelisted `sort`
  string to the store's atom contract themselves (explicit clauses — never
  `String.to_existing_atom`).
  """

  defstruct q: nil, sort: nil, dir: :asc, page: 1, default_sort: nil

  @type t :: %__MODULE__{
          q: binary() | nil,
          sort: binary() | nil,
          dir: :asc | :desc,
          page: pos_integer(),
          default_sort: binary() | nil
        }

  @spec parse(map(), keyword()) :: t()
  def parse(params, opts) when is_map(params) and is_list(opts) do
    sortable = Keyword.fetch!(opts, :sortable)
    default_sort = Keyword.get(opts, :default_sort)

    %__MODULE__{
      q: parse_query(params["q"]),
      sort: parse_sort(params["sort"], sortable, default_sort),
      dir: parse_dir(params["dir"]),
      page: parse_page(params["page"]),
      default_sort: default_sort
    }
  end

  @doc "Sorting an already-active column flips direction; a new column resets to ascending."
  @spec toggle_sort(t(), binary()) :: t()
  def toggle_sort(%__MODULE__{sort: key, dir: :asc} = list, key),
    do: %{list | dir: :desc, page: 1}

  def toggle_sort(%__MODULE__{} = list, key), do: %{list | sort: key, dir: :asc, page: 1}

  @doc """
  Serializes to query params, dropping defaults so bare URLs stay canonical.
  Extra pairs (e.g. `filter: "missing_profile"`) are appended; nil values
  are dropped.
  """
  @spec to_query(t(), keyword()) :: keyword()
  def to_query(%__MODULE__{} = list, extra \\ []) do
    default_sort? = list.sort == list.default_sort and list.dir == :asc

    [
      q: list.q,
      sort: unless(default_sort?, do: list.sort),
      dir: if(list.dir == :desc, do: "desc"),
      page: if(list.page > 1, do: list.page)
    ]
    |> Keyword.merge(extra)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp parse_query(q) when is_binary(q) do
    case String.trim(q) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp parse_query(_q), do: nil

  defp parse_sort(sort, sortable, default) do
    if is_binary(sort) and sort in sortable, do: sort, else: default
  end

  defp parse_dir("desc"), do: :desc
  defp parse_dir(_dir), do: :asc

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {n, ""} when n >= 1 -> n
      _other -> 1
    end
  end

  defp parse_page(_page), do: 1
end
