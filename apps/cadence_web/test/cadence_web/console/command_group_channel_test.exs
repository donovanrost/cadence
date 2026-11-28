defmodule CadenceWeb.Console.CommandGroupChannelTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.ChannelTest, except: [connect: 2, connect: 3, push: 3]
  require Phoenix.ChannelTest

  alias Cadence.{CommandAuthoringFixtures, ExactCommandAuthoringFixtures}
  alias Cadence.Commanding.Groups.Validation
  alias Cadence.Control.Commanding.{GroupAbort, GroupSubmission}
  alias CadenceWeb.ConsoleSocket
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "SC-1")

    endpoint =
      CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
        spacecraft_id: craft.spacecraft_id
      })

    token = TestFixtures.member_session_token!(user)

    {:ok, scope} =
      Cadence.Auth.authenticate_browser_session(token,
        current_organization_id: org.organization_id
      )

    draft = %{
      title: "t",
      targets: [
        %{spacecraft_id: craft.spacecraft_id, source_endpoint_id: endpoint.source_endpoint_id}
      ],
      commands: [
        %{command_id: model.commands_by_name["SET_SIGNED"], argument_values: %{"counter" => 1}}
      ],
      priority: 3
    }

    actor = %{"actor_kind" => "user", "user_id" => user.user_id}
    {:ok, validated} = Validation.validate(org.organization_id, mission.mission_id, actor, draft)

    {:ok, group} =
      GroupSubmission.submit(scope, mission.mission_id, draft, preflight_digest: validated.digest)

    {:ok, socket} =
      Phoenix.ChannelTest.connect(ConsoleSocket, %{},
        connect_info: %{session: %{"user_session_token" => token}}
      )

    %{socket: socket, scope: scope, mission: mission, group: group}
  end

  defp topic(c, id \\ nil),
    do: "command_group:#{c.mission.mission_id}:#{id || c.group.command_group_id}"

  test "pushes the group on join and again when it changes", c do
    {:ok, _reply, _socket} = subscribe_and_join(c.socket, topic(c), %{})
    assert_push("group", %{seq: 1, group: %{state: "queued"} = pushed}, 2_000)
    # #795: the push carries the page totals, never the targets or events themselves.
    refute Map.has_key?(pushed, :targets) or Map.has_key?(pushed, :events)
    assert %{total: _, revision: _, next_cursor: _} = pushed.targets_page
    assert %{total: _, next_cursor: _} = pushed.events_page

    {:ok, _} =
      GroupAbort.abort(c.scope, c.mission.mission_id, c.group.command_group_id, "Stand down")

    assert_push("group", %{seq: 2, group: %{state: "aborted"} = aborted}, 3_000)
    refute Map.has_key?(aborted, :targets) or Map.has_key?(aborted, :events)
  end

  test "an unknown group or another organization's mission is refused", c do
    assert {:error, %{reason: "command_group_not_found"}} =
             subscribe_and_join(c.socket, topic(c, "nope"), %{})

    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert {:error, %{reason: "mission_not_found"}} =
             subscribe_and_join(c.socket, "command_group:#{stranger.mission_id}:x", %{})
  end
end
