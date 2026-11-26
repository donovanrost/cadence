defmodule CadenceWeb.Console.CommandEncodingAPITest do
  @moduledoc "M24 encode preview: the payload release would send, from the request's revision."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.{CommandAuthoringFixtures, CommandGroupFixtures, ExactCommandAuthoringFixtures}
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    requester = TestFixtures.persist_user!(display_name: "Requester")
    TestFixtures.grant_membership!(requester, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "SC-1")

    endpoint =
      CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
        spacecraft_id: craft.spacecraft_id
      })

    CommandGroupFixtures.commandable_pass!(
      org.organization_id,
      mission.mission_id,
      craft.spacecraft_id
    )

    %{
      org: org,
      mission: mission,
      requester: requester,
      base: "/api/v1/missions/#{mission.mission_id}",
      ids: model.commands_by_name,
      spacecraft_id: craft.spacecraft_id,
      target: %{
        "spacecraft_id" => craft.spacecraft_id,
        "source_endpoint_id" => endpoint.source_endpoint_id
      }
    }
  end

  defp conn(c), do: TestFixtures.member_conn(c.requester)

  defp request_id(c) do
    body = %{
      "title" => "Encode me",
      "targets" => [c.target],
      "commands" => [
        %{
          "command_id" => c.ids["SET_SIGNED"],
          "argument_values_json" => Jason.encode!(%{"counter" => 7})
        }
      ]
    }

    pre = c |> conn() |> post(c.base <> "/command-groups/preflight", body) |> json_response(200)

    acks =
      for %{"result" => "hold", "ackable" => true} = check <- pre["data"]["checks"],
          do: %{"key" => check["key"], "hold_basis" => check["hold_basis"], "note" => "Seen."}

    created =
      c
      |> conn()
      |> post(
        c.base <> "/command-groups",
        Map.merge(body, %{
          "preflight_digest" => pre["data"]["digest"],
          "acknowledged_holds" => acks
        })
      )
      |> json_response(201)

    [%{"members" => [%{"request_id" => id}]} | _] = created["data"]["targets"]
    id
  end

  test "shows the payload bytes for the request's own revision; unknown requests 404", c do
    id = request_id(c)

    assert %{
             "command_request_id" => ^id,
             "scope" => "command_payload",
             "size_bytes" => size,
             "hex" => hex,
             "base64" => base64,
             "arguments_json" => args_json
           } =
             c
             |> conn()
             |> get(c.base <> "/command-requests/#{id}/encoding")
             |> json_response(200)
             |> Map.fetch!("data")

    assert size > 0
    assert Jason.decode!(args_json) == %{"counter" => 7}
    assert Base.decode16!(hex) == Base.decode64!(base64)
    assert byte_size(Base.decode16!(hex)) == size

    assert %{"error" => %{"code" => "command_request_not_found"}} =
             c |> conn() |> get(c.base <> "/command-requests/nope/encoding") |> json_response(404)
  end

  test "never encodes against another revision: a superseded request fails closed", c do
    id = request_id(c)

    # A new activation (an extra command) makes a new active model revision.
    ExactCommandAuthoringFixtures.activate!(c.org.organization_id, c.mission.mission_id, """
      - name: EXTRA_PING
        opcode: 99
        parameters: []
    """)

    assert %{"error" => %{"code" => "encode_unavailable", "details" => %{"reason" => reason}}} =
             c
             |> conn()
             |> get(c.base <> "/command-requests/#{id}/encoding")
             |> json_response(409)

    assert reason in ["revision_superseded", "revision_not_active"]

    # The brief still names the values, as JSON text, with no current value (api-ops review).
    assert %{
             "arguments" => [
               %{"name" => "counter", "value_json" => "7", "current_basis" => "unavailable"}
             ]
           } =
             c
             |> conn()
             |> get(c.base <> "/command-requests/#{id}/brief")
             |> json_response(200)
             |> Map.fetch!("data")
  end

  test "the brief names the spacecraft, each argument's value, and the command's prior requests",
       c do
    first = request_id(c)
    second = request_id(c)

    assert %{
             "command_request_id" => ^second,
             "spacecraft_id" => spacecraft_id,
             "arguments" => [
               %{
                 "name" => "counter",
                 "value_json" => "7",
                 "current" => nil,
                 "current_basis" => "none"
               }
             ],
             "prior_requests" => [%{"command_request_id" => ^first, "arguments_json" => args}]
           } =
             c
             |> conn()
             |> get(c.base <> "/command-requests/#{second}/brief")
             |> json_response(200)
             |> Map.fetch!("data")

    assert spacecraft_id == c.spacecraft_id
    assert Jason.decode!(args) == %{"counter" => 7}

    # Never released: nothing reached the spacecraft (fe-ops, #38).
    assert [%{"reached_target" => nil}] =
             c
             |> conn()
             |> get(c.base <> "/command-requests/#{second}/brief")
             |> json_response(200)
             |> get_in(["data", "prior_requests"])

    assert c |> conn() |> get(c.base <> "/command-requests/nope/brief") |> json_response(404)
  end
end
