defmodule CadenceWeb.CommandQueueEntryReleaseApiTest do
  @moduledoc """
  The REST release of a queue entry (#708): every request is a command group's member, so an entry
  is released only once its group has its GO. A request is made only through a group, and a group
  is decided in the console, so the entry here is a member of a group still awaiting its GO.
  """
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.ControlPlaneApiFixtures

  alias Cadence.Commanding.CommandRequest
  alias Cadence.CommandMemberFixtures

  setup %{conn: conn} do
    %{conn: conn, api_token: token, organization_id: org, mission_id: mission} = bootstrap(conn)
    %{conn: conn, token: token, org: org, mission: mission}
  end

  test "an entry whose group hasn't been given its GO is refused with 409 command_group_not_armed",
       c do
    group = CommandMemberFixtures.group!(c.org, c.mission, :approval_pending)

    %{queue_entry: entry} =
      c.org
      |> CommandMemberFixtures.insert!(
        CommandRequest.new(%{
          mission_id: c.mission,
          source_endpoint_ref: "endpoint-release",
          mission_model_revision_id: "model-release",
          command_id: "command-release",
          command_name: "NOOP",
          lifecycle_state: :queued,
          requested_by: %{"user_id" => "requester"},
          requested_at: DateTime.utc_now()
        }),
        group: group
      )
      |> CommandMemberFixtures.queue(kick: false)

    conn =
      c.conn
      |> authorize(c.token)
      |> post(
        "/api/organizations/#{c.org}/missions/#{c.mission}/command_queue_entries/#{entry.command_queue_entry_id}/release",
        %{"release_attempt" => %{"realized_contact_id" => "any-contact"}}
      )

    assert %{"errors" => [%{"reason" => "command_group_not_armed"}]} = json_response(conn, 409)
  end
end
