defmodule CadenceWeb.Console.ConfigLanesAPITest do
  @moduledoc """
  ADR-020 P3 slice L (#451): `GET …/config?lane=` reads one lane's staged bar. Configuration is the
  default, so today's screens see what they always did; monitoring adds its sets in review.
  """
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    alice = TestFixtures.persist_user!(display_name: "Alice")
    TestFixtures.grant_membership!(alice, org)
    mission = TestFixtures.persist_mission!(org)
    %{alice: alice, base: "/api/v1/missions/#{mission.mission_id}/config"}
  end

  defp read(c, query),
    do: c.alice |> TestFixtures.member_conn() |> get(c.base <> query)

  test "no lane is the configuration lane", c do
    data = c |> read("") |> json_response(200) |> Map.fetch!("data")

    assert %{"lane" => "configuration", "change_set" => nil, "head" => %{}} = data
    refute Map.has_key?(data, "in_review")
  end

  test "the monitoring lane carries its sets in review", c do
    assert %{
             "lane" => "monitoring",
             "change_set" => nil,
             "in_review" => [],
             "in_review_count" => 0
           } =
             c |> read("?lane=monitoring") |> json_response(200) |> Map.fetch!("data")
  end

  test "an unknown lane is refused", c do
    assert %{"error" => %{"code" => "invalid_lane"}} =
             c |> read("?lane=telemetry") |> json_response(422)
  end
end
