defmodule CadenceWeb.NoOrganizationControllerTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "renders for authenticated user with no membership and no invitations" do
    user = TestFixtures.persist_user!()
    conn = TestFixtures.member_conn(user)

    vue = no_organization_vue(conn)
    assert vue.props["page"]["pending_invitations_count"] == 0
    assert is_binary(vue.props["page"]["csrf_token"])
    assert vue.props["page"]["csrf_token"] != ""
  end

  test "renders pending-invitations block when the user has unread invitation notifications" do
    user = TestFixtures.persist_user!()

    {:ok, _n} =
      Notifications.persist_notification(
        Notification.new(%{
          user_id: user.user_id,
          kind: :organization_invitation,
          title: "Invitation to join Demo",
          metadata: %{"organization_invitation_id" => "orginv_x"}
        })
      )

    conn = TestFixtures.member_conn(user)

    pending = no_organization_vue(conn).props["page"]["pending_invitations_count"]

    assert pending == 1
  end

  test "uses plural copy for multiple invitations" do
    user = TestFixtures.persist_user!()

    Enum.each(1..2, fn _ ->
      {:ok, _} =
        Notifications.persist_notification(
          Notification.new(%{
            user_id: user.user_id,
            kind: :organization_invitation,
            title: "Invite",
            metadata: %{}
          })
        )
    end)

    conn = TestFixtures.member_conn(user)

    pending = no_organization_vue(conn).props["page"]["pending_invitations_count"]

    assert pending == 2
  end

  test "redirects to /sign-in when unauthenticated", %{conn: conn} do
    conn = get(conn, "/no-organization")
    assert redirected_to(conn) == "/sign-in"
  end

  defp no_organization_vue(conn) do
    {:ok, view, _html} = live(conn, "/no-organization")
    vue = Test.get_vue(view, id: "no-organization-page-component")

    assert vue.component == "NoOrganizationPage"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props |> Map.keys() |> Enum.sort() == ["page"]
    assert vue.handlers == %{}

    vue
  end
end
