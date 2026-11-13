defmodule CadenceWeb.Console.PeopleAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada Admin")
    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)

    %{admin: admin, member: member, base: "/api/console/v1/organizations/#{org.organization_id}"}
  end

  defp call(user, :get, path), do: user |> TestFixtures.member_conn() |> get(path)
  defp call(user, :post, path, body), do: user |> TestFixtures.member_conn() |> post(path, body)

  test "members see the directory with server-evaluated capabilities", c do
    data = c.member |> call(:get, c.base <> "/people") |> json_response(200) |> Map.fetch!("data")

    by_name = Map.new(data["members"], &{&1["display_name"], &1})
    assert by_name["Ada Admin"]["role"] == "organization_admin"
    assert "org.invite" in by_name["Ada Admin"]["capabilities"]
    # Commanding needs :manage_mission today (DECISIONS #38): members can't.
    assert by_name["Mira K."]["capabilities"] == []

    # No command.*: this organization has no missions to command in (DECISIONS #42, #62).
    assert Enum.sort(by_name["Ada Admin"]["capabilities"]) == ~w(org.invite org.manage_members)

    assert is_binary(by_name["Mira K."]["joined_at"])
    assert data["invitations"] == []
    assert data["permissions"] == []
  end

  test "the inviter sees a declined invitation with its status; pending still blocks a duplicate",
       c do
    invitee = TestFixtures.persist_user!(display_name: "Ivy")

    invite =
      c.admin
      |> call(:post, c.base <> "/invitations", %{"email" => invitee.email, "role" => "member"})
      |> json_response(201)
      |> Map.fetch!("data")

    assert {:ok, _} = Cadence.Accounts.decline_invitation_as_user(invitee.user_id, invite["id"])

    listed = c.admin |> call(:get, c.base <> "/people") |> json_response(200)
    assert [%{"status" => "declined", "decided_at" => decided}] = listed["data"]["invitations"]
    assert is_binary(decided)

    # A declined invitation doesn't block inviting them again.
    assert c.admin
           |> call(:post, c.base <> "/invitations", %{
             "email" => invitee.email,
             "role" => "member"
           })
           |> json_response(201)
  end

  test "an organization admin invites; duplicates are refused", c do
    admin_view = c.admin |> call(:get, c.base <> "/people") |> json_response(200)
    assert "org.invite" in admin_view["data"]["permissions"]

    invite =
      c.admin
      |> call(:post, c.base <> "/invitations", %{"email" => "Ana@Example.com", "role" => "member"})
      |> json_response(201)
      |> Map.fetch!("data")

    assert %{"email" => "ana@example.com", "role" => "member", "status" => "pending"} = invite
    assert invite["invited_by"] == %{"name" => "Ada Admin"}

    listed = c.admin |> call(:get, c.base <> "/people") |> json_response(200)

    assert [%{"email" => "ana@example.com", "invited_by" => %{"name" => "Ada Admin"}}] =
             listed["data"]["invitations"]

    conn = call(c.admin, :post, c.base <> "/invitations", %{"email" => "ana@example.com"})
    assert json_response(conn, 409)["error"]["code"] == "already_invited"

    conn = call(c.admin, :post, c.base <> "/invitations", %{"email" => c.member.email})
    assert json_response(conn, 409)["error"]["code"] == "already_member"

    conn = call(c.admin, :post, c.base <> "/invitations", %{"email" => "nope"})

    assert %{"code" => "invalid_params", "details" => %{"email" => _}} =
             json_response(conn, 422)["error"]
  end

  test "organization admins list service identities; members can't", c do
    data =
      c.admin
      |> call(:get, c.base <> "/service-identities")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data == %{"service_identities" => [], "rotation_policy_days" => nil}

    conn = call(c.member, :get, c.base <> "/service-identities")
    assert json_response(conn, 403)["error"]["code"] == "forbidden"
  end

  test "a plain member can't invite", c do
    conn = call(c.member, :post, c.base <> "/invitations", %{"email" => "x@example.com"})
    assert json_response(conn, 403)["error"]["code"] in ["forbidden", "scope_mismatch"]
  end

  test "another organization's people are not found", c do
    stranger = TestFixtures.persist_org!()

    conn =
      call(c.member, :get, "/api/console/v1/organizations/#{stranger.organization_id}/people")

    assert json_response(conn, 404)["error"]["code"] == "organization_not_found"
  end
end
