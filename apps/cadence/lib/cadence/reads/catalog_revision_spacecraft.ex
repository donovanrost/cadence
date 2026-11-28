defmodule Cadence.Reads.CatalogRevisionSpacecraft do
  @moduledoc """
  The spacecraft that use a catalog revision (#678): those whose latest saved configuration names
  it, those whose active generation runs it, or both. Paged by name then id with the names read's
  cursor (#847), at most 500 a page. A fixed number of queries however large the fleet:
  - the saved set (one query);
  - the active set (the activation, then one query over its fleet members);
  - one page and its total;
  - the page's latest versions.

  Rows are `%{id, name, scid, uses, configuration_version}`:
  - `uses` is a subset of `["saved", "active"]`, in that order;
  - `configuration_version` is the craft's latest saved configuration version, or nil when it has
    none.
  """

  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Catalog
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Reads.SpacecraftCursor
  alias Cadence.SpacecraftStore

  @default_limit 200
  @max_limit 500

  @spec page(binary(), binary(), binary(), binary() | nil, term()) ::
          {:ok, %{spacecraft: [map()], total: non_neg_integer(), next_cursor: binary() | nil}}
          | {:error, :invalid_cursor | :catalog_revision_not_found}
  def page(organization_id, mission_id, catalog_revision_id, cursor, limit) do
    size = page_size(limit)

    with {:ok, _revision} <- revision(organization_id, mission_id, catalog_revision_id),
         {:ok, after_key} <- SpacecraftCursor.decode(cursor) do
      saved =
        MapSet.new(Drafts.saved_on_catalog(organization_id, mission_id, catalog_revision_id))

      active = MapSet.new(active(organization_id, mission_id, catalog_revision_id))
      ids = saved |> MapSet.union(active) |> MapSet.to_list()

      {rows, total} =
        SpacecraftStore.names_page_of(organization_id, mission_id, ids, after_key, size + 1)

      {page, more} = Enum.split(rows, size)
      versions = Drafts.latest_versions(organization_id, mission_id, Enum.map(page, & &1["id"]))

      {:ok,
       %{
         spacecraft: Enum.map(page, &row(&1, saved, active, versions)),
         total: total,
         next_cursor: if(more != [], do: cursor_of(List.last(page)))
       }}
    end
  end

  defp revision(organization_id, mission_id, catalog_revision_id) do
    case Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id) do
      {:ok, revision} -> {:ok, revision}
      {:error, _not_found} -> {:error, :catalog_revision_not_found}
    end
  end

  defp active(organization_id, mission_id, catalog_revision_id) do
    case ControlActivations.fetch_active_basis(organization_id, mission_id) do
      {:ok, activation} ->
        FleetSnapshot.spacecraft_on_catalog(activation.metadata, catalog_revision_id)

      {:error, _none} ->
        []
    end
  end

  defp row(%{"id" => id, "name" => name, "scid" => scid}, saved, active, versions) do
    %{
      id: id,
      name: name,
      scid: scid,
      uses:
        Enum.filter(
          ["saved", "active"],
          &((&1 == "saved" and MapSet.member?(saved, id)) or
              (&1 == "active" and MapSet.member?(active, id)))
        ),
      configuration_version: Map.get(versions, id)
    }
  end

  defp cursor_of(%{"name" => name, "id" => id}), do: SpacecraftCursor.encode({name, id})

  defp page_size(limit) when is_integer(limit) and limit in 1..@max_limit, do: limit
  defp page_size(_limit), do: @default_limit
end
