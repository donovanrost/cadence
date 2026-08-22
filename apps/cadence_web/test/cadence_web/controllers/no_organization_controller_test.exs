defmodule CadenceWeb.NoOrganizationControllerTest do
  use CadenceWeb.ConnCase, async: true

  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias CadenceWeb.TestFixtures

  test "renders for authenticated user with no membership and no invitations" do
    user = TestFixtures.persist_user!()
    conn = TestFixtures.member_conn(user)

    html =
      conn
      |> get("/no-organization")
      |> html_response(200)

    assert html =~ "don&#39;t have access"
    assert html =~ "Sign out"
    refute html =~ "pending invitation"
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

    html =
      conn
      |> get("/no-organization")
      |> html_response(200)

    assert html =~ ">1<"
    assert html =~ "pending invitation."
    assert html =~ ~s(href="/notifications")
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

    html =
      conn
      |> get("/no-organization")
      |> html_response(200)

    assert html =~ ">2<"
    assert html =~ "pending invitations."
  end

  test "redirects to /sign-in when unauthenticated", %{conn: conn} do
    conn = get(conn, "/no-organization")
    assert redirected_to(conn) == "/sign-in"
  end
end
