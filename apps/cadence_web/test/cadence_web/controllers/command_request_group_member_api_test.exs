defmodule CadenceWeb.CommandRequestGroupMemberApiTest do
  @moduledoc """
  Four-eyes audit 11-17, P0, at the HTTP layer: the REST approve, reject and enqueue refuse a
  command-group member with 409 `command_request_in_group`, each in the words for the act tried
  (ux U87, amended, #121), and the REST create refuses a request that names a group in its
  metadata (422 `command_request_group_reserved`). A group's members are decided only by its
  GO/NO-GO.
  """
  use CadenceWeb.ConnCase, async: false

  import Cadence.CommandGroupFixtures
  import CadenceWeb.ControlPlaneApiFixtures, only: [authorize: 2]

  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Commanding.CommandApproval
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.GroupSubmission

  @approve_words "This command is part of a command group. Approve it with the group's GO/NO-GO."
  @reject_words "This command is part of a command group. Reject it with the group's NO-GO."
  @enqueue_words "This command is part of a command group. Its group's GO queues it."
  @create_words "Not created: this request names a command group. " <>
                  "A group's commands are submitted with the group."

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
        })
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

  test "approve of a group member is 409 in the approve words", c do
    assert_in_group(c, "approve", @approve_words)
  end

  test "reject of a group member is 409 in the reject words (#121)", c do
    assert_in_group(c, "reject", @reject_words)
  end

  test "enqueue of a group member is refused, approved or not, in the enqueue words (#121)", c do
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
          metadata: %{"command_group_id" => c.group.command_group_id}
        })
      ])

    assert %{"errors" => [%{"reason" => "command_request_in_group", "message" => @enqueue_words}]} =
             c |> post_json("/#{id}/enqueue", %{}) |> json_response(409)
  end

  test "a forged marker in the approval's metadata changes nothing", c do
    body = %{"approval" => %{"metadata" => %{"command_group_id" => "command_group_other"}}}

    assert %{"errors" => [%{"reason" => "command_request_in_group"}]} =
             c
             |> post_json("/#{c.member.command_request_id}/approve", body)
             |> json_response(409)
  end

  test "create refuses a request that names a group in its metadata, in U87's words", c do
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

    assert %{
             "errors" => [
               %{"reason" => "command_request_group_reserved", "message" => @create_words}
             ]
           } =
             c |> post_json("", body) |> json_response(422)

    assert members(c) |> Enum.map(& &1.command_request_id) |> Enum.sort() == before
  end

  defp assert_in_group(c, act, words) do
    id = c.member.command_request_id
    body = %{"approval" => %{"reason" => "one member alone"}}

    assert %{"errors" => [%{"reason" => "command_request_in_group", "message" => ^words}]} =
             c |> post_json("/#{id}/#{act}", body) |> json_response(409)

    [member] = Enum.filter(members(c), &(&1.command_request_id == id))
    assert member.lifecycle_state == :approval_pending
  end

  defp members(c), do: GroupStore.members(c.org, c.mission, c.group.command_group_id)
end
