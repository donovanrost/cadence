defmodule CadenceWeb.PlatformOrganizationDetailPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.{Accounts, Auth}
  alias CadenceWeb.TestFixtures

  setup do
    previous = Application.fetch_env(:swoosh, :shared_test_process)
    Application.put_env(:swoosh, :shared_test_process, self())

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:swoosh, :shared_test_process, value)
        :error -> Application.delete_env(:swoosh, :shared_test_process)
      end
    end)

    user = TestFixtures.persist_user!(capabilities: [:platform_admin])
    org = TestFixtures.persist_org!()
    other = TestFixtures.persist_org!()

    conn =
      user
      |> TestFixtures.member_conn()
      |> put_session(:admin_mode_expires_at, CadenceWeb.AdminMode.expires_at())

    %{
      user: user,
      org: org,
      other: other,
      conn: conn,
      path: "/admin/organizations/#{org.organization_id}"
    }
  end

  test "route identity wins over forged query identity and each page has core ownership", c do
    {:ok, view, _} =
      live(
        c.conn,
        c.path <> "?organization_id=#{c.other.organization_id}&org_id=#{c.other.organization_id}"
      )

    assert page(view)["page"] == "organization_detail"
    assert page(view)["organization_id"] == c.org.organization_id
    assert page(view)["data"]["organization"]["id"] == c.org.organization_id
    assert page(view)["status"] == "ready"

    render_hook(view, "host:context", %{
      "path" => c.path <> "/invite?org_id=#{c.other.organization_id}"
    })

    assert page(view)["page"] == "organization_invite"
    assert page(view)["data"]["organization"]["id"] == c.org.organization_id
    assert has_element?(view, "#application-shell")
    render_hook(view, "host:context", %{"path" => c.path <> "?members_after[]=bad"})
    assert page(view)["status"] == "unavailable"
    render_hook(view, "host:context", %{"path" => c.path})
    assert page(view)["status"] == "ready"
  end

  test "issuance consumes the visit and safe snapshots never repeat plaintext tokens", c do
    {:ok, view, _} = live(c.conn, c.path)
    token = page(view)["action_token"]
    input = %{"display_name" => "Flight API", "service_identity_id" => "web-service"}
    act(view, c.path, "issue_service_identity", input, "foreign")
    assert Auth.list_service_identities(c.org.organization_id) == []
    act(view, c.path, "issue_service_identity", input, token)
    [identity] = Auth.list_service_identities(c.org.organization_id)
    assert identity.service_identity_id == "web-service"

    assert page(view)["data"]["issued_identity"] == %{
             "id" => "web-service",
             "name" => "Flight API"
           }

    refute String.contains?(Jason.encode!(page(view)), "api_token")

    act(
      view,
      c.path,
      "issue_service_identity",
      %{input | "service_identity_id" => "second"},
      token
    )

    assert length(Auth.list_service_identities(c.org.organization_id)) == 1
    render_hook(view, "host:context", %{"path" => c.path})
    assert page(view)["data"]["issued_identity"]["id"] == "web-service"
    refute String.contains?(Jason.encode!(page(view)), "api_token")
    render_hook(view, "host:context", %{"path" => "/admin/organizations"})

    act(
      view,
      c.path,
      "issue_service_identity",
      %{input | "service_identity_id" => "departed"},
      token
    )

    render_hook(view, "host:context", %{"path" => c.path})
    refute page(view)["action_token"] == token
    assert page(view)["data"]["issued_identity"] == nil

    act(
      view,
      c.path,
      "issue_service_identity",
      %{input | "service_identity_id" => "stale"},
      token
    )

    assert length(Auth.list_service_identities(c.org.organization_id)) == 1
  end

  test "invitation receipt is consumed, preserves reviewed grant and excludes credentials", c do
    recipient = TestFixtures.persist_user!()
    path = c.path <> "/invite"
    {:ok, view, _} = live(c.conn, path)
    token = page(view)["action_token"]

    input = %{
      "email" => recipient.email,
      "display_name" => "Recipient",
      "membership_role" => "organization_admin",
      "grant_platform_admin" => true
    }

    act(
      view,
      path,
      "issue_service_identity",
      %{"display_name" => "Wrong page", "service_identity_id" => "wrong"},
      token
    )

    assert Auth.list_service_identities(c.org.organization_id) == []
    act(view, path, "invite", Map.put(input, "organization_id", c.other.organization_id), token)
    assert Accounts.list_pending_invitations(c.org.organization_id) == []
    act(view, path, "invite", input, token)
    [invitation] = Accounts.list_pending_invitations(c.org.organization_id)
    assert invitation.email == recipient.email
    assert invitation.grant_platform_admin
    assert invitation.membership_role == :organization_admin
    assert page(view)["data"]["submitted"]["id"] == invitation.organization_invitation_id
    assert page(view)["data"]["submitted"]["delivery"] == "submitted"

    for key <- ~w(api_token invitation_token token_digest token_hint),
        do: refute(String.contains?(Jason.encode!(page(view)), key))

    act(view, path, "invite", input, token)
    assert [preserved] = Accounts.list_pending_invitations(c.org.organization_id)
    assert preserved.organization_invitation_id == invitation.organization_invitation_id
    assert Accounts.list_user_memberships(recipient.user_id) == []
    assert Accounts.list_pending_invitations(c.other.organization_id) == []
  end

  test "revoked browser sessions cannot issue credentials or invitations", c do
    {:ok, detail, _} = live(c.conn, c.path)
    {:ok, invite, _} = live(c.conn, c.path <> "/invite")
    detail_token = page(detail)["action_token"]
    invite_token = page(invite)["action_token"]
    :ok = Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    act(
      detail,
      c.path,
      "issue_service_identity",
      %{"display_name" => "Denied", "service_identity_id" => "denied"},
      detail_token
    )

    assert_redirect(detail, "/sign-in")

    act(
      invite,
      c.path <> "/invite",
      "invite",
      %{
        "email" => "denied@example.test",
        "display_name" => "",
        "membership_role" => "member",
        "grant_platform_admin" => false
      },
      invite_token
    )

    assert_redirect(invite, "/sign-in")
    assert Auth.list_service_identities(c.org.organization_id) == []
    assert Accounts.list_pending_invitations(c.org.organization_id) == []
  end

  defp page(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"][
        "platform_administration_page"
      ]

  defp act(view, path, event, input, token) do
    render_hook(view, "host:platform-administration", %{
      "path" => path,
      "event" => event,
      "input" => input,
      "token" => token
    })
  end
end
