defmodule Cadence.IdsTest do
  use Cadence.UnitCase, async: false

  test "managed source endpoints keep their persisted format and decode spacecraft IDs" do
    endpoint_id = Cadence.Ids.managed_source_endpoint_id("fleet:craft-2")

    assert endpoint_id == "spacecraft_runtime:fleet:craft-2"
    assert Cadence.Ids.spacecraft_id_from_managed_source_endpoint(endpoint_id) == "fleet:craft-2"
    assert Cadence.Ids.spacecraft_id_from_managed_source_endpoint("source_endpoint_2") == nil
    assert Cadence.Ids.spacecraft_id_from_managed_source_endpoint(nil) == nil
  end

  test "only Cadence.Ids defines the managed source endpoint prefix" do
    root = Path.expand("../../../..", __DIR__)
    ids_path = Path.join(root, "apps/cadence/lib/cadence/ids.ex")

    paths = Path.wildcard(Path.join(root, "{apps,packages}/*/lib/**/*.{ex,exs}"))
    assert ids_path in paths

    for path <- paths -- [ids_path] do
      refute File.read!(path) =~ "spacecraft_runtime:", Path.relative_to(path, root)
    end
  end

  test "generates unique ids with a stable per-boot prefix" do
    first_id = Cadence.Ids.new("packet")
    second_id = Cadence.Ids.new("packet")

    assert first_id != second_id

    boot_id = :persistent_term.get({Cadence.Ids, :boot_id})

    assert String.starts_with?(first_id, "packet_" <> boot_id <> "_")
    assert String.starts_with?(second_id, "packet_" <> boot_id <> "_")
  end

  test "accepts only bounded persisted identifiers as path segments" do
    for identifier <- [
          "slash/id",
          "?query",
          "#fragment",
          "percent%20",
          "space id",
          "é",
          ".",
          "..",
          String.duplicate("a", 121)
        ] do
      assert {:error, :invalid_identifier} = Cadence.Ids.path_segment(identifier)
    end

    max_identifier = String.duplicate("a", 120)
    assert {:ok, ^max_identifier} = Cadence.Ids.path_segment(max_identifier)
  end
end
