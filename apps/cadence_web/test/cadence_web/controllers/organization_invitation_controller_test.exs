defmodule CadenceWeb.OrganizationInvitationControllerTest do
  @moduledoc """
  The invitation page for an email that already has an account: it asks only for the current
  password, and the account is never overwritten (security fix).
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Changeset, only: [change: 2]

  alias Cadence.Accounts.{AttemptLimit, OrganizationInvitationRow, UserRow}
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    AttemptLimit.reset()
    on_exit(&AttemptLimit.reset/0)

    user = TestFixtures.persist_user!(display_name: "Kept Name")
    inviter = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!(display_name: "Cadence Operations")

    assert {:ok, %{mode: :invited, invitation: invitation, invitation_token: token}} =
             Cadence.Accounts.establish_organization_access(
               user.email,
               organization.organization_id,
               membership_role: :member,
               invited_by_user_id: inviter.user_id,
               force_invitation: true
             )

    %{
      user: user,
      path: "/invitations/#{token}",
      invitation_id: invitation.organization_invitation_id
    }
  end

  defp accept(conn, path, password),
    do: post(conn, path, %{"organization_invitation_acceptance" => %{"password" => password}})

  test "GET asks an existing account only for its current password", c do
    html = c.conn |> get(c.path) |> html_response(200)

    assert html =~ "Your current password"
    assert html =~ ~s(autocomplete="current-password")
    refute html =~ "organization_invitation_acceptance[password_confirmation]"
    refute html =~ "organization_invitation_acceptance[display_name]"
  end

  test "a wrong password is refused, changes nothing, and leaves the invitation pending", c do
    html = c.conn |> accept(c.path, "a-new-password-1") |> html_response(422)

    assert html =~ "That password isn&#39;t right."
    assert html =~ "Your current password"
    assert Repo.get!(OrganizationInvitationRow, c.invitation_id).status == "pending"
    assert {:ok, _} = Cadence.Auth.sign_in(c.user.email, TestFixtures.default_password())
  end

  test "a blank password asks for the current password", c do
    html = c.conn |> accept(c.path, "") |> html_response(422)
    assert html =~ "Enter your current password."
  end

  test "the current password joins and keeps the account as it was", c do
    {:ok, other_session} = Cadence.Auth.sign_in(c.user.email, TestFixtures.default_password())
    response = accept(c.conn, c.path, TestFixtures.default_password())

    assert redirected_to(response)
    assert is_binary(get_session(response, :user_session_token))
    assert Repo.get!(UserRow, c.user.user_id).display_name == "Kept Name"
    assert Repo.get!(OrganizationInvitationRow, c.invitation_id).status == "accepted"

    assert {:ok, _} =
             Cadence.Auth.authenticate_browser_session(other_session.session_token)
  end

  test "a disabled account says so only after the right password, and stays disabled", c do
    Repo.get!(UserRow, c.user.user_id) |> change(lifecycle_state: "disabled") |> Repo.update!()

    assert c.conn |> accept(c.path, "wrong-password-1") |> html_response(422) =~
             "That password isn&#39;t right."

    assert recycle(c.conn)
           |> accept(c.path, TestFixtures.default_password())
           |> html_response(403) =~
             "Your account is disabled."

    assert Repo.get!(UserRow, c.user.user_id).lifecycle_state == "disabled"
    assert Repo.get!(OrganizationInvitationRow, c.invitation_id).status == "pending"
  end

  test "too many wrong passwords answer 429 with the wait", c do
    for _ <- 1..6, do: accept(c.conn, c.path, "wrong-password-1")

    assert c.conn |> accept(c.path, TestFixtures.default_password()) |> html_response(429) =~
             "Too many wrong passwords. Try again in"
  end
end
