defmodule Cadence.Catalog.FleetSnapshotTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Catalog.FleetSnapshot.{EntryRow, MemberRow}
  alias Cadence.Catalog.SpacecraftConfigurationInput

  setup do
    %{mission_id: mission} = configuration_mission("fleet")
    %{mission: mission}
  end

  test "stores a fleet once and reads it back by spacecraft, source and commanding", %{
    mission: mission
  } do
    entries = fleet(3)
    assert {:ok, %{"count" => 3, "sha256" => sha} = fleet} = FleetSnapshot.store(mission, entries)
    assert {:ok, ^fleet} = FleetSnapshot.store(mission, entries)

    metadata = FleetSnapshot.metadata(fleet, %{"spacecraft_id" => "sc-1"})
    assert FleetSnapshot.fleet?(metadata)
    assert FleetSnapshot.fleet_sha256(metadata) == sha
    assert {:ok, ^entries} = FleetSnapshot.entries(metadata)
    assert {:ok, %{"catalog_revision_id" => "cat-2"}} = FleetSnapshot.entry(metadata, "sc-2")

    assert {:ok, %{"source_endpoint_ids" => ["src-3"]}} =
             FleetSnapshot.entry_for_source(metadata, "src-3")

    assert {:error, :spacecraft_model_not_active} =
             FleetSnapshot.entry_for_source(metadata, "nope")

    assert ["sc-1", "sc-2", "sc-3"] = FleetSnapshot.spacecraft_ids(metadata)
    assert {:ok, commanding} = FleetSnapshot.commanding_entries(metadata)
    assert Map.keys(commanding) |> Enum.sort() == ["sc-1", "sc-3"]
    assert %{"sc-2" => "cat-2"} = FleetSnapshot.catalog_usage(metadata)
  end

  # #56: bytewise, whatever the database's collation (en_US would give sc-a, sc-A, SC-b).
  test "a stored fleet's spacecraft ids are sorted bytewise", %{mission: mission} do
    entries =
      fleet(3)
      |> Enum.zip(["SC-b", "sc-a", "sc-A"])
      |> Map.new(fn {{_id, entry}, id} -> {id, entry} end)

    {:ok, fleet} = FleetSnapshot.store(mission, entries)
    metadata = FleetSnapshot.metadata(fleet, %{"spacecraft_id" => "sc-a"})

    assert FleetSnapshot.spacecraft_ids(metadata) == ["SC-b", "sc-A", "sc-a"]
  end

  test "an unchanged spacecraft re-uses its stored entry", %{mission: mission} do
    {:ok, _} = FleetSnapshot.store(mission, fleet(3))
    changed = put_in(fleet(3), ["sc-1", "catalog_revision_id"], "cat-9")
    changed = put_in(changed, ["sc-1", "document", "catalog_revision_id"], "cat-9")
    {:ok, _} = FleetSnapshot.store(mission, changed)

    assert Repo.aggregate(where(EntryRow, mission_id: ^mission), :count) == 4
    assert Repo.aggregate(where(MemberRow, mission_id: ^mission), :count) == 6
  end

  test "inline (v1) metadata stays readable", %{mission: mission} do
    _ = mission
    metadata = %{"spacecraft_configuration_version" => 1, "spacecraft_configurations" => fleet(2)}

    assert FleetSnapshot.fleet?(metadata)
    assert {:ok, %{"source_endpoint_ids" => ["src-2"]}} = FleetSnapshot.entry(metadata, "sc-2")
    assert {:ok, _} = FleetSnapshot.entry_for_source(metadata, "src-1")
  end

  test "invalid fleets are refused before anything is stored", %{mission: mission} do
    duplicate_source = put_in(fleet(2), ["sc-2", "source_endpoint_ids"], ["src-1"])

    assert {:error, :invalid_spacecraft_model_bindings} =
             FleetSnapshot.store(mission, duplicate_source)

    assert {:error, :invalid_spacecraft_model_bindings} = FleetSnapshot.store(mission, %{})
    assert Repo.aggregate(where(MemberRow, mission_id: ^mission), :count) == 0
  end

  defp fleet(count) do
    Map.new(1..count, fn n ->
      catalog = "cat-#{n}"
      commanding = rem(n, 2) == 1

      document =
        Map.merge(SpacecraftConfigurationInput.empty(), %{
          "catalog_revision_id" => catalog,
          "commanding_enabled" => commanding
        })

      {"sc-#{n}",
       %{
         "configuration_revision_id" => "rev-#{n}",
         "configuration_version" => 1,
         "catalog_revision_id" => catalog,
         "commanding_enabled" => commanding,
         "document" => document,
         "mission_model" => %{
           "revision_id" => "model-1",
           "content_sha256" => "abc",
           "plans" => %{}
         },
         "source_endpoint_ids" => ["src-#{n}"],
         "telemetry_capability_ids" => []
       }}
    end)
  end
end
