defmodule CadenceWeb.OpsContextSnapshotTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsContextSnapshot

  test "builds an ordered mission-scoped module contract from fleet health" do
    observed_at = ~U[2026-08-01 12:00:00Z]

    snapshot =
      OpsContextSnapshot.new(
        "mission-1",
        %{
          normalized_state_counts: %{red: 1, yellow: 2, blue: 0, green: 8},
          violating_points: 3
        },
        observed_at
      )

    assert snapshot.mission_id == "mission-1"
    assert snapshot.observed_at == observed_at
    assert snapshot.pinned_focus == nil

    assert [fleet_health] = snapshot.modules
    assert fleet_health.key == "fleet_health"
    assert fleet_health.status == :critical
    assert fleet_health.count == 3
    assert fleet_health.freshness == :current
    assert fleet_health.observed_at == observed_at
    assert fleet_health.destination == "/missions/mission-1"
  end

  test "distinguishes an unavailable projection from an empty nominal projection" do
    observed_at = ~U[2026-08-01 12:00:00Z]
    snapshot = OpsContextSnapshot.new("mission-1", nil, observed_at)

    assert [fleet_health] = snapshot.modules
    assert fleet_health.freshness == :unavailable
    assert fleet_health.status == nil
    assert fleet_health.count == nil
  end

  test "refreshes fleet health without clearing another module or pinned focus" do
    observed_at = ~U[2026-08-01 12:00:00Z]
    refreshed_at = ~U[2026-08-01 12:01:00Z]

    snapshot =
      OpsContextSnapshot.new("mission-1", nil, observed_at)
      |> Map.put(:pinned_focus, %{kind: :command, id: "command-1"})
      |> Map.update!(:modules, fn modules ->
        modules ++
          [
            %{
              key: "commands",
              title: "Commands",
              icon: "hero-command-line",
              status: :info,
              count: 1,
              freshness: :current,
              observed_at: observed_at,
              destination: "/missions/mission-1/ops/commands",
              data: %{}
            }
          ]
      end)
      |> OpsContextSnapshot.put_fleet_health(
        "mission-1",
        %{
          normalized_state_counts: %{red: 0, yellow: 1, blue: 0, green: 9},
          violating_points: 1
        },
        refreshed_at
      )

    assert Enum.map(snapshot.modules, & &1.key) == ["commands", "fleet_health"]
    assert snapshot.pinned_focus == %{kind: :command, id: "command-1"}
    assert snapshot.observed_at == refreshed_at
    assert Enum.find(snapshot.modules, &(&1.key == "fleet_health")).status == :warning
  end
end
