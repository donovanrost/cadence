defmodule Cadence.ContactPlanning.RepairPairingTest do
  @moduledoc "Which lost booking a repair's new pass replaces (qa #30 review R1, DECISIONS #56)."
  use ExUnit.Case, async: true

  alias Cadence.ContactPlanning.RepairPairing

  defp at(hour, minute), do: DateTime.new!(~D[2026-11-10], Time.new!(hour, minute, 0))

  defp pass(id, at, opts \\ []),
    do: %{
      id: id,
      starts_at: at,
      requirement_id: Keyword.get(opts, :requirement),
      spacecraft_id: Keyword.get(opts, :spacecraft, "sc-004")
    }

  test "unequal counts pair by nearest start and leave the rest unpaired" do
    lost = [pass("lost-10", at(10, 0)), pass("lost-22", at(22, 0))]
    assert RepairPairing.pair(lost, [pass("new-2150", at(21, 50))]) == %{"new-2150" => "lost-22"}
  end

  test "the same requirement wins over a nearer pass of the same spacecraft" do
    lost = [
      pass("lost-a", at(10, 0), requirement: "req-a"),
      pass("lost-b", at(12, 0), requirement: "req-b")
    ]

    fresh = [pass("new-a", at(11, 55), requirement: "req-a")]
    assert RepairPairing.pair(lost, fresh) == %{"new-a" => "lost-a"}
  end

  test "known but different requirements never pair; an unknown one falls back to the spacecraft" do
    lost = [pass("lost-a", at(10, 0), requirement: "req-a")]

    assert RepairPairing.pair(lost, [pass("new-b", at(10, 5), requirement: "req-b")]) == %{}
    assert RepairPairing.pair(lost, [pass("single", at(10, 5))]) == %{"single" => "lost-a"}

    assert RepairPairing.pair(lost, [pass("other-craft", at(10, 5), spacecraft: "sc-9")]) ==
             %{}
  end

  describe "cover/2 (DECISIONS #56)" do
    defp lost_input(key, at, spacecraft, requirement \\ "req-a"),
      do: %{
        "key" => key,
        "starts_at" => DateTime.to_iso8601(at),
        "spacecraft_id" => spacecraft,
        "requirement_id" => requirement
      }

    defp single(id, at, spacecraft),
      do: %{provider_reservation_id: id, spacecraft_id: spacecraft, starts_at: at}

    test "a single booking covers its spacecraft's nearest lost booking, even with a known requirement" do
      lost = [
        lost_input("lost-0054", at(0, 54), "sc-004"),
        lost_input("lost-2018", at(20, 18), "sc-004")
      ]

      assert RepairPairing.cover(lost, [single("res-single", at(1, 5), "sc-004")]) ==
               %{"lost-0054" => "res-single"}
    end

    test "another spacecraft's booking covers nothing, and extra singles stay unpaired" do
      lost = [lost_input("lost-a", at(9, 0), "sc-004")]

      assert RepairPairing.cover(lost, [single("res-other", at(9, 0), "sc-005")]) == %{}

      assert RepairPairing.cover(lost, [
               single("res-near", at(9, 10), "sc-004"),
               single("res-far", at(15, 0), "sc-004")
             ]) == %{"lost-a" => "res-near"}
    end
  end
end
