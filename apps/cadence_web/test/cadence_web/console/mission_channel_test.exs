defmodule CadenceWeb.Console.MissionChannelTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.ChannelTest, except: [connect: 2, connect: 3]
  require Phoenix.ChannelTest

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Platform.ScopedReadUpdates
  alias CadenceWeb.ConsoleSocket
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    token = TestFixtures.member_session_token!(user)

    %{org: org, mission: mission, token: token}
  end

  defp connect_console(session) do
    Phoenix.ChannelTest.connect(ConsoleSocket, %{}, connect_info: %{session: session})
  end

  describe "connect" do
    test "accepts a valid browser session", c do
      assert {:ok, socket} = connect_console(%{"user_session_token" => c.token})
      assert ConsoleSocket.id(socket) == ConsoleSocket.id_for_session_token(c.token)
    end

    test "refuses a missing session (as when the CSRF param is invalid)" do
      assert :error = connect_console(nil)
    end

    test "refuses an unknown session token" do
      assert :error = connect_console(%{"user_session_token" => "bogus"})
    end
  end

  describe "mission:<id>" do
    setup c do
      {:ok, socket} = connect_console(%{"user_session_token" => c.token})
      %{socket: socket}
    end

    test "joins a mission the user can operate", c do
      assert {:ok, reply, _socket} =
               subscribe_and_join(c.socket, "mission:" <> c.mission.mission_id, %{})

      assert reply.mission_id == c.mission.mission_id
      assert "commanding" in reply.resources
    end

    test "refuses another organization's mission", c do
      stranger_mission = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

      assert {:error, %{reason: "mission_not_found"}} =
               subscribe_and_join(c.socket, "mission:" <> stranger_mission.mission_id, %{})
    end

    test "coalesces change notifications into one invalidate push", c do
      {:ok, _reply, _socket} =
        subscribe_and_join(c.socket, "mission:" <> c.mission.mission_id, %{})

      org_id = c.org.organization_id
      mission_id = c.mission.mission_id

      :ok = ScopedReadUpdates.publish(:commanding_changed, org_id, mission_id)
      :ok = ScopedReadUpdates.publish(:commanding_changed, org_id, mission_id)

      _counts =
        RuntimeInvalidation.catalog_revision_changed(%{
          organization_id: org_id,
          mission_id: mission_id
        })

      assert_push("invalidate", %{resources: resources}, 2_000)
      assert "commanding" in resources
      assert "catalog" in resources
      refute_push("invalidate", _payload, 700)
    end

    test "ignores changes to other missions", c do
      {:ok, _reply, _socket} =
        subscribe_and_join(c.socket, "mission:" <> c.mission.mission_id, %{})

      other = TestFixtures.persist_mission!(c.org)

      :ok =
        ScopedReadUpdates.publish(:commanding_changed, c.org.organization_id, other.mission_id)

      refute_push("invalidate", _payload, 800)
    end
  end
end
