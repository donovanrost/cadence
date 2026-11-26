defmodule CadenceWeb.Console.BookingResolutionAPITest do
  @moduledoc "#53 resolve from the plan side: request validation and unknown passes."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    alice = TestFixtures.persist_user!(display_name: "Alice")
    TestFixtures.grant_membership!(alice, org)
    mission = TestFixtures.persist_mission!(org)
    %{alice: alice, base: "/api/v1/missions/#{mission.mission_id}/contact-plans"}
  end

  defp resolve(c, body),
    do:
      c.alice
      |> TestFixtures.member_conn()
      |> post(c.base <> "/plan-x/unconfirmed/snap-x/resolve", body)

  test "an unknown action is invalid; a pass that isn't a booking of the plan is not found", c do
    assert %{"error" => %{"code" => "invalid_params", "details" => %{"action" => _}}} =
             c |> resolve(%{"action" => "maybe", "note" => "x"}) |> json_response(422)

    assert %{"error" => %{"code" => "booking_not_found"}} =
             c |> resolve(%{"action" => "booked", "note" => "x"}) |> json_response(404)
  end
end
