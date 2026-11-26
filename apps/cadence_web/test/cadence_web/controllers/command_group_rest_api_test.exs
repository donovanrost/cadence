defmodule CadenceWeb.CommandGroupRestApiTest do
  @moduledoc """
  #708: a service identity commands through a command group, over REST. One target and one
  command is a group of one. The service requests and never decides; a person's GO is always
  needed; the service's issuer and rotators cannot give it; the requester is the bearer, never a
  field of the body.
  """
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.ControlPlaneApiFixtures, only: [authorize: 2]

  alias Cadence.{CommandAuthoringFixtures, ExactCommandAuthoringFixtures, ServiceIdentityFixtures}
  alias Cadence.Auth.{Scope, ServiceIdentity, ServiceIdentityKeys}
  alias CadenceWeb.TestFixtures

  setup %{conn: conn} do
    org = TestFixtures.persist_org!()
    issuer = TestFixtures.persist_user!(display_name: "Issuer")
    rotator = TestFixtures.persist_user!(display_name: "Rotator")
    approver = TestFixtures.persist_user!(display_name: "Approver")

    for user <- [issuer, rotator, approver],
        do: TestFixtures.grant_membership!(user, org, role: :organization_admin)

    mission = TestFixtures.persist_mission!(org)
    other_mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)

    craft = TestFixtures.persist_spacecraft!(mission, display_name: "SC-1")

    endpoint =
      CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
        spacecraft_id: craft.spacecraft_id
      })

    Cadence.CommandGroupFixtures.commandable_pass!(
      org.organization_id,
      mission.mission_id,
      craft.spacecraft_id
    )

    {:ok, %{service_identity: service, api_token: token}} =
      Cadence.Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          display_name: "Pass scripts",
          capabilities: [:mission_admin]
        }),
        user_scope(org, issuer)
      )

    %{
      conn: conn,
      org: org,
      mission: mission,
      other_mission: other_mission,
      issuer: issuer,
      rotator: rotator,
      approver: approver,
      service: service,
      token: token,
      ids: model.commands_by_name,
      craft: {craft.spacecraft_id, endpoint.source_endpoint_id}
    }
  end

  defp user_scope(org, user),
    do: %Scope{actor_kind: :user, organization_id: org.organization_id, user: user}

  defp rest(c, mission \\ nil),
    do:
      "/api/organizations/#{c.org.organization_id}/missions/#{(mission || c.mission).mission_id}"

  defp console(c), do: "/api/console/v1/missions/#{c.mission.mission_id}"

  defp as_service(c, token \\ nil), do: authorize(c.conn, token || c.token)

  # A routine command to one target: with a person requesting, nothing needs a second GO.
  defp body(c, extra \\ %{}) do
    {spacecraft_id, endpoint} = c.craft

    Map.merge(
      %{
        "title" => "Counter bump",
        "log_entry" => "Scripted pass setup.",
        "targets" => [%{"spacecraft_id" => spacecraft_id, "source_endpoint_id" => endpoint}],
        "commands" => [
          %{
            "command_id" => c.ids["SET_SIGNED"],
            "argument_values_json" => Jason.encode!(%{"counter" => 1})
          }
        ]
      },
      extra
    )
  end

  defp preflight(c, body, token \\ nil),
    do:
      c
      |> as_service(token)
      |> post(rest(c) <> "/command_groups/preflight", body)
      |> json_response(200)
      |> Map.fetch!("data")

  defp submit(c, body, token \\ nil) do
    pre = preflight(c, body, token)

    acks =
      for %{"result" => "hold", "ackable" => true} = check <- pre["checks"],
          do: %{"key" => check["key"], "hold_basis" => check["hold_basis"], "note" => "Seen."}

    c
    |> as_service(token)
    |> post(
      rest(c) <> "/command_groups",
      Map.merge(body, %{"preflight_digest" => pre["digest"], "acknowledged_holds" => acks})
    )
  end

  defp created!(c, extra \\ %{}), do: c |> submit(body(c, extra)) |> json_response(201)

  defp decide(c, user, id, kind \\ "go"),
    do:
      TestFixtures.member_conn(user)
      |> post(console(c) <> "/command-groups/#{id}/decision", %{"kind" => kind})

  test "a service requests a group of one; its preflight says a person must give the GO", c do
    pre = preflight(c, body(c))

    assert pre["second_go_required"] == true
    assert %{"result" => "second_go"} = Enum.find(pre["checks"], &(&1["key"] == "two_person"))

    assert Enum.any?(
             get_in(pre, ["checks", Access.all(), "evidence", "reasons"]) |> List.flatten(),
             &(is_map(&1) and &1["key"] == "service_requester")
           )
  end

  test "creating over REST makes a group, requested by the bearer, waiting for a person", c do
    assert %{"data" => %{"id" => id, "state" => "approval_pending"} = group} = created!(c)
    assert group["requested_by"]["service_identity_id"] == c.service.service_identity_id
    assert group["requested_by"]["actor_kind"] == "service"

    assert %{"data" => %{"id" => ^id, "state" => "approval_pending"}} =
             c |> as_service() |> get(rest(c) <> "/command_groups/#{id}") |> json_response(200)

    assert %{"data" => %{"groups" => [%{"id" => ^id}]}} =
             c |> as_service() |> get(rest(c) <> "/command_groups") |> json_response(200)

    # The member is a request of the group; nothing was queued without a person.
    assert %{
             "data" => [%{"lifecycle_state" => state} = member],
             "meta" => %{"next_cursor" => nil}
           } =
             c
             |> as_service()
             |> get(rest(c) <> "/command_requests?command_group_id=#{id}")
             |> json_response(200)

    assert state in ["approval_pending", "validated"]
    assert member["command_request_id"]

    assert %{"data" => []} =
             c
             |> as_service()
             |> get(rest(c) <> "/command_queue_entries")
             |> json_response(200)
  end

  test "the same routine command from a person is queued with no second GO (the control)", c do
    user_conn = TestFixtures.member_conn(c.issuer)
    {spacecraft_id, endpoint} = c.craft

    draft = body(c) |> Map.delete("log_entry")

    pre =
      user_conn
      |> post(console(c) <> "/command-groups/preflight", draft)
      |> json_response(200)
      |> Map.fetch!("data")

    assert pre["second_go_required"] == false

    assert %{"data" => %{"state" => "queued"}} =
             user_conn
             |> post(
               console(c) <> "/command-groups",
               Map.merge(draft, %{"preflight_digest" => pre["digest"], "acknowledged_holds" => []})
             )
             |> json_response(201)

    assert spacecraft_id && endpoint
  end

  test "an actor in the body is refused and nothing is created", c do
    for field <- ["requested_by", "actor", "actor_kind", "user_id", "service_identity_id"] do
      assert %{"error" => %{"code" => "actor_not_assignable"}} =
               c
               |> as_service()
               |> post(rest(c) <> "/command_groups", body(c, %{field => "someone-else"}))
               |> json_response(422)

      assert %{"error" => %{"code" => "actor_not_assignable"}} =
               c
               |> as_service()
               |> post(rest(c) <> "/command_groups/preflight", body(c, %{field => %{}}))
               |> json_response(422)
    end

    assert %{"data" => %{"groups" => []}} =
             c |> as_service() |> get(rest(c) <> "/command_groups") |> json_response(200)
  end

  test "a service is held to its own mission and organization", c do
    assert %{"error" => %{"code" => "forbidden"}} =
             c
             |> as_service()
             |> post(rest(c, c.other_mission) <> "/command_groups/preflight", body(c))
             |> json_response(403)

    assert %{"error" => %{"code" => "forbidden"}} =
             c
             |> as_service()
             |> post(rest(c, c.other_mission) <> "/command_groups", body(c))
             |> json_response(403)

    assert %{"error" => %{"code" => "scope_mismatch"}} =
             c
             |> as_service()
             |> post(
               "/api/organizations/org-other/missions/#{c.mission.mission_id}/command_groups",
               body(c)
             )
             |> json_response(403)

    assert c.conn |> post(rest(c) <> "/command_groups", body(c)) |> response(401)
  end

  test "an operation id is scoped to the mission and replays answer duplicate_operation", c do
    assert %{"data" => %{"id" => id}} = created!(c, %{"operation_id" => "op-1"})

    assert %{
             "error" => %{
               "code" => "duplicate_operation",
               "details" => %{"command_group_id" => ^id}
             }
           } =
             c |> submit(body(c, %{"operation_id" => "op-1"})) |> json_response(409)

    assert %{"data" => %{"groups" => [%{"id" => ^id}]}} =
             c
             |> as_service()
             |> get(rest(c) <> "/command_groups?operation_id=op-1")
             |> json_response(200)
  end

  test "the issuer and a rotator cannot give the GO; another person can (#622)", c do
    {:ok, %{api_token: token}} =
      ServiceIdentityKeys.rotate(
        c.org.organization_id,
        c.service.service_identity_id,
        user_scope(c.org, c.rotator)
      )

    assert %{"data" => %{"id" => id}} = c |> submit(body(c), token) |> json_response(201)

    for person <- [c.issuer, c.rotator] do
      assert %{"error" => %{"code" => "command_group_self_approval_not_allowed"}} =
               c |> decide(person, id) |> json_response(403)
    end

    assert %{"data" => %{"state" => "approval_pending"}} =
             TestFixtures.member_conn(c.approver)
             |> get(console(c) <> "/command-groups/#{id}")
             |> json_response(200)

    assert %{"data" => %{"state" => "queued"}} =
             c |> decide(c.approver, id) |> json_response(200)
  end

  test "a service nobody is accountable for cannot have its group approved by anyone", c do
    assert %{"data" => %{"id" => id}} = created!(c)
    ServiceIdentityFixtures.forget_accountables!(c.service.service_identity_id)

    assert %{"error" => %{"code" => "command_group_approver_authors_unknown"}} =
             c |> decide(c.approver, id) |> json_response(403)
  end

  test "a service bearer cannot decide: it is refused before any group state is read", c do
    assert %{"data" => %{"id" => id}} = created!(c)

    for kind <- ["go", "no_go"] do
      conn =
        c
        |> as_service()
        |> post(console(c) <> "/command-groups/#{id}/decision", %{"kind" => kind})

      assert conn.status in [401, 403]
    end

    # Nor does REST have a decision route.
    assert c
           |> as_service()
           |> post(rest(c) <> "/command_groups/#{id}/decision", %{"kind" => "go"})
           |> response(404)

    assert %{"data" => %{"state" => "approval_pending"}} =
             c |> as_service() |> get(rest(c) <> "/command_groups/#{id}") |> json_response(200)
  end

  test "the request list is paged and bounded", c do
    for n <- 1..3 do
      created!(c, %{
        "commands" => [
          %{
            "command_id" => c.ids["SET_SIGNED"],
            "argument_values_json" => Jason.encode!(%{"counter" => n})
          }
        ]
      })
    end

    first =
      c
      |> as_service()
      |> get(rest(c) <> "/command_requests?limit=2")
      |> json_response(200)

    assert length(first["data"]) == 2
    assert cursor = first["meta"]["next_cursor"]

    second =
      c
      |> as_service()
      |> get(rest(c) <> "/command_requests?limit=2&cursor=#{cursor}")
      |> json_response(200)

    ids = Enum.map(first["data"] ++ second["data"], & &1["command_request_id"])
    assert length(ids) == 3 and length(Enum.uniq(ids)) == 3
    assert second["meta"]["next_cursor"] == nil

    for bad <- ["limit=0", "limit=501", "cursor=nope"] do
      assert c |> as_service() |> get(rest(c) <> "/command_requests?" <> bad) |> response(422)
    end
  end
end
