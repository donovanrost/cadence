defmodule Cadence.Alarms.RuleChangedEventTest do
  @moduledoc """
  A change of the rules in force on a parameter records one `rule_changed` event on its open alarm
  episode (#451 T2d): replay-safe (the id derives from the episode, the rule ids and the two
  digests, inserted if absent, DECISIONS #99), only while an episode is open, and never for the
  sample that opened it.
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.SemanticTransitionFixtures

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow}
  alias Cadence.SemanticObservations

  @org "org-rule-changed"
  @mission "mission-rule-changed"
  @t0 ~U[2026-11-28 12:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  defp at(n), do: DateTime.add(@t0, n)

  defp open!(parameter, craft \\ "sc-1") do
    :ok =
      SemanticObservations.persist_many([
        transition(
          @org,
          @mission,
          craft,
          parameter,
          {:normal, :critical},
          at(1),
          "open-#{parameter}-#{craft}"
        )
      ])
  end

  # A sample after the alarm opened: the state stays critical, the rules in force changed.
  defp rule_change(parameter, id, n, change, craft \\ "sc-1") do
    prepared = transition(@org, @mission, craft, parameter, {:critical, :critical}, at(n), id)

    update_in(prepared.semantic_result.monitoring_results, fn [monitoring] ->
      [%{monitoring | transition: nil, metadata: %{rule_changed: change}}]
    end)
  end

  defp digests(from, to), do: %{from: from, to: to, rule_ids: ["limit:p"]}

  defp events do
    Repo.all(from(e in EpisodeEventRow, where: e.kind == "rule_changed", order_by: e.at))
  end

  test "an open episode gets one rule_changed event with the digests and the rule ids" do
    open!("P1")

    :ok =
      SemanticObservations.persist_many([rule_change("P1", "edit-1", 5, digests("d1", "d2"))])

    assert [event] = events()
    assert event.kind == "rule_changed"
    assert event.at == at(5)

    assert %{"from" => "d1", "to" => "d2", "rule_ids" => ["limit:p"], "policy_id" => "policy-P1"} =
             event.payload

    # The episode itself is untouched: still the same active critical episode.
    assert [%EpisodeRow{state: "active", severity: "critical"}] = Repo.all(EpisodeRow)
  end

  test "a replayed batch writes it once, and so does a re-cut one (another evidence id)" do
    open!("P1")
    batch = [rule_change("P1", "edit-1", 5, digests("d1", "d2"))]

    assert :ok = SemanticObservations.persist_many(batch)
    assert :ok = SemanticObservations.persist_many(batch)
    assert length(events()) == 1

    # The same change cut into another batch: another evidence and sample id, the same event.
    assert :ok =
             SemanticObservations.persist_many([
               rule_change("P1", "edit-1-recut", 6, digests("d1", "d2"))
             ])

    assert length(events()) == 1

    # A different change (another digest pair) is another event.
    assert :ok =
             SemanticObservations.persist_many([
               rule_change("P1", "edit-2", 9, digests("d2", "d3"))
             ])

    assert [first, second] = events()
    assert {first.payload["to"], second.payload["to"]} == {"d2", "d3"}
  end

  test "nothing is recorded with no open episode, for the sample that opened it, or after it cleared" do
    # No episode at all.
    assert :ok =
             SemanticObservations.persist_many([
               rule_change("P1", "no-episode", 5, digests("d1", "d2"))
             ])

    assert events() == []

    # The sample that opens the alarm carries the change: the episode ran under the new rules.
    opening = transition(@org, @mission, "sc-1", "P2", {:normal, :critical}, at(1), "opening")

    opening =
      update_in(opening.semantic_result.monitoring_results, fn [monitoring] ->
        [%{monitoring | metadata: %{rule_changed: digests("d1", "d2")}}]
      end)

    assert :ok = SemanticObservations.persist_many([opening])
    assert events() == []

    # After the alarm clears, a change has no episode to attach to.
    assert :ok =
             SemanticObservations.persist_many([
               transition(@org, @mission, "sc-1", "P2", {:critical, :normal}, at(3), "clear")
             ])

    assert :ok =
             SemanticObservations.persist_many([
               rule_change("P2", "after-clear", 8, digests("d2", "d3"))
             ])

    assert events() == []
  end

  test "each spacecraft's episode gets its own event for the same change" do
    open!("P1", "sc-1")
    open!("P1", "sc-2")

    assert :ok =
             SemanticObservations.persist_many([
               rule_change("P1", "edit-a", 5, digests("d1", "d2"), "sc-1"),
               rule_change("P1", "edit-b", 5, digests("d1", "d2"), "sc-2")
             ])

    assert length(events()) == 2
    assert events() |> Enum.map(& &1.episode_id) |> Enum.uniq() |> length() == 2
  end
end
