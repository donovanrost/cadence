defmodule CadenceWeb.Console.PeopleWritesAPITest do
  @moduledoc "People administration: role change, remove, invitation resend/revoke (backlog)."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Accounts
  alias Cadence.Accounts.Authentication
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada Admin")
    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)

    %{admin: admin, member: member, base: "/api/console/v1/organizations/#{org.organization_id}"}
  end

  defp conn(user), do: TestFixtures.member_conn(user)

  defp people(c),
    do: c.admin |> conn() |> get(c.base <> "/people") |> json_response(200) |> Map.fetch!("data")

  test "role changes keep at least one admin; members can't administer", c do
    admin_id = c.admin.user_id
    member_id = c.member.user_id

    assert %{"error" => %{"code" => "forbidden"}} =
             c.member
             |> conn()
             |> put(c.base <> "/people/#{admin_id}", %{"role" => "member"})
             |> json_response(403)

    assert %{"error" => %{"code" => "last_admin"}} =
             c.admin
             |> conn()
             |> put(c.base <> "/people/#{admin_id}", %{"role" => "member"})
             |> json_response(409)

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"role" => _}}} =
             c.admin
             |> conn()
             |> put(c.base <> "/people/#{member_id}", %{"role" => "owner"})
             |> json_response(422)

    assert %{
             "data" => %{
               "user_id" => ^member_id,
               "role" => "organization_admin",
               "state" => "active"
             }
           } =
             c.admin
             |> conn()
             |> put(c.base <> "/people/#{member_id}", %{"role" => "organization_admin"})
             |> json_response(200)

    # Now there's another admin, so the first can step down.
    assert %{"data" => %{"role" => "member"}} =
             c.admin
             |> conn()
             |> put(c.base <> "/people/#{admin_id}", %{"role" => "member"})
             |> json_response(200)

    assert %{"error" => %{"code" => "member_not_found"}} =
             c.member
             |> conn()
             |> put(c.base <> "/people/nobody", %{"role" => "member"})
             |> json_response(404)
  end

  test "removing a member revokes their access; the last admin can't be removed", c do
    assert %{"error" => %{"code" => "last_admin"}} =
             c.admin
             |> conn()
             |> delete(c.base <> "/people/#{c.admin.user_id}")
             |> json_response(409)

    assert %{"data" => %{"state" => "revoked"}} =
             c.admin
             |> conn()
             |> delete(c.base <> "/people/#{c.member.user_id}")
             |> json_response(200)

    refute Enum.any?(people(c)["members"], &(&1["user_id"] == c.member.user_id))

    # The removed person no longer sees the organization at all.
    assert %{"error" => %{"code" => "organization_not_found"}} =
             c.member |> conn() |> get(c.base <> "/people") |> json_response(404)
  end

  defp pending(c), do: Enum.filter(people(c)["invitations"], &(&1["status"] == "pending"))

  test "resend issues a fresh invitation; revoke ends it", c do
    %{"data" => %{"id" => first}} =
      c.admin
      |> conn()
      |> post(c.base <> "/invitations", %{"email" => "new@example.com", "role" => "member"})
      |> json_response(201)

    assert %{"data" => %{"id" => second, "email" => "new@example.com", "status" => "pending"}} =
             c.admin
             |> conn()
             |> post(c.base <> "/invitations/#{first}/resend", %{})
             |> json_response(201)

    refute second == first
    # The replaced one stays listed as revoked for 30 days (the inviter sees what happened).
    assert [%{"id" => ^second}] = pending(c)
    assert %{"status" => "revoked"} = Enum.find(people(c)["invitations"], &(&1["id"] == first))

    # The old link is gone.
    assert %{"error" => %{"code" => "invitation_not_found"}} =
             c.admin
             |> conn()
             |> post(c.base <> "/invitations/#{first}/resend", %{})
             |> json_response(404)

    assert c.admin |> conn() |> delete(c.base <> "/invitations/#{second}") |> response(204)
    assert pending(c) == []

    assert %{"error" => %{"code" => "invitation_not_found"}} =
             c.admin |> conn() |> delete(c.base <> "/invitations/#{second}") |> json_response(404)
  end

  test "the audit shows who invited, revoked, changed roles and removed (qa)", c do
    %{"data" => %{"id" => invitation}} =
      c.admin
      |> conn()
      |> post(c.base <> "/invitations", %{"email" => "late@example.com", "role" => "member"})
      |> json_response(201)

    assert c.admin |> conn() |> delete(c.base <> "/invitations/#{invitation}") |> response(204)

    assert c.admin
           |> conn()
           |> put(c.base <> "/people/#{c.member.user_id}", %{"role" => "organization_admin"})
           |> json_response(200)

    assert c.admin
           |> conn()
           |> delete(c.base <> "/people/#{c.member.user_id}")
           |> json_response(200)

    actions =
      c.admin
      |> conn()
      |> get(c.base <> "/audit?actor_id=#{c.admin.user_id}&kinds=access")
      |> json_response(200)
      |> get_in(["data", "events"])
      |> Enum.map(& &1["action"])

    assert "Invited late@example.com as member" in actions
    assert "Revoked the invitation for late@example.com" in actions
    assert "Changed Mira K.'s role from member to organization admin" in actions
    assert "Removed Mira K. from the organization" in actions
  end

  test "an accepted invitation is the new member's audited access event (qa)", c do
    email = "joiner-#{System.unique_integer([:positive])}@example.com"
    org_id = c.base |> String.split("/") |> List.last()

    {:ok, %{invitation_token: token}} =
      Accounts.establish_organization_access(email, org_id,
        membership_role: :member,
        invited_by_user_id: c.admin.user_id
      )

    assert {:ok, _accepted} =
             Accounts.accept_organization_invitation(token, %{
               "display_name" => "Jo Joiner",
               "password" => "a-long-enough-password"
             })

    {:ok, joiner} = Authentication.durable_user_by_email(email)

    assert [%{"action" => "Accepted the invitation and joined as member", "actor" => actor}] =
             c.admin
             |> conn()
             |> get(c.base <> "/audit?actor_id=#{joiner.user_id}&kinds=access")
             |> json_response(200)
             |> get_in(["data", "events"])

    assert %{"kind" => "user", "name" => "Jo Joiner"} = actor
  end
end
