defmodule Cadence.Reads.OrganizationAudit.ApprovalSettingLinesTest do
  @moduledoc "#233's audit sentences (ux U96) from a governance revision's stored audit."
  use ExUnit.Case, async: true

  alias Cadence.Reads.OrganizationAudit.ApprovalSettingLines, as: Lines

  @mission %{id: "m", name: "EARENDIL"}
  @independent %{"approval_requirement" => "independent"}
  @direct %{"approval_requirement" => "direct"}

  defp mission(before_effective, before_override, after_effective, after_override),
    do: %{
      "scope" => "mission",
      "before" => %{"effective" => before_effective, "override" => before_override},
      "after" => %{"effective" => after_effective, "override" => after_override}
    }

  test "a mission handed back to a looser organization reads as loosened, to its setting" do
    assert {action, change} =
             Lines.line(mission(@independent, @independent, @direct, nil), @mission)

    assert action ==
             "Loosened approval on EARENDIL: Needs a second person's approval → " <>
               "Applies without approval (the organization's setting)"

    assert change == %{
             before: %{approval_requirement: "independent", override: true},
             after: %{approval_requirement: "direct", override: false}
           }
  end

  test "only the override changed: what applies doesn't change" do
    assert {"EARENDIL now uses the organization's approval setting (Needs a second person's approval); what applies doesn't change.",
            _} = Lines.line(mission(@independent, @independent, @independent, nil), @mission)

    assert {"EARENDIL now sets its own approval setting (Needs a second person's approval); what applies doesn't change.",
            _} = Lines.line(mission(@independent, nil, @independent, @independent), @mission)
  end

  test "the organization: value first, then the override sentence; a no-change save says nothing" do
    org = %{
      "scope" => "organization",
      "before" => %{"value" => @independent, "allow_override" => false},
      "after" => %{"value" => @direct, "allow_override" => true}
    }

    assert {action, %{after: %{allow_override: true, approval_requirement: "direct"}}} =
             Lines.line(org, nil)

    assert action ==
             "Loosened approval (organization default): Needs a second person's approval → " <>
               "Applies without approval Missions may now set their own approval setting."

    same = %{org | "after" => org["before"]}
    assert Lines.line(same, nil) == nil
    assert Lines.line(mission(@direct, @direct, @direct, @direct), @mission) == nil
  end

  test "no value before: set, neither loosened nor tightened (api-ops)" do
    org = %{
      "scope" => "organization",
      "before" => %{"value" => nil, "allow_override" => true},
      "after" => %{"value" => @independent, "allow_override" => true}
    }

    assert {"Set approval (organization default): Not set → Needs a second person's approval", _} =
             Lines.line(org, nil)
  end

  test "a revision saved before #233 has no audit" do
    assert Lines.line(nil, @mission) == nil
  end
end
