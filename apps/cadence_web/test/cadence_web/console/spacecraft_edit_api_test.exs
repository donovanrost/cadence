defmodule CadenceWeb.Console.SpacecraftEditAPITest do
  @moduledoc "L17: the spacecraft kind's form, staging rules, running switches and catalog APIDs."
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, mission: mission, base: "/api/v1/missions/#{mission.mission_id}"}
  end

  test "the spacecraft schema: identity, then the switches with ux's help", c do
    profile = TestFixtures.persist_spacecraft_profile!(c.mission, display_name: "Block 1")
    fields = get_data(c, "/config/kinds/spacecraft/schema")["fields"]

    assert Enum.map(fields, &{&1["path"], &1["section"]}) == [
             {"display_name", "identity"},
             {"scid", "identity"},
             {"spacecraft_type_id", "identity"},
             {"spacecraft_type_version", "identity"},
             {"commanding_enabled", "switches"},
             {"telemetry_enabled", "switches"}
           ]

    by_path = Map.new(fields, &{&1["path"], &1})

    assert by_path["spacecraft_type_id"]["enum"] == [
             %{"value" => profile.spacecraft_type_id, "label" => "Block 1"}
           ]

    assert %{"type" => "boolean", "help" => "Lets operators request and release commands" <> _} =
             by_path["commanding_enabled"]

    assert %{"min" => 0, "max" => 1023} = by_path["scid"]["range"]
  end

  test "an explicit null switch is a 422 naming the op and path", c do
    craft = TestFixtures.persist_spacecraft!(c.mission, display_name: "EARENDIL-010")

    body = %{
      "ops" => [
        %{
          "kind" => "spacecraft",
          "action" => "update",
          "entity_id" => craft.spacecraft_id,
          "changes" => [%{"path" => "telemetry_enabled", "value" => nil}]
        }
      ]
    }

    for path <- ["/config/preview", "/config/stage"] do
      conn = c.user |> TestFixtures.member_conn() |> post(c.base <> path, body)

      assert %{"code" => "invalid_params", "details" => %{"ops.0.changes.telemetry_enabled" => _}} =
               json_response(conn, 422)["error"]
    end
  end

  test "the detail read carries the running switches", c do
    craft = TestFixtures.persist_spacecraft!(c.mission, display_name: "EARENDIL-011")
    data = get_data(c, "/spacecraft/#{craft.spacecraft_id}")

    # No active configuration in this mission yet.
    assert Map.take(data, ["commanding_enabled", "telemetry_enabled"]) == %{
             "commanding_enabled" => nil,
             "telemetry_enabled" => nil
           }
  end

  test "the derived_telemetry schema: a create-only id, a name, a multiline expression", c do
    fields = get_data(c, "/config/kinds/derived_telemetry/schema")["fields"]
    assert Enum.map(fields, & &1["path"]) == ~w(point_id point_name expression)
    assert %{"create_only" => true, "required" => true} = hd(fields)
    assert %{"type" => "text", "required" => true} = List.last(fields)
  end

  test "the limit_definition schema: a create-only point and set, four optional thresholds", c do
    fields = get_data(c, "/config/kinds/limit_definition/schema")["fields"]

    assert Enum.map(fields, & &1["path"]) ==
             ~w(point_id limit_set_name thresholds.red_low thresholds.yellow_low thresholds.yellow_high thresholds.red_high)

    assert %{"create_only" => true} = Enum.at(fields, 0)
    assert %{"create_only" => true, "default" => "DEFAULT"} = Enum.at(fields, 1)
    assert %{"type" => "number", "required" => false} = List.last(fields)
  end

  test "catalog APIDs: an unknown revision is not found", c do
    conn =
      c.user
      |> TestFixtures.member_conn()
      |> get(c.base <> "/catalog/revisions/catalog_revision_nope/apids")

    assert json_response(conn, 404)["error"]["code"] == "catalog_revision_not_found"
  end

  defp get_data(c, path) do
    c.user
    |> TestFixtures.member_conn()
    |> get(c.base <> path)
    |> json_response(200)
    |> Map.fetch!("data")
  end
end
