defmodule Cadence.Reads.SpacecraftPassesTest do
  @moduledoc "Investigate Passes P1 coverage: contacts, the longest gap and the contact rule."
  use ExUnit.Case, async: true

  alias Cadence.Reads.SpacecraftPasses

  @now ~U[2026-11-11 12:00:00Z]

  defp pass(id, state, start_h, minutes \\ 8) do
    starts = DateTime.add(@now, round(start_h * 3_600))

    %{
      id: id,
      state: state,
      station: %{id: "st-#{id}", code: "FBK", name: "Fairbanks"},
      starts_at: starts,
      ends_at: DateTime.add(starts, minutes * 60)
    }
  end

  defp rule(id, from_h, to_h, need) do
    %{
      requirement_id: id,
      version: 1,
      text: "#{need} contacts",
      window: %{from: DateTime.add(@now, from_h * 3_600), to: DateTime.add(@now, to_h * 3_600)},
      need: need
    }
  end

  test "last and next contact, passes ahead and the longest booked gap with its bounds" do
    passes = [
      pass("flown", "completed", -3),
      pass("a", "confirmed", 2),
      pass("b", "active", 10),
      # Not booked: doesn't count toward coverage or gaps.
      pass("requested", "requesting", 5),
      pass("far", "confirmed", 30)
    ]

    coverage = SpacecraftPasses.coverage(passes, [], @now)

    assert %{pass_id: "flown", los_at: los} = coverage.last_contact
    assert los == DateTime.add(@now, -3 * 3_600 + 480)
    assert %{pass_id: "a", aos_at: aos} = coverage.next_contact
    assert aos == DateTime.add(@now, 2 * 3_600)
    assert coverage.passes_next_24h == 2
    refute coverage.none_within_6h

    # Gaps: now→a (2 h), a→b (~7.9 h), b→now+24h (~13.9 h): the last is the longest.
    b_end = DateTime.add(@now, 10 * 3_600 + 480)

    assert coverage.longest_gap == %{
             from: b_end,
             to: DateTime.add(@now, 86_400),
             seconds: 50_400 - 480
           }

    assert coverage.contact_rule == %{state: :none, have: 0, need: 0, rules: []}
  end

  test "no booked pass ahead: the whole day is the gap and it's a U35 caution" do
    coverage = SpacecraftPasses.coverage([pass("x", "requesting", 1)], [], @now)

    assert coverage.next_contact == nil
    assert coverage.none_within_6h
    assert coverage.longest_gap.seconds == 86_400
    assert coverage.last_contact == nil
  end

  test "the next contact can be days out while the 24 h figures stay empty" do
    coverage = SpacecraftPasses.coverage([pass("later", "confirmed", 48)], [], @now)

    assert %{pass_id: "later"} = coverage.next_contact
    assert coverage.passes_next_24h == 0
    assert coverage.none_within_6h
    assert coverage.longest_gap.seconds == 86_400
  end

  test "the contact rule counts booked or flown passes inside each window, capped at its need" do
    passes = [
      pass("m1", "completed", -10),
      pass("m2", "completed", -6),
      pass("m3", "confirmed", -2),
      pass("e1", "confirmed", 4),
      pass("e2", "rejected", 6)
    ]

    rules = [rule("morning", -12, 0, 2), rule("evening", 0, 12, 2)]
    rule = SpacecraftPasses.coverage(passes, rules, @now).contact_rule

    assert %{state: :short, have: 3, need: 4} = rule

    assert [
             %{requirement_id: "morning", have: 2, met: true},
             %{requirement_id: "evening", have: 1, met: false}
           ] =
             rule.rules
  end
end
