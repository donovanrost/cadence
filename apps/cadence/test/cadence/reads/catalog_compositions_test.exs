defmodule Cadence.Reads.CatalogCompositionsTest do
  @moduledoc """
  D2 (#543): the composition behind a catalog revision, as the reads send it beside the catalog
  revision they show (until D3 pins one): the composition of the catalog revision's own
  mission-model revision, or nil.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Reads.CatalogCompositions

  setup do
    org = "org-d2-cc-#{System.unique_integer([:positive])}"
    mid = "mission-d2-cc-#{System.unique_integer([:positive])}"
    {_craft, catalog, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    %{org: org, mid: mid, catalog: catalog}
  end

  test "an imported catalog revision's composition, on a catalog override and an L10 catalog row",
       c do
    id = c.catalog.catalog_revision_id
    compositions = CatalogCompositions.load(c.org, c.mid, [id, "catalog_revision:none", nil])

    assert Map.keys(compositions) == [id]

    assert %{
             composition_id: composition_id,
             number: number,
             imported_layers: [%{mount: "/", catalog_revision: %{id: layer_catalog}}]
           } = composition = compositions[id]

    assert is_binary(composition_id) and is_integer(number)
    assert layer_catalog == id

    catalog_override = %{path: "catalog_revision_id", spacecraft_value: id}
    frame_override = %{path: "frame_parameters.frame_size", spacecraft_value: 892}
    put = &CatalogCompositions.put_override(&1, compositions)
    assert CatalogCompositions.override_ids([catalog_override, frame_override]) == [id]
    assert put.(catalog_override).composition == composition
    assert put.(frame_override).composition == nil

    frame_row = %{field: "frame_size", label: "Frame size", before: 1115, after: 892}
    first_start = %{field: "catalog_revision", label: "Catalog revision", before: nil}
    catalog_row = Map.put(first_start, :after, %{id: id, number: c.catalog.revision_number})
    changes = %{total: 1, groups: [%{count: 1, rows: [catalog_row, frame_row]}]}

    assert %{total: 1, groups: [%{count: 1, rows: [catalog, ^frame_row]}]} =
             CatalogCompositions.configuration_changes(c.org, c.mid, changes)

    assert catalog.before == nil
    assert catalog.after == Map.put(catalog_row.after, :composition, composition)
    assert CatalogCompositions.configuration_changes(c.org, c.mid, nil) == nil
  end
end
