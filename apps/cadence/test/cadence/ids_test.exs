defmodule Cadence.IdsTest do
  use Cadence.UnitCase, async: false

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
