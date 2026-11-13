defmodule CadenceWeb.Console.ContactChangesTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.ChannelTest, except: [connect: 2, connect: 3]
  require Phoenix.ChannelTest

  alias Cadence.ContactPlanning.PlanUpdates
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Platform.ScopedReadUpdates
  alias CadenceWeb.Console.ContactChanges
  alias CadenceWeb.ConsoleSocket
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    token = TestFixtures.member_session_token!(user)

    {:ok, socket} =
      Phoenix.ChannelTest.connect(ConsoleSocket, %{},
        connect_info: %{session: %{"user_session_token" => token}}
      )

    {:ok, reply, _socket} = subscribe_and_join(socket, "mission:" <> mission.mission_id, %{})
    %{org: org, mission: mission, reply: reply}
  end

  test "contacts is an advertised resource", c do
    assert "contacts" in c.reply.resources
  end

  test "a contact fact for the mission invalidates contacts; other missions don't", c do
    :ok = ContactChanges.observe(%ScheduledContact{mission_id: "someone-else"})
    refute_push("invalidate", _payload, 700)

    :ok = ContactChanges.observe(%ScheduledContact{mission_id: c.mission.mission_id})
    assert_push("invalidate", %{resources: ["contacts"]}, 2_000)
  end

  # A settled booking can close a pass_release attention item with no attention event of its own.
  test "a contacts_changed read update invalidates contacts and attention", c do
    :ok =
      ScopedReadUpdates.publish(:contacts_changed, c.org.organization_id, c.mission.mission_id)

    assert_push("invalidate", %{resources: ["attention", "contacts"]}, 2_000)
  end

  test "contact plan and run changes invalidate contact_plans (S10)", c do
    assert "contact_plans" in c.reply.resources

    :ok = PlanUpdates.changed(c.org.organization_id, c.mission.mission_id)
    assert_push("invalidate", %{resources: ["contact_plans"]}, 2_000)
  end

  test "facts without a mission are ignored" do
    assert :ok = ContactChanges.observe(:unrelated)
  end
end
