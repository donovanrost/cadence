defmodule CadenceWeb.Console.ResolvedArgumentsAPITest do
  @moduledoc "U68: resolved_arguments on preflight and the group read; priority on list rows."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.{CommandAuthoringFixtures, CommandGroupFixtures, ExactCommandAuthoringFixtures}
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(display_name: "Requester")
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)

    crafts =
      for i <- 1..2 do
        craft = TestFixtures.persist_spacecraft!(mission, display_name: "SC-#{i}")

        endpoint =
          CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
            spacecraft_id: craft.spacecraft_id
          })

        CommandGroupFixtures.commandable_pass!(
          org.organization_id,
          mission.mission_id,
          craft.spacecraft_id
        )

        {craft.spacecraft_id, endpoint.source_endpoint_id}
      end

    %{user: user, mission: mission, ids: model.commands_by_name, crafts: crafts}
  end

  test "a default the server filled reads in Arm and Approve; the list row carries priority", c do
    [{one, _}, {two, _}] = c.crafts

    body = %{
      "title" => "Counter reset",
      "log_entry" => "Counter reset",
      "priority" => 1,
      "targets" =>
        Enum.map(c.crafts, fn {id, endpoint} ->
          %{"spacecraft_id" => id, "source_endpoint_id" => endpoint}
        end),
      "commands" => [
        %{
          "command_id" => c.ids["SET_COUNTER"],
          "argument_values_json" => ~s({"amount":1}),
          "per_target" => [
            %{"spacecraft_id" => two, "argument_values_json" => ~s({"amount":1,"counter":5})}
          ]
        }
      ]
    }

    pre = post(conn(c), base(c) <> "/preflight", body) |> json_response(200) |> Map.get("data")

    assert [%{"position" => 0, "resolved_arguments" => [row]}] = pre["commands"]

    assert %{
             "name" => "counter",
             "entered_value_json" => nil,
             "sent_value_json" => nil,
             "source" => "default",
             "spacecraft_ids" => [^one]
           } = row

    assert is_binary(row["resolved_value_json"])

    acks =
      for %{"result" => "hold", "ackable" => true} = check <- pre["checks"],
          do: %{"key" => check["key"], "hold_basis" => check["hold_basis"], "note" => "Seen."}

    id =
      conn(c)
      |> post(
        base(c),
        Map.merge(body, %{"preflight_digest" => pre["digest"], "acknowledged_holds" => acks})
      )
      |> json_response(201)
      |> get_in(["data", "id"])

    shown = conn(c) |> get(base(c) <> "/" <> id) |> json_response(200) |> Map.get("data")
    assert [%{"resolved_arguments" => [^row]}] = shown["commands"]

    listed = conn(c) |> get(base(c)) |> json_response(200) |> get_in(["data", "groups"])
    assert [%{"id" => ^id, "priority" => 1}] = listed
  end

  defp base(c), do: "/api/v1/missions/#{c.mission.mission_id}/command-groups"
  defp conn(c), do: TestFixtures.member_conn(c.user)
end
