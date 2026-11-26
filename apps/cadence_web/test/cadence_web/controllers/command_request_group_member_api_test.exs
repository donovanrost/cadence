defmodule CadenceWeb.CommandRequestGroupMemberApiTest do
  @moduledoc """
  Four-eyes audit 11-17, P0, at the HTTP layer: the REST approve, reject and enqueue refuse a
  command-group member with 409 `command_request_in_group` and ux U87's words, and the REST
  create refuses a request that names a group in its metadata (422
  `command_request_group_reserved`). A group's members are decided only by its GO/NO-GO.
  """
  use CadenceWeb.ConnCase, async: false

  import Cadence.CommandGroupFixtures
  import CadenceWeb.ControlPlaneApiFixtures, only: [authorize: 2]

  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Commanding.CommandApproval
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.GroupSubmission

  @words "This command is part of a command group. Approve it with the group's GO/NO-GO."

  setup %{conn: conn} do
    c = setup!(2)

    draft =
      draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{log_entry: "Reset"})

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    assert group.state == :approval_pending
    [member | _rest] = GroupStore.members(c.org, c.mission, group.command_group_id)

    {:ok, %{api_token: token}} =
      Cadence.Auth.issue_service_identity(
        ServiceIdentity.new(%{
          service_identity_id: "svc-p0-#{System.unique_integer([:positive])}",
          organization_id: c.org,
          display_name: "P0 test service",
          capabilities: [:organization_admin]
        }),
        %Cadence.Auth.Scope{
          actor_kind: :user,
          organization_id: c.org,
          user: %Cadence.Accounts.User{user_id: "user-service-issuer"}
        }
      )

    Map.merge(c, %{
      conn: conn,
      token: token,
      group: group,
      member: member,
      base: "/api/organizations/#{c.org}/missions/#{c.mission}/command_requests"
    })
  end

  defp post_json(c, path, body), do: c.conn |> authorize(c.token) |> post(c.base <> path, body)

  test "approve and reject of a group member are 409 with U87's words", c do
    id = c.member.command_request_id

    for path <- ["/#{id}/approve", "/#{id}/reject"] do
      body = %{"approval" => %{"reason" => "one member alone"}}

      assert %{"errors" => [%{"reason" => "command_request_in_group", "message" => @words}]} =
               c |> post_json(path, body) |> json_response(409)
    end

    [member] = Enum.filter(members(c), &(&1.command_request_id == id))
    assert member.lifecycle_state == :approval_pending
  end

  test "enqueue of a group member is refused, approved or not", c do
    id = c.member.command_request_id

    # Waiting for the GO it has no approval, so the enqueue stops there first.
    assert %{"errors" => [%{"reason" => "command_not_approved"}]} =
             c |> post_json("/#{id}/enqueue", %{}) |> json_response(422)

    # Holding an approval in a state the standalone enqueue would queue, the group check refuses it.
    :ok = GroupStore.set_member_state(c.org, c.mission, [id], :approved)

    :ok =
      GroupStore.insert_approvals([
        CommandApproval.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          command_request_id: id,
          decision: :approved,
          decided_by: %{"actor_kind" => "user", "user_id" => "someone-else"},
          decided_at: DateTime.utc_now(),
          metadata: %{"command_group_id" => c.group.command_group_id},
          # #117 step 4b's required record fields.
          subject_digest: String.duplicate("a", 64),
          separated_from: [],
          admin_mode: false
        })
      ])

    assert %{"errors" => [%{"reason" => "command_request_in_group", "message" => @words}]} =
             c |> post_json("/#{id}/enqueue", %{}) |> json_response(409)
  end

  test "a forged marker in the approval's metadata changes nothing", c do
    body = %{"approval" => %{"metadata" => %{"command_group_id" => "command_group_other"}}}

    assert %{"errors" => [%{"reason" => "command_request_in_group"}]} =
             c
             |> post_json("/#{c.member.command_request_id}/approve", body)
             |> json_response(409)
  end

  test "create refuses a request that names a group in its metadata", c do
    before = members(c) |> Enum.map(& &1.command_request_id) |> Enum.sort()

    body = %{
      "command_request" => %{
        "command_request_id" => "command_request_injected",
        "source_endpoint_ref" => c.member.source_endpoint_ref,
        "mission_model_revision_id" => c.member.mission_model_revision_id,
        "command_id" => c.member.command_id,
        "argument_values" => %{"amount" => 2},
        "metadata" => %{
          "group" => %{"id" => c.group.command_group_id, "target_index" => 0, "position" => 9}
        }
      }
    }

    assert %{"errors" => [%{"reason" => "command_request_group_reserved"}]} =
             c |> post_json("", body) |> json_response(422)

    assert members(c) |> Enum.map(& &1.command_request_id) |> Enum.sort() == before
  end

  defp members(c), do: GroupStore.members(c.org, c.mission, c.group.command_group_id)
end
