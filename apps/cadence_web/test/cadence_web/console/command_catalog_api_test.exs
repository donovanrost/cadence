defmodule CadenceWeb.Console.CommandCatalogAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ExactCommandAuthoringFixtures
  alias CadenceWeb.TestFixtures

  @maximum 18_446_744_073_709_551_615

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, org: org, mission: mission}
  end

  defp get_json(c, path) do
    c.user
    |> TestFixtures.member_conn()
    |> get("/api/v1/missions/#{c.mission.mission_id}" <> path)
  end

  describe "with an active catalog" do
    setup c do
      model = ExactCommandAuthoringFixtures.activate!(c.org.organization_id, c.mission.mission_id)
      %{ids: model.commands_by_name}
    end

    test "lists commands with hazard flags and a cursor", c do
      body = c |> get_json("/commands?limit=2") |> json_response(200)

      assert %{"state" => "active", "revision_id" => revision} = body["data"]
      assert is_binary(revision)
      # The fixture composes its model without a catalog import, so no human revision exists.
      assert Map.fetch!(body["data"], "catalog_revision") == nil
      assert length(body["data"]["commands"]) == 2
      assert is_binary(body["meta"]["next_cursor"])

      all = c |> get_json("/commands?q=set_") |> json_response(200)
      counter = Enum.find(all["data"]["commands"], &(&1["name"] == "SET_COUNTER"))

      assert %{"hazardous" => true, "second_go_required" => true, "argument_count" => 2} = counter
    end

    test "shows one command with exact 64-bit argument values", c do
      data =
        c
        |> get_json("/commands/#{c.ids["SET_COUNTER"]}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert %{"name" => "SET_COUNTER", "arguments" => [amount, counter]} = data["command"]
      assert amount["type"] == "integer"
      assert counter["default_value_json"] == Integer.to_string(@maximum)
      assert counter["choices"] == []
      assert Map.has_key?(counter, "valid_range")
      assert Map.has_key?(counter, "unit")
      # Compose B2: no verifier ties these arguments to a point, so there's no Now column.
      assert counter["current_point"] == nil
      assert is_list(data["command"]["verifiers"])

      enum =
        c
        |> get_json("/commands/#{c.ids["SET_ENUM"]}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert [%{"choices" => [%{"value_json" => value}]}] = enum["command"]["arguments"]
      assert value == Integer.to_string(@maximum)
    end

    test "unknown commands and bad limits are errors", c do
      assert %{"error" => %{"code" => "command_not_found"}} =
               c |> get_json("/commands/cmd_missing") |> json_response(404)

      assert %{"error" => %{"code" => "invalid_params", "details" => %{"limit" => _}}} =
               c |> get_json("/commands?limit=0") |> json_response(422)
    end
  end

  test "a mission with nothing active says so", c do
    assert %{"data" => %{"state" => "not_active", "commands" => []}} =
             c |> get_json("/commands") |> json_response(200)

    assert %{"data" => %{"state" => "not_active", "command" => nil}} =
             c |> get_json("/commands/anything") |> json_response(200)
  end

  test "is not available for another organization's mission", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert %{"error" => %{"code" => "mission_not_found"}} =
             c.user
             |> TestFixtures.member_conn()
             |> get("/api/v1/missions/#{stranger.mission_id}/commands")
             |> json_response(404)
  end
end
