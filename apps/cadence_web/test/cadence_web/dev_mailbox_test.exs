defmodule CadenceWeb.DevMailboxTest do
  @moduledoc """
  #745: /dev/mailbox (Swoosh's mailbox preview, HTML and /json) is a dev-only convenience so a
  seed working through the public API can read an invitation link. It is not routed in this
  (test) build, and the invitation responses still carry no token.
  """
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  test "the mailbox is not routed outside dev" do
    refute Application.get_env(:cadence_web, :dev_routes, false)

    paths = Enum.map(Phoenix.Router.routes(CadenceWeb.Router), & &1.path)
    refute Enum.any?(paths, &String.starts_with?(&1, "/dev"))

    routed = Enum.map(Phoenix.Router.routes(CadenceWeb.Router), & &1.plug)
    refute Plug.Swoosh.MailboxPreview in routed
  end

  test "its URLs answer nothing in this build", %{conn: conn} do
    for path <- ["/dev/mailbox", "/dev/mailbox/json"] do
      conn = get(conn, path)
      refute conn.status == 200, "#{path} answered 200"
      refute conn.resp_body =~ "invitation"
    end
  end

  describe "invitation responses carry no token" do
    setup do
      org = TestFixtures.persist_org!()
      admin = TestFixtures.persist_user!(display_name: "Ada Admin")

      platform =
        TestFixtures.persist_user!(display_name: "Pat Platform", capabilities: [:platform_admin])

      TestFixtures.grant_membership!(admin, org, role: :organization_admin)
      %{org: org, admin: admin, platform: platform}
    end

    defp sent_token do
      assert_received {:email, email}

      [_, token] =
        Regex.run(~r{/invitations/([^\s"<?]+)}, email.text_body || email.html_body)

      token
    end

    test "organization invite", c do
      body =
        TestFixtures.member_conn(c.admin)
        |> post("/api/v1/organizations/#{c.org.organization_id}/invitations", %{
          "email" => "new@example.com",
          "role" => "member"
        })
        |> response(201)

      token = sent_token()
      refute body =~ token
      refute body =~ "token"
    end

    test "platform admin invite", c do
      body =
        c.platform
        |> TestFixtures.member_conn()
        |> Plug.Test.init_test_session(%{
          admin_mode_expires_at: System.system_time(:second) + 600
        })
        |> post("/api/v1/admin/organizations/#{c.org.organization_id}/invitations", %{
          "email" => "new2@example.com",
          "role" => "member"
        })
        |> response(201)

      token = sent_token()
      refute body =~ token
      refute body =~ "token"
    end
  end
end
