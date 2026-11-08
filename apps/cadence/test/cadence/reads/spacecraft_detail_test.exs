defmodule Cadence.Reads.SpacecraftDetailTest do
  use ExUnit.Case, async: true

  alias Cadence.Comms.{RoutingRule, Transport}
  alias Cadence.Reads.SpacecraftDetail
  alias Cadence.{Spacecraft, SpacecraftType}

  @profile %SpacecraftType{spacecraft_type_id: "p", display_name: "Block 1", version: 4}

  defp craft(opts) do
    %Spacecraft{
      spacecraft_id: "sc",
      display_name: "SC",
      scid: Keyword.get(opts, :scid, 7),
      spacecraft_type_id: Keyword.get(opts, :profile_id, "p"),
      spacecraft_type_version: Keyword.get(opts, :version, 4),
      metadata: %{"plane" => 3}
    }
  end

  defp checks(detail), do: Map.new(detail.readiness.checks, &{&1.key, &1.status})

  test "ready spacecraft with a pinned latest profile and a usable rule" do
    detail =
      SpacecraftDetail.build(%{
        spacecraft: craft([]),
        profiles: [@profile],
        routing_rules: [
          %RoutingRule{
            routing_rule_id: "r1",
            spacecraft_id: "sc",
            display_name: "Primary downlink",
            direction: :inbound,
            role: :primary,
            transport_id: "t1",
            lifecycle_state: :active,
            enabled?: true
          }
        ],
        transports: [%Transport{transport_id: "t1", display_name: "Svalbard X"}],
        last_received_at: ~U[2026-11-08 02:00:00Z]
      })

    assert detail.readiness.ready

    assert checks(detail) == %{
             identity: :ready,
             profile: :ready,
             routing: :ready,
             telemetry: :ready
           }

    assert detail.profile == %{id: "p", name: "Block 1", version: 4, latest_version: 4}

    assert [%{transport: %{name: "Svalbard X"}, active: true, enabled: true}] =
             detail.routing_rules

    assert detail.spacecraft.plane == 3
  end

  test "older pinned version is a caution; missing SCID and rules are blockers" do
    detail =
      SpacecraftDetail.build(%{spacecraft: craft(scid: nil, version: 2), profiles: [@profile]})

    refute detail.readiness.ready

    assert checks(detail) == %{
             identity: :blocker,
             profile: :caution,
             routing: :blocker,
             telemetry: :not_set_up
           }
  end

  test "a deleted pinned profile is a blocker" do
    detail = SpacecraftDetail.build(%{spacecraft: craft([]), profiles: []})
    assert checks(detail).profile == :blocker
    assert detail.profile == %{id: "p", name: nil, version: 4, latest_version: nil}
  end
end
