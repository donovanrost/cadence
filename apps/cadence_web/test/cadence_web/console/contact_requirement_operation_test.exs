defmodule CadenceWeb.Console.ContactRequirementOperationTest do
  @moduledoc "Idempotent requirement creates: an optional operation_id (qa's P4 duplicates)."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    member = TestFixtures.persist_user!(display_name: "Mia")
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "SC-1")

    %{
      member: member,
      craft: craft,
      base: "/api/v1/missions/#{mission.mission_id}/contact-planning/requirements"
    }
  end

  defp create(c, operation_id) do
    body = %{
      "operation_id" => operation_id,
      "content" => %{
        "spacecraft_id" => c.craft.spacecraft_id,
        "earliest_start" => "2027-01-02T00:00:00Z",
        "latest_end" => "2027-01-02T12:00:00Z",
        "service_direction" => "downlink",
        "success_measure" => "minimum_duration",
        "minimum_duration_seconds" => 300,
        "preferred_duration_seconds" => 600,
        "contact_count" => 1,
        "priority" => "high",
        "rationale" => "Payload dump"
      }
    }

    c.member |> TestFixtures.member_conn() |> post(c.base, body)
  end

  test "a replay answers 409 duplicate_operation naming the requirement it made", c do
    assert %{"id" => id, "version" => 1} = json_response(create(c, "op-1"), 201)["data"]

    assert %{"code" => "duplicate_operation", "details" => %{"requirement_id" => ^id}} =
             json_response(create(c, "op-1"), 409)["error"]

    assert %{"id" => other} = json_response(create(c, "op-2"), 201)["data"]
    assert other != id

    # Without one, every create is new (the old contract).
    assert %{"id" => _} = json_response(create(c, nil), 201)["data"]
    assert %{"id" => _} = json_response(create(c, nil), 201)["data"]
  end

  test "an operation_id must be text", c do
    assert %{"code" => "invalid_params", "details" => %{"operation_id" => _}} =
             json_response(create(c, 42), 422)["error"]
  end
end
