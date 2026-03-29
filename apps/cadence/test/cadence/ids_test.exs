defmodule Cadence.IdsTest do
  use ExUnit.Case, async: false

  test "generates unique ids with a stable per-boot prefix" do
    first_id = Cadence.Ids.new("packet")
    second_id = Cadence.Ids.new("packet")

    assert first_id != second_id

    boot_id = :persistent_term.get({Cadence.Ids, :boot_id})

    assert String.starts_with?(first_id, "packet_" <> boot_id <> "_")
    assert String.starts_with?(second_id, "packet_" <> boot_id <> "_")
  end
end
