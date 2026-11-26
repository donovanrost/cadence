defmodule Cadence.Dashboards.DocumentDiff do
  @moduledoc """
  A short, closed summary of how two dashboard documents differ, for an import that keeps its
  id and meets a different dashboard already there (#746): which top-level fields changed, and
  which placements were added, removed or changed. It names ids and fields, never values.
  """

  alias Cadence.Dashboards.Document

  @fields ~w(schema_version name description defaults grid sections metadata)a

  @doc "A document as compared: its map form without the version metadata, which an import resets."
  @spec comparable(Document.t()) :: map()
  def comparable(%Document{} = document) do
    map = document |> Document.to_map() |> normalize()
    Map.update(map, "metadata", %{}, &Map.drop(&1, ~w(version dashboard_version)))
  end

  @spec summary(map(), map()) :: %{
          fields: [binary()],
          placements: %{added: [binary()], removed: [binary()], changed: [binary()]}
        }
  def summary(existing, imported) do
    existing_placements = placements(existing)
    imported_placements = placements(imported)

    both =
      Map.keys(existing_placements) --
        (Map.keys(existing_placements) -- Map.keys(imported_placements))

    %{
      fields:
        for(
          field <- @fields,
          existing[Atom.to_string(field)] != imported[Atom.to_string(field)],
          do: Atom.to_string(field)
        ),
      placements: %{
        added: Enum.sort(Map.keys(imported_placements) -- Map.keys(existing_placements)),
        removed: Enum.sort(Map.keys(existing_placements) -- Map.keys(imported_placements)),
        changed:
          both
          |> Enum.filter(&(existing_placements[&1] != imported_placements[&1]))
          |> Enum.sort()
      }
    }
  end

  defp placements(map) do
    map
    |> Map.get("placements", [])
    |> Map.new(&{to_string(&1["placement_id"]), &1})
  end

  # Both sides through JSON, so atom and string keys and struct forms compare alike.
  defp normalize(map), do: map |> Jason.encode!() |> Jason.decode!()
end
