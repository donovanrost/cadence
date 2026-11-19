defmodule Cadence.Reads.SpacecraftDirectoryTest do
  use ExUnit.Case, async: true

  alias Cadence.Comms.RoutingRule
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

  defp rule(spacecraft_id, opts \\ []) do
    %RoutingRule{
      spacecraft_id: spacecraft_id,
      lifecycle_state: Keyword.get(opts, :lifecycle_state, :active),
      enabled?: Keyword.get(opts, :enabled?, true)
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
        routing_rules: [
          rule("ready"),
          rule("ready", enabled?: false),
          rule("no-rule", lifecycle_state: :archived),
          rule("no-scid"),
          rule("no-profile")
        ],
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
    assert Enum.map(rows, & &1.id) == ["ready", "no-rule", "no-profile", "no-scid"]
  end
end
