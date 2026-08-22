defmodule CadenceWeb.MissionAuthTest do
  use Cadence.DataCase, async: true

  alias Cadence.Missions.Mission
  alias CadenceWeb.MissionAuth
  alias CadenceWeb.TestFixtures

  defp socket_with_scope_for(org) do
    user = TestFixtures.persist_user!()
    _ = TestFixtures.grant_membership!(user, org)

    {:ok, scope} =
      Cadence.Auth.authenticate_browser_session(TestFixtures.member_session_token!(user))

    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, current_scope: scope, flash: %{}}
    }
  end

  defp persist_mission!(org, slug) do
    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: slug,
        display_name: "Mission #{slug}"
      })

    assert {:ok, persisted} = Cadence.Missions.persist_mission(mission)
    persisted
  end

  describe "on_mount :load_mission" do
    test "assigns the mission when it belongs to the scope's organization" do
      org = TestFixtures.persist_org!()
      mission = persist_mission!(org, "alpha")
      socket = socket_with_scope_for(org)

      assert {:cont, socket} =
               MissionAuth.on_mount(
                 :load_mission,
                 %{"mission_id" => mission.mission_id},
                 %{},
                 socket
               )

      assert socket.assigns.current_mission.mission_id == mission.mission_id
      assert socket.assigns.nav_context == :mission
      assert socket.assigns.unread_notifications_count == 0
      assert socket.assigns.recent_notifications == []
    end

    test "halts and redirects to /missions when mission id does not exist" do
      org = TestFixtures.persist_org!()
      socket = socket_with_scope_for(org)

      assert {:halt, socket} =
               MissionAuth.on_mount(
                 :load_mission,
                 %{"mission_id" => "mission_missing"},
                 %{},
                 socket
               )

      assert socket.redirected == {:redirect, %{to: "/missions", status: 302}}
    end

    test "halts and redirects to /missions when mission belongs to another org" do
      mine = TestFixtures.persist_org!(slug: "mine")
      other = TestFixtures.persist_org!(slug: "other")
      mission = persist_mission!(other, "alpha")
      socket = socket_with_scope_for(mine)

      assert {:halt, socket} =
               MissionAuth.on_mount(
                 :load_mission,
                 %{"mission_id" => mission.mission_id},
                 %{},
                 socket
               )

      assert socket.redirected == {:redirect, %{to: "/missions", status: 302}}
    end
  end
end
