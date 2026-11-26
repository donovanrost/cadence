defmodule Cadence.Reads.SpacecraftNames do
  @moduledoc """
  Spacecraft id → name and SCID for a mission (#847): what a screen needs to name the craft its
  own rows carry (Plan, Re-plan), without the fleet read's telemetry and limits.

  Two shapes, both bounded per request:
  - **By ids** (`by_ids/3`): at most 100 ids, the small sets a screen already knows.
  - **The whole mission in pages** (`page/4`): sorted by name then id, a page of at most 500
    after an opaque cursor, so a screen that needs every name walks a few bounded pages; there is
    no unpaged list.

  Rows are `%{"id", "name", "scid"}` from `SpacecraftStore` (no metadata loaded).
  """

  alias Cadence.Reads.SpacecraftCursor
  alias Cadence.SpacecraftStore

  @max_ids 100
  @default_limit 500
  @max_limit 500

  @doc "The names of the given spacecraft (unknown ids are left out); more than #{@max_ids} is refused."
  @spec by_ids(binary(), binary(), [binary()]) ::
          {:ok, [map()]} | {:error, {:invalid_params, map()}}
  def by_ids(_org, _mission, ids) when length(ids) > @max_ids,
    do: {:error, {:invalid_params, %{"ids" => "at most #{@max_ids}"}}}

  def by_ids(org, mission, ids) do
    case SpacecraftStore.display_names(org, mission, Enum.uniq(ids), scid: true) do
      {:ok, rows} -> {:ok, rows}
      {:error, _bounds} -> {:error, {:invalid_params, %{"ids" => "must be spacecraft ids"}}}
    end
  end

  @doc """
  One page of the mission's names: `%{names, next_cursor}`, `next_cursor` nil on the last page.
  `limit` 1–#{@max_limit} (default #{@default_limit}).
  """
  @spec page(binary(), binary(), binary() | nil, term()) ::
          {:ok, %{names: [map()], next_cursor: binary() | nil}} | {:error, :invalid_cursor}
  def page(org, mission, cursor, limit) do
    size = page_size(limit)

    with {:ok, after_key} <- SpacecraftCursor.decode(cursor) do
      # One row more than the page says whether another page follows.
      rows = SpacecraftStore.display_names_page(org, mission, after_key, size + 1)
      {names, more} = Enum.split(rows, size)

      {:ok,
       %{
         names: names,
         next_cursor:
           if(more != [], do: names |> List.last() |> cursor_key() |> SpacecraftCursor.encode())
       }}
    end
  end

  defp page_size(limit) when is_integer(limit) and limit in 1..@max_limit, do: limit
  defp page_size(_limit), do: @default_limit

  defp cursor_key(%{"name" => name, "id" => id}), do: {name, id}
end
