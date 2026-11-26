defmodule Cadence.Reads.SpacecraftDirectoryTest do
  use ExUnit.Case, async: true

  alias Cadence.Reads.SpacecraftDirectory
  alias Cadence.{Spacecraft, SpacecraftType}

  defp craft(id, opts) do
    %Spacecraft{
      spacecraft_id: id,
      display_name: id,
      scid: Keyword.get(opts, :scid),
      spacecraft_type_id: Keyword.get(opts, :profile_id),
      spacecraft_type_version: 1,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  test "ready needs a SCID, a profile and an active enabled routing rule" do
    at = ~U[2026-11-08 02:00:00Z]

    rows =
      SpacecraftDirectory.build(%{
        spacecraft: [
          craft("ready",
            scid: 1,
            profile_id: "p",
            metadata: %{"norad_id" => "58001", "plane" => 2}
          ),
          craft("no-rule", scid: 2, profile_id: "p"),
          craft("no-scid", profile_id: "p"),
          craft("no-profile", scid: 3)
        ],
        profiles: [%SpacecraftType{spacecraft_type_id: "p", display_name: "Bus", version: 1}],
        rule_counts: %{"ready" => 1, "no-scid" => 1, "no-profile" => 1},
        last_received: %{"ready" => at}
      })

    by_id = Map.new(rows, &{&1.id, &1})

    assert by_id["ready"].ready
    assert by_id["ready"].routing_rule_count == 1
    assert by_id["ready"].norad_id == 58_001
    assert by_id["ready"].plane == 2
    assert by_id["ready"].profile == %{id: "p", name: "Bus", version: 1}
    assert by_id["ready"].last_received_at == at

    refute by_id["no-rule"].ready
    assert by_id["no-rule"].routing_rule_count == 0
    refute by_id["no-scid"].ready
    refute by_id["no-profile"].ready
    # The builder keeps the page's order (the store pages by name, then id).
    assert Enum.map(rows, & &1.id) == ["ready", "no-rule", "no-scid", "no-profile"]
  end
end
