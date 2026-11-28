defmodule Cadence.Alarms.RuleDisabledTest do
  @moduledoc """
  A policy turned off for a spacecraft (#451 T3d) clears the alarm it raised there, with cause
  `rule_disabled`: its effective state becomes `disabled`, which raises and clears nothing, so the
  episode would stay open for ever. Only that spacecraft's, never another's; and a state that is
  merely unknown still changes no episode.
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.SemanticTransitionFixtures

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow, History}
  alias Cadence.SemanticObservations
  alias Cadence.SemanticObservations.FleetAlarms

  @org "org-rule-disabled"
  @mission "mission-rule-disabled"
  @t0 ~U[2026-11-28 12:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  defp at(n), do: DateTime.add(@t0, n)

  defp persist!(parameter, craft, states, n, id) do
    :ok =
      SemanticObservations.persist_many([
        transition(@org, @mission, craft, parameter, states, at(n), "#{id}-#{parameter}-#{craft}")
      ])
  end

  defp episodes, do: Repo.all(from(e in EpisodeRow, order_by: e.spacecraft_id))

  test "a disabled override clears the open alarm on that spacecraft only, with rule_disabled" do
    persist!("P1", "sc-1", {:normal, :critical}, 1, "open")
    persist!("P1", "sc-2", {:normal, :critical}, 1, "open")

    persist!("P1", "sc-1", {:critical, :disabled}, 5, "off")

    assert [%{spacecraft_id: "sc-1", state: "cleared"}, %{spacecraft_id: "sc-2", state: "active"}] =
             episodes()

    assert [%{payload: %{"cause" => "rule_disabled"}}] =
             Repo.all(from(e in EpisodeEventRow, where: e.kind == "cleared"))

    # Fleet follows: the disabled state is not an alarm.
    assert ["sc-2"] = FleetAlarms.load(@org, @mission) |> Map.keys()

    assert %{items: [item]} =
             History.page(@mission, %{spacecraft_id: "sc-1"}, nil, 10, DateTime.add(@t0, 60))

    assert item.ended == :rule_disabled
  end

  test "a replayed batch clears it once, and a disable with nothing open does nothing" do
    persist!("P1", "sc-1", {:normal, :critical}, 1, "open")
    batch = [transition(@org, @mission, "sc-1", "P1", {:critical, :disabled}, at(5), "off")]

    assert :ok = SemanticObservations.persist_many(batch)
    assert :ok = SemanticObservations.persist_many(batch)
    assert Repo.aggregate(from(e in EpisodeEventRow, where: e.kind == "cleared"), :count) == 1

    persist!("P9", "sc-3", {:normal, :disabled}, 6, "never-open")
    assert Enum.map(episodes(), & &1.parameter_ref) == ["P1"]
  end

  test "an unknown state changes no episode" do
    persist!("P1", "sc-1", {:normal, :critical}, 1, "open")
    persist!("P1", "sc-1", {:critical, :unknown}, 5, "unknown")

    assert [%{state: "active"}] = episodes()
  end
end
