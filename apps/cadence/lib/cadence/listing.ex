defmodule Cadence.Listing do
  @moduledoc """
  Shared vocabulary for paginated list queries.

  Stores that support fleet-scale listing return a `Cadence.Listing.Page`
  so callers get the items and the total count for the active filter in
  one value. Offset pagination is deliberate: list URLs (`?page=2`) must
  be shareable and per-mission row counts stay in the hundreds.
  """

  defmodule Page do
    @moduledoc "One page of a filtered list plus the filter's total count."

    @enforce_keys [:items, :total_count, :page, :page_size]
    defstruct [:items, :total_count, :page, :page_size]

    @type t :: %__MODULE__{
            items: list(),
            total_count: non_neg_integer(),
            page: pos_integer(),
            page_size: pos_integer()
          }
  end

  @default_page_size 50
  @max_page_size 100

  @doc "Normalizes `:page`/`:page_size` opts into clamped values plus an offset."
  @spec page_opts(keyword()) :: %{
          page: pos_integer(),
          page_size: pos_integer(),
          offset: non_neg_integer()
        }
  def page_opts(opts) when is_list(opts) do
    page = opts |> Keyword.get(:page, 1) |> max(1)

    page_size =
      opts
      |> Keyword.get(:page_size, @default_page_size)
      |> max(1)
      |> min(@max_page_size)

    %{page: page, page_size: page_size, offset: (page - 1) * page_size}
  end

  @doc "Escapes `\\`, `%`, and `_` so user input matches literally inside ILIKE patterns."
  @spec escape_like(binary()) :: binary()
  def escape_like(term) when is_binary(term) do
    String.replace(term, ~r/([\\%_])/, "\\\\\\1")
  end
end
