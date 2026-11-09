defmodule CadenceWeb.Console.CommandGroupAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.{CommandAuthoringFixtures, ExactCommandAuthoringFixtures}
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    requester = TestFixtures.persist_user!(display_name: "Requester")
    approver = TestFixtures.persist_user!(display_name: "Approver")
    TestFixtures.grant_membership!(requester, org, role: :organization_admin)
    TestFixtures.grant_membership!(approver, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)

    crafts =
      for i <- 1..2 do
        craft = TestFixtures.persist_spacecraft!(mission, display_name: "SC-#{i}")

        endpoint =
          CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
            spacecraft_id: craft.spacecraft_id
          })

        {craft.spacecraft_id, endpoint.source_endpoint_id}
      end

    %{
      requester: requester,
      approver: approver,
      mission: mission,
      ids: model.commands_by_name,
      crafts: crafts
    }
  end

  defp base(c), do: "/api/console/v1/missions/#{c.mission.mission_id}"
  defp as(user), do: TestFixtures.member_conn(user)

  defp body(c, command, args, extra \\ %{}) do
    Map.merge(
      %{
        "title" => "Load shed",
        "targets" =>
          Enum.map(c.crafts, fn {id, endpoint} ->
            %{"spacecraft_id" => id, "source_endpoint_id" => endpoint}
          end),
        "commands" => [
          %{"command_id" => c.ids[command], "argument_values_json" => Jason.encode!(args)}
        ]
      },
      extra
    )
  end

  defp preflight(c, body),
    do:
      as(c.requester) |> post(base(c) <> "/command-groups/preflight", body) |> json_response(200)

  defp create(c, body) do
    digest = preflight(c, body)["data"]["digest"]

    as(c.requester)
    |> post(base(c) <> "/command-groups", Map.put(body, "preflight_digest", digest))
  end

  test "preflight, submit and show a routine group", c do
    pre = preflight(c, body(c, "SET_SIGNED", %{"counter" => 1}))["data"]
    assert pre["valid"] == true
    assert pre["members"] == 2
    assert Enum.find(pre["checks"], &(&1["key"] == "two_person"))["result"] == "go"

    data =
      c
      |> create(body(c, "SET_SIGNED", %{"counter" => 1}))
      |> json_response(201)
      |> Map.fetch!("data")

    assert data["state"] == "queued"
    assert [%{"stage" => "queued_for_contact", "members" => [_]}, _] = data["targets"]
    assert [%{"argument_values_json" => ~s({"counter":1})}] = data["commands"]
    assert is_binary(data["review_token"])
  end

  test "a hazardous group goes through the second operator's GO", c do
    data =
      c
      |> create(body(c, "SET_COUNTER", %{"amount" => 2}, %{"log_entry" => "Reset"}))
      |> json_response(201)
      |> Map.fetch!("data")

    assert data["state"] == "approval_pending"
    id = data["id"]

    assert %{"error" => %{"code" => "command_group_self_approval_not_allowed"}} =
             as(c.requester)
             |> post(base(c) <> "/command-groups/#{id}/decision", %{"kind" => "go"})
             |> json_response(403)

    assert %{"data" => %{"groups" => [%{"id" => ^id, "awaiting_me" => true}]}} =
             as(c.approver)
             |> get(base(c) <> "/command-groups?awaiting_me=true")
             |> json_response(200)

    review =
      as(c.approver) |> get(base(c) <> "/command-groups/#{id}/preflight") |> json_response(200)

    assert Enum.find(review["data"]["checks"], &(&1["key"] == "changed_since_submit"))["result"] ==
             "go"

    decided =
      as(c.approver)
      |> post(base(c) <> "/command-groups/#{id}/decision", %{
        "kind" => "go",
        "expected_review" => data["review_token"]
      })
      |> json_response(200)

    assert decided["data"]["state"] == "queued"
  end

  test "abort, cancel and policies", c do
    data =
      c
      |> create(body(c, "SET_SIGNED", %{"counter" => 3}))
      |> json_response(201)
      |> Map.fetch!("data")

    [%{"members" => [%{"request_id" => request_id}]} | _] = data["targets"]

    assert %{"data" => %{"state" => "canceled"}} =
             as(c.approver)
             |> post(base(c) <> "/command-requests/#{request_id}/cancel", %{
               "reason" => "Not needed"
             })
             |> json_response(200)

    aborted =
      as(c.approver)
      |> post(base(c) <> "/command-groups/#{data["id"]}/abort", %{"reason" => "Stand down"})
      |> json_response(200)

    assert aborted["data"]["state"] == "aborted"
    assert aborted["data"]["abort_result"] == %{"canceled" => 1, "already_started" => []}

    noted =
      as(c.requester)
      |> post(base(c) <> "/command-groups/#{data["id"]}/notes", %{
        "note" => "Logged for the shift"
      })
      |> json_response(200)

    assert Enum.any?(noted["data"]["events"], &(&1["kind"] == "note"))

    assert %{"error" => %{"code" => "note_required"}} =
             as(c.requester)
             |> post(base(c) <> "/command-groups/#{data["id"]}/notes", %{"note" => " "})
             |> json_response(422)

    assert %{"data" => %{"policies" => policies}} =
             as(c.requester) |> get(base(c) <> "/command-policies") |> json_response(200)

    assert %{"parameters" => %{"threshold" => 10}} =
             Enum.find(policies, &(&1["key"] == "fleet_reach"))
  end

  test "errors: stale preflight, bad params, replay, unknown group", c do
    stale =
      as(c.requester)
      |> post(
        base(c) <> "/command-groups",
        Map.put(body(c, "SET_SIGNED", %{"counter" => 1}), "preflight_digest", "old")
      )

    assert %{"error" => %{"code" => "preflight_stale"}} = json_response(stale, 409)

    bad =
      as(c.requester)
      |> post(base(c) <> "/command-groups/preflight", %{"targets" => [], "commands" => []})

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"targets" => _}}} =
             json_response(bad, 422)

    replay = body(c, "SET_SIGNED", %{"counter" => 4}, %{"operation_id" => "op-9"})
    assert json_response(create(c, replay), 201)

    assert %{
             "error" => %{
               "code" => "duplicate_operation",
               "details" => %{"command_group_id" => _}
             }
           } = json_response(create(c, replay), 409)

    assert %{"data" => %{"groups" => [_]}} =
             as(c.requester)
             |> get(base(c) <> "/command-groups?operation_id=op-9")
             |> json_response(200)

    assert %{"error" => %{"code" => "command_group_not_found"}} =
             as(c.requester) |> get(base(c) <> "/command-groups/nope") |> json_response(404)
  end

  test "command endpoints: route resolution and candidates per spacecraft", c do
    [{id, endpoint} | _] = c.crafts

    data =
      as(c.requester)
      |> get(base(c) <> "/command-endpoints?spacecraft_ids=#{id}")
      |> json_response(200)
      |> Map.fetch!("data")

    # The fixture spacecraft have endpoints but no routing rules.
    assert [
             %{
               "spacecraft_id" => ^id,
               "failure" => "no_uplink_route",
               "resolved_source_endpoint_id" => nil
             } = row
           ] =
             data["spacecraft"]

    assert [%{"id" => ^endpoint, "managed" => false}] = row["endpoints"]

    # Without an explicit endpoint, preflight says the same thing.
    pre =
      preflight(
        c,
        Map.put(body(c, "SET_SIGNED", %{"counter" => 1}), "targets", [%{"spacecraft_id" => id}])
      )

    identity = Enum.find(pre["data"]["checks"], &(&1["key"] == "identity"))

    assert %{
             "result" => "no_go",
             "per_target" => [%{"reason" => "no_uplink_route", "routes" => []}]
           } = identity
  end
end
