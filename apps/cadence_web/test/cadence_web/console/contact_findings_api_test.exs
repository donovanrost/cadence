defmodule CadenceWeb.Console.ContactFindingsAPITest do
  @moduledoc "M22 (Contacts D4): double-bookings, outage bookings and coverage gaps."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{
      org: org,
      user: user,
      mission: mission,
      base: "/api/console/v1/missions/#{mission.mission_id}"
    }
  end

  defp findings(c, query \\ ""),
    do:
      c.user
      |> TestFixtures.member_conn()
      |> get(c.base <> "/contact-findings" <> query)
      |> json_response(200)
      |> Map.fetch!("data")

  test "a spacecraft with no pass for longer than max_gap_s is a coverage gap", c do
    craft = TestFixtures.persist_spacecraft!(c.mission, display_name: "SC-GAP")

    assert %{"counts" => %{"gaps" => 1, "conflicts" => 0}, "findings" => [gap]} = findings(c)
    craft_id = craft.spacecraft_id

    assert %{
             "kind" => "coverage_gap",
             "severity" => "critical",
             "fix" => nil,
             "spacecraft" => %{"id" => ^craft_id}
           } =
             gap

    assert gap["message"] =~ "has no pass for"
    assert %{"counts" => %{"gaps" => 0}} = findings(c, "?max_gap_s=86400")

    assert c.user
           |> TestFixtures.member_conn()
           |> get(c.base <> "/contact-findings?max_gap_s=5")
           |> json_response(422)
  end
end
