defmodule Cadence.ContactPlanning.PolicyNarrowingTest do
  use Cadence.UnitCase, async: true

  alias Cadence.ContactPlanning.PolicyNarrowing

  @mission_policy %{
    "version" => 1,
    "mode" => "bounded_automatic",
    "maximum_later_start_shift_seconds" => 120,
    "minimum_retained_duration_seconds" => 600,
    "approved_station_substitutions" => ["station-a", "station-b"],
    "allow_automatic_execution_revision" => true
  }

  test "Requirement restrictions produce an explicit effective policy" do
    assert {:ok, effective} =
             PolicyNarrowing.narrow(@mission_policy, %{
               "mode" => "approval_required",
               "maximum_later_start_shift_seconds" => 60,
               "minimum_retained_duration_seconds" => 900,
               "approved_station_substitutions" => ["station-a"],
               "allow_automatic_execution_revision" => false
             })

    assert effective["mode"] == "approval_required"
    assert effective["maximum_later_start_shift_seconds"] == 60
    assert effective["minimum_retained_duration_seconds"] == 900
    assert effective["approved_station_substitutions"] == ["station-a"]
    refute effective["allow_automatic_execution_revision"]
  end

  test "a Requirement cannot widen timing, station, or automation policy" do
    assert {:error,
            {:contact_requirement_policy_widens_mission_policy,
             "maximum_later_start_shift_seconds"}} =
             PolicyNarrowing.narrow(@mission_policy, %{
               "maximum_later_start_shift_seconds" => 121
             })

    assert {:error,
            {:contact_requirement_policy_widens_mission_policy, "approved_station_substitutions"}} =
             PolicyNarrowing.narrow(@mission_policy, %{
               "approved_station_substitutions" => ["station-c"]
             })

    assert {:error,
            {:contact_requirement_policy_widens_mission_policy,
             "allow_automatic_execution_revision"}} =
             PolicyNarrowing.narrow(
               Map.put(@mission_policy, "allow_automatic_execution_revision", false),
               %{"allow_automatic_execution_revision" => true}
             )
  end
end
