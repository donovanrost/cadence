defmodule Cadence.Reads.PlanMeasuresTest do
  use ExUnit.Case, async: true

  alias Cadence.ContactPlanning.ContactOpportunitySnapshot
  alias Cadence.Reads.PlanMeasures

  @day {~U[2027-01-01 00:00:00Z], ~U[2027-01-02 00:00:00Z]}

  defp pass(id, from, to, opts \\ []) do
    %ContactOpportunitySnapshot{
      contact_opportunity_snapshot_id: id,
      starts_at: at(from),
      ends_at: at(to),
      expires_at: at(Keyword.get(opts, :expires, from)),
      route_binding_document: %{"provider_id" => Keyword.get(opts, :provider, "provider-a")}
    }
  end

  defp at(time), do: DateTime.new!(~D[2027-01-01], time, "Etc/UTC")

  describe "day/1" do
    test "is the UTC day of the earliest pass, or nil without passes" do
      assert PlanMeasures.day([
               pass("b", ~T[18:00:00], ~T[18:10:00]),
               pass("a", ~T[02:00:00], ~T[02:10:00])
             ]) ==
               @day

      assert PlanMeasures.day([]) == nil
    end
  end

  describe "longest_gap/2" do
    test "runs LOS to next AOS, the day's edges included" do
      passes = [
        pass("a", ~T[02:00:00], ~T[02:10:00]),
        pass("b", ~T[20:00:00], ~T[20:10:00]),
        pass("c", ~T[08:00:00], ~T[08:10:00])
      ]

      assert PlanMeasures.longest_gap(passes, @day) == %{
               seconds: 11 * 3600 + 50 * 60,
               limit_seconds: nil,
               from: at(~T[08:10:00]),
               to: at(~T[20:00:00])
             }
    end

    test "counts the stretch from the last LOS to the day's end" do
      assert %{seconds: 81_900, from: from, to: ~U[2027-01-02 00:00:00Z]} =
               PlanMeasures.longest_gap([pass("a", ~T[01:00:00], ~T[01:15:00])], @day)

      assert from == at(~T[01:15:00])
    end

    test "overlapping passes don't open a gap between them" do
      passes = [
        pass("a", ~T[00:00:00], ~T[12:00:00]),
        pass("b", ~T[06:00:00], ~T[10:00:00]),
        pass("c", ~T[11:00:00], ~T[23:00:00])
      ]

      assert %{seconds: 3600, from: from} = PlanMeasures.longest_gap(passes, @day)
      assert from == at(~T[23:00:00])
    end

    test "a day with no pass is one gap; no day is nil" do
      assert %{seconds: 86_400} = PlanMeasures.longest_gap([], @day)
      assert PlanMeasures.longest_gap([], nil) == nil
    end
  end

  describe "provider_freeze/2" do
    test "is the earliest offer expiry, overall and per provider" do
      unsent = [
        pass("a", ~T[10:00:00], ~T[10:10:00], expires: ~T[09:00:00], provider: "ksat"),
        pass("b", ~T[04:00:00], ~T[04:10:00], expires: ~T[03:30:00], provider: "aws"),
        pass("c", ~T[06:00:00], ~T[06:10:00], expires: ~T[05:00:00], provider: "ksat")
      ]

      assert PlanMeasures.provider_freeze(unsent, %{"ksat" => "KSAT"}) == %{
               at: at(~T[03:30:00]),
               provider: %{id: "aws", name: nil},
               snapshot_id: "b",
               by_provider: [
                 %{provider: %{id: "aws", name: nil}, at: at(~T[03:30:00])},
                 %{provider: %{id: "ksat", name: "KSAT"}, at: at(~T[05:00:00])}
               ]
             }
    end

    test "is nil when nothing is left to send" do
      assert PlanMeasures.provider_freeze([], %{}) == nil
    end
  end
end
