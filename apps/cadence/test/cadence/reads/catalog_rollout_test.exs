defmodule Cadence.Reads.CatalogRolloutTest do
  @moduledoc "Catalog C3 rollout: each pinned spacecraft counts in exactly one bucket."
  use ExUnit.Case, async: true

  alias Cadence.Reads.CatalogRollout

  defp sc(id, type, version),
    do: %{spacecraft_id: id, spacecraft_type_id: type, spacecraft_type_version: version}

  test "override first, then already on the revision, else movable; default moves only the current version" do
    profile = %{
      spacecraft_type_id: "p1",
      display_name: "Block 1",
      version: 3,
      catalog_revision_id: "rev-a"
    }

    spacecraft = [
      sc("cur-move", "p1", 3),
      sc("cur-on", "p1", 3),
      sc("cur-own", "p1", 3),
      sc("old-move", "p1", 2),
      # Pinned to its own catalog AND already on the target AND on an older version: once, as override.
      sc("old-own-on", "p1", 1),
      sc("loose", nil, nil)
    ]

    rollout =
      CatalogRollout.build(%{
        revision_id: "rev-b",
        numbers: %{"rev-a" => 3, "rev-b" => 4},
        profiles: [profile],
        spacecraft: spacecraft,
        own_catalog: MapSet.new(["cur-own", "old-own-on"]),
        configured: %{"cur-on" => "rev-b", "old-own-on" => "rev-b", "cur-move" => "rev-a"}
      })

    assert rollout.revision == %{id: "rev-b", number: 4, label: "rev 4"}
    assert rollout.unprofiled_count == 1

    assert [
             %{
               id: "p1",
               name: "Block 1",
               current_revision: %{id: "rev-a", number: 3, label: "rev 3"},
               spacecraft_count: 5,
               on_current_version: 3,
               on_older_versions: 2,
               override_pinned: 2,
               already_on_revision: 1,
               moves_default: 1,
               moves_all: 2
             } = row
           ] = rollout.profiles

    assert row.override_pinned + row.already_on_revision + row.moves_all == row.spacecraft_count
  end

  test "a profile with no catalog and no spacecraft" do
    profile = %{
      spacecraft_type_id: "p2",
      display_name: "Bare",
      version: 1,
      catalog_revision_id: nil
    }

    assert %{profiles: [%{current_revision: nil, spacecraft_count: 0, moves_all: 0}]} =
             CatalogRollout.build(%{
               revision_id: "rev-b",
               numbers: %{},
               profiles: [profile],
               spacecraft: [],
               own_catalog: MapSet.new(),
               configured: %{}
             })
  end
end
