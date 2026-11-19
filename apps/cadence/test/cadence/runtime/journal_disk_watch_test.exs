defmodule Cadence.Runtime.JournalDiskWatchTest do
  @moduledoc "The ingress journal's disk as the backpressure monitor watches it (ux U66)."
  use ExUnit.Case, async: true

  alias Cadence.Runtime.JournalDiskWatch

  @t0 ~U[2026-11-15 12:00:00Z]
  @size 100_000_000_000

  defp reading(percent),
    do: {:ok, %{size_bytes: @size, used_bytes: round(@size * percent / 100), percent: percent}}

  defp at(minutes), do: DateTime.add(@t0, minutes * 60, :second)

  defp sample(state, percent, minutes, opts \\ []) do
    JournalDiskWatch.sample(
      state,
      reading(percent),
      Keyword.get(opts, :streams, []),
      Keyword.get(opts, :refusing, false),
      at(minutes)
    )
  end

  describe "levels" do
    test "opens at 70 % (caution), critical at 90 %, and stays open until below 60 %" do
      {state, false} = sample(JournalDiskWatch.new(), 65.0, 0)
      assert JournalDiskWatch.view(state, "m") == nil

      {state, true} = sample(state, 72.0, 1)
      assert %{level: :caution, raised_at: raised} = JournalDiskWatch.view(state, "m")
      assert raised == at(1)

      {state, true} = sample(state, 91.0, 2)
      assert %{level: :critical, raised_at: ^raised} = JournalDiskWatch.view(state, "m")

      # Back under 90 but above 60: caution, still open (no flapping).
      {state, true} = sample(state, 65.0, 3)
      assert %{level: :caution} = JournalDiskWatch.view(state, "m")
      {state, false} = sample(state, 61.0, 4)
      assert %{level: :caution} = JournalDiskWatch.view(state, "m")

      {state, true} = sample(state, 59.0, 5)
      assert JournalDiskWatch.view(state, "m") == nil

      assert [%{resolved_at: resolved_at, refused_from: nil, refused_to: nil}] =
               JournalDiskWatch.resolved(state, at(5))

      assert resolved_at == at(5)
      assert JournalDiskWatch.resolved(state, at(8)) == []
    end

    test "thresholds are config; with a free-space floor, critical also needs little free" do
      # Dev's: 95 / 97 / 93, and critical only with under 10 GB free (lead 11-15).
      t = %{caution: 95.0, critical: 97.0, clear: 93.0, emergency_free_bytes: 10_000_000_000}
      state = JournalDiskWatch.new(t)

      {state, false} = sample(state, 92.0, 0)
      {state, true} = sample(state, 96.0, 1)
      assert %{level: :caution} = JournalDiskWatch.view(state, "m")

      # 98 % of 100 GB leaves 2 GB: under the floor.
      {state, true} = sample(state, 98.0, 2)
      assert %{level: :critical} = JournalDiskWatch.view(state, "m")

      # A huge disk at 98 % with plenty free stays caution.
      big = JournalDiskWatch.new(%{t | emergency_free_bytes: 1_000_000})
      {big, true} = sample(big, 98.0, 0)
      assert %{level: :caution} = JournalDiskWatch.view(big, "m")

      {state, true} = sample(state, 92.9, 3)
      assert JournalDiskWatch.view(state, "m") == nil
    end

    test "an unreadable disk changes nothing" do
      {state, true} = sample(JournalDiskWatch.new(), 75.0, 0)
      {same, false} = JournalDiskWatch.sample(state, :unknown, [], false, at(1))
      assert JournalDiskWatch.view(same, "m") == JournalDiskWatch.view(state, "m")

      {quiet, false} = JournalDiskWatch.sample(JournalDiskWatch.new(), :unknown, [], false, @t0)
      assert JournalDiskWatch.view(quiet, "m") == nil
    end
  end

  describe "rate and eta" do
    test "signed bytes per hour from the last hour, and an eta only while growing" do
      {state, _} = sample(JournalDiskWatch.new(), 70.0, 0)
      assert %{rate_bytes_per_hour: nil, eta_full_s: nil} = JournalDiskWatch.view(state, "m")

      # +1 % of 100 GB in 30 minutes: +2 GB/h; 29 GB left: 14.5 h.
      {state, _} = sample(state, 71.0, 30)
      assert %{rate_bytes_per_hour: rate, eta_full_s: eta} = JournalDiskWatch.view(state, "m")
      assert rate == 2_000_000_000
      assert eta == round(29 * 3_600 / 2)

      # The window is the last hour: 70 → 70.5 over 60 minutes.
      {state, _} = sample(state, 70.5, 60)
      assert %{rate_bytes_per_hour: 500_000_000} = JournalDiskWatch.view(state, "m")

      # Shrinking: a negative rate, no eta.
      {state, _} = sample(state, 69.0, 100)

      assert %{rate_bytes_per_hour: shrinking, eta_full_s: nil} =
               JournalDiskWatch.view(state, "m")

      assert shrinking < 0
    end
  end

  describe "holders" do
    test "a mission names its own contacts (summed over paths), largest 3; others are a sum" do
      streams = [
        %{mission_id: "m", realized_contact_id: "c1", stream_id: "s1", bytes: 100},
        %{mission_id: "m", realized_contact_id: "c1", stream_id: "s2", bytes: 400},
        %{mission_id: "m", realized_contact_id: "c2", stream_id: "s3", bytes: 300},
        %{mission_id: "m", realized_contact_id: "c3", stream_id: "s4", bytes: 200},
        %{mission_id: "m", realized_contact_id: "c4", stream_id: "s5", bytes: 10},
        %{mission_id: "other", realized_contact_id: "x1", stream_id: "s6", bytes: 7_000}
      ]

      {state, _} = sample(JournalDiskWatch.new(), 80.0, 0, streams: streams)
      view = JournalDiskWatch.view(state, "m")

      assert view.holders == [
               %{realized_contact_id: "c1", bytes: 500},
               %{realized_contact_id: "c2", bytes: 300},
               %{realized_contact_id: "c3", bytes: 200}
             ]

      assert view.more_count == 1
      assert view.other_missions_bytes == 7_000
      refute inspect(view) =~ "x1"
      assert Enum.sort(JournalDiskWatch.missions(state)) == ["m", "other"]
    end
  end

  describe "refusing" do
    test "marks when appends fail for lack of space, and the resolution says from when to when" do
      {state, true} = sample(JournalDiskWatch.new(), 99.0, 0, refusing: true)
      assert %{refusing: true, refused_since: since} = JournalDiskWatch.view(state, "m")
      assert since == at(0)

      {state, true} = sample(state, 95.0, 5, refusing: false)
      assert %{refusing: false, refused_since: nil} = JournalDiskWatch.view(state, "m")

      {state, true} = sample(state, 50.0, 10)

      assert [%{refused_from: from, refused_to: to}] = JournalDiskWatch.resolved(state, at(10))
      assert {from, to} == {at(0), at(5)}
    end
  end
end
