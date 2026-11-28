defmodule CadenceWeb.Console.ChannelAccessTest do
  @moduledoc """
  #1153: a live channel stops streaming when the person's access ends. A membership removal closes
  the person's channels; a role change re-checks them; admin mode lapsing closes a platform
  admin's; a command group channel re-checks before each push. A join after the access has gone
  is refused.
  """
  use CadenceWeb.ConnCase, async: false

  import Phoenix.ChannelTest, except: [connect: 2, connect: 3, push: 3]
  require Phoenix.ChannelTest

  alias Cadence.Accounts.MembershipAdministration
  alias Cadence.Administration.OrganizationPeople
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.Groups.Validation
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.ExactCommandAuthoringFixtures
  alias CadenceWeb.ConsoleSocket
  alias CadenceWeb.TestFixtures

  @endpoint CadenceWeb.Endpoint

  setup do
    # A channel the check closes exits with `{:shutdown, :access_revoked}`; the test is linked to it.
    Process.flag(:trap_exit, true)
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    admin = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "SC-1")

    endpoint =
      CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
        spacecraft_id: craft.spacecraft_id
      })

    token = TestFixtures.member_session_token!(user)
    scope = scope(token, org)

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

    %{
      org: org,
      user: user,
      admin_scope: scope(TestFixtures.member_session_token!(admin), org),
      mission: mission,
      group: group,
      socket: connect_socket(%{"user_session_token" => token})
    }
  end

  defp scope(token, org) do
    {:ok, scope} =
      Cadence.Auth.authenticate_browser_session(token,
        current_organization_id: org.organization_id
      )

    scope
  end

  defp connect_socket(session) do
    {:ok, socket} =
      Phoenix.ChannelTest.connect(ConsoleSocket, %{}, connect_info: %{session: session})

    socket
  end

  defp mission_topic(c), do: "mission:#{c.mission.mission_id}"
  defp group_topic(c), do: "command_group:#{c.mission.mission_id}:#{c.group.command_group_id}"

  defp join!(socket, topic) do
    {:ok, _reply, joined} = subscribe_and_join(socket, topic, %{})
    ref = Process.monitor(joined.channel_pid)
    {joined, ref}
  end

  test "removing a member closes their channels, and a later join is refused", c do
    {_mission_channel, mission_ref} = join!(c.socket, mission_topic(c))
    {_group_channel, group_ref} = join!(c.socket, group_topic(c))

    assert {:ok, _} =
             OrganizationPeople.remove_member(
               c.admin_scope,
               c.org.organization_id,
               c.user.user_id
             )

    assert_receive {:DOWN, ^mission_ref, :process, _pid, {:shutdown, :access_revoked}}, 2_000
    assert_receive {:DOWN, ^group_ref, :process, _pid, {:shutdown, :access_revoked}}, 2_000

    # The same transport, a new join: refused.
    assert {:error, %{reason: "mission_not_found"}} =
             subscribe_and_join(c.socket, mission_topic(c), %{})
  end

  test "a role change re-checks the channels, and they stay while the person can still operate",
       c do
    {_channel, ref} = join!(c.socket, mission_topic(c))

    assert {:ok, _} =
             OrganizationPeople.change_role(
               c.admin_scope,
               c.org.organization_id,
               c.user.user_id,
               %{
                 "role" => "member"
               }
             )

    refute_receive {:DOWN, ^ref, :process, _pid, _reason}, 500
  end

  test "a command group channel re-checks before it pushes", c do
    {channel, ref} = join!(c.socket, group_topic(c))

    # The membership ends with no announcement (a path that doesn't send one): the next push finds out.
    assert {:ok, _} =
             MembershipAdministration.remove_member(
               c.org.organization_id,
               c.user.user_id,
               c.admin_scope.user.user_id
             )

    send(channel.channel_pid, :push)
    assert_receive {:DOWN, ^ref, :process, _pid, {:shutdown, :access_revoked}}, 2_000
  end

  describe "a platform admin in admin mode" do
    setup c do
      platform = TestFixtures.persist_user!(capabilities: [:platform_admin])
      token = TestFixtures.member_session_token!(platform)
      expires_at = System.system_time(:second) + 1

      session = %{
        "user_session_token" => token,
        "admin_mode_expires_at" => expires_at
      }

      Map.put(c, :platform_socket, connect_socket(session))
    end

    test "loses its channels when admin mode lapses, and can't join after", c do
      {_channel, ref} = join!(c.platform_socket, mission_topic(c))

      assert_receive {:DOWN, ^ref, :process, _pid, {:shutdown, :access_revoked}}, 5_000

      assert {:error, %{reason: "mission_not_found"}} =
               subscribe_and_join(c.platform_socket, mission_topic(c), %{})
    end
  end
end
