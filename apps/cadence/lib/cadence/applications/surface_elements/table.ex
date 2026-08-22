defmodule Cadence.Applications.SurfaceElements.Table do
  @moduledoc "Bounded, paginated tabular projection rendered by the application host."

  alias Cadence.Listing.Page

  @type column :: %{key: atom(), label: binary(), mono: boolean()}
  @type row :: %{required(:id) => binary(), optional(atom()) => binary()}

  @type t :: %__MODULE__{
          id: binary(),
          title: binary(),
          description: binary() | nil,
          columns: [column()],
          page: Page.t(),
          empty_title: binary(),
          empty_description: binary() | nil
        }

  @enforce_keys [:id, :title, :columns, :page, :empty_title]
  defstruct [:id, :title, :description, :page, :empty_title, :empty_description, columns: []]

  @max_page_size 50
  @max_columns 12

  @spec validate(t()) :: :ok | {:error, :invalid_application_surface_table}
  def validate(%__MODULE__{page: %Page{} = page} = table) do
    with true <- valid_text?(table.id),
         true <- valid_text?(table.title),
         true <- optional_text?(table.description),
         true <- valid_text?(table.empty_title),
         true <- optional_text?(table.empty_description),
         true <- valid_columns?(table.columns),
         true <- is_list(page.items),
         true <- nonnegative_integer?(page.total_count),
         true <- positive_integer?(page.page),
         true <- valid_page_size?(page.page_size),
         true <- page_in_range?(page),
         true <- expected_row_count?(page),
         true <- valid_rows?(page.items, table.columns) do
      :ok
    else
      _invalid -> {:error, :invalid_application_surface_table}
    end
  end

  def validate(%__MODULE__{}), do: {:error, :invalid_application_surface_table}

  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0
  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp valid_page_size?(page_size),
    do: positive_integer?(page_size) and page_size <= @max_page_size

  defp page_in_range?(%Page{} = page) do
    page.page <= max(ceil(page.total_count / page.page_size), 1)
  end

  defp expected_row_count?(%Page{} = page) do
    expected =
      min(page.page_size, max(page.total_count - (page.page - 1) * page.page_size, 0))

    length(page.items) == expected
  end

  defp valid_columns?(columns) when is_list(columns) do
    column_keys = Enum.map(columns, &column_key/1)

    columns != [] and length(columns) <= @max_columns and
      Enum.all?(columns, &valid_column?/1) and
      length(Enum.uniq(column_keys)) == length(column_keys)
  end

  defp valid_columns?(_columns), do: false

  defp valid_column?(%{key: key, label: label, mono: mono}),
    do: is_atom(key) and valid_text?(label) and is_boolean(mono)

  defp valid_column?(_column), do: false

  defp column_key(column) when is_map(column), do: Map.get(column, :key)
  defp column_key(_column), do: nil

  defp valid_rows?(items, columns) do
    row_ids = Enum.map(items, &row_id/1)
    column_keys = Enum.map(columns, & &1.key)

    Enum.all?(row_ids, &(is_binary(&1) and &1 != "")) and
      length(Enum.uniq(row_ids)) == length(row_ids) and
      Enum.all?(items, &valid_row?(&1, column_keys))
  end

  defp valid_row?(row, column_keys) when is_map(row) do
    Enum.all?(column_keys, fn key -> is_binary(Map.get(row, key)) end)
  end

  defp valid_row?(_row, _column_keys), do: false

  defp row_id(row) when is_map(row), do: Map.get(row, :id)
  defp row_id(_row), do: nil

  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
