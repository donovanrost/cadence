defmodule CadenceWeb.OrganizationInvitationControllerTest do
  use CadenceWeb.ConnCase, async: true

  import Ecto.Changeset, only: [change: 2]
  import Phoenix.LiveViewTest

  alias Cadence.Accounts.OrganizationInvitationRow
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  # L5: the page's GET goes to the console's invitation screen; the legacy POST (below) stays for a
  # page that was already open.
  test "GET goes to the console's invitation screen with the token, whatever its state", %{
    conn: conn
  } do
    %{path: path} = invitation_fixture()
    token = String.replace_prefix(path, "/invitations/", "")
    assert redirected_to(get(conn, path)) == "/console/invitations/" <> token

    expired = invitation_fixture()

    expired.row
    |> change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    assert redirected_to(get(recycle(conn), expired.path)) =~ "/console/invitations/"

    assert redirected_to(get(recycle(conn), "/invitations/not-a-valid-token")) ==
             "/console/invitations/not-a-valid-token"
  end

  test "POST preserves validation status, copy, and non-password form values", %{conn: conn} do
    %{path: path} = invitation_fixture()

    response =
      post(conn, path, %{
        "organization_invitation_acceptance" => %{
          "display_name" => "Flight Operator",
          "password" => "durable-password-123",
          "password_confirmation" => "different-password-123"
        }
      })

    presentation = response |> html_response(422) |> invitation_vue() |> Map.fetch!(:props)
    presentation = presentation["page"]

    assert presentation["error"] == "Password confirmation does not match."
    assert presentation["token"] == String.replace_prefix(path, "/invitations/", "")
    assert presentation["display_name"] == "Flight Operator"
    refute Map.has_key?(presentation, "password")
    refute Map.has_key?(presentation, "password_confirmation")
  end

  test "POST preserves malformed payload status and hides the unavailable form", %{conn: conn} do
    %{path: path} = invitation_fixture()

    response = post(conn, path, %{"organization_invitation_acceptance" => "invalid"})
    presentation = response |> html_response(422) |> invitation_vue() |> Map.fetch!(:props)
    presentation = presentation["page"]

    assert presentation["error"] == "Submit a valid invitation acceptance form."
    assert presentation["available"] == false
  end

  describe "an invited email that already has an account (748fcbc9)" do
    setup do
      user = TestFixtures.persist_user!(display_name: "Kept Name")
      Map.put(invitation_fixture(user.email), :user, user)
    end

    test "a POST without the current password asks for it", c do
      response = post(c.conn, c.path, %{"organization_invitation_acceptance" => %{}})

      page =
        response |> html_response(422) |> invitation_vue() |> get_in([Access.key(:props), "page"])

      assert page["existing_account"] == true
      assert page["error"] == "Enter your current password."
    end

    test "POST with a wrong password is refused and changes nothing", c do
      response =
        post(c.conn, c.path, %{
          "organization_invitation_acceptance" => %{"password" => "a-new-password-1"}
        })

      page =
        response |> html_response(422) |> invitation_vue() |> get_in([Access.key(:props), "page"])

      assert page["error"] == "That password isn't right."
      assert page["existing_account"] == true
      assert {:ok, _} = Cadence.Auth.sign_in(c.user.email, TestFixtures.default_password())
    end

    test "POST with the current password joins and keeps the account as it was", c do
      response =
        post(c.conn, c.path, %{
          "organization_invitation_acceptance" => %{"password" => TestFixtures.default_password()}
        })

      assert redirected_to(response)
      assert is_binary(get_session(response, :user_session_token))
      assert Repo.get!(Cadence.Accounts.UserRow, c.user.user_id).display_name == "Kept Name"

      assert Repo.get!(OrganizationInvitationRow, c.row.organization_invitation_id).status ==
               "accepted"
    end

    test "POST for a disabled account says so only after the right password", c do
      Repo.get!(Cadence.Accounts.UserRow, c.user.user_id)
      |> change(lifecycle_state: "disabled")
      |> Repo.update!()

      wrong =
        post(c.conn, c.path, %{
          "organization_invitation_acceptance" => %{"password" => "wrong-password-1"}
        })

      assert wrong
             |> html_response(422)
             |> invitation_vue()
             |> get_in([Access.key(:props), "page", "error"]) == "That password isn't right."

      right =
        post(recycle(c.conn), c.path, %{
          "organization_invitation_acceptance" => %{"password" => TestFixtures.default_password()}
        })

      assert right
             |> html_response(403)
             |> invitation_vue()
             |> get_in([Access.key(:props), "page", "error"]) =~ "disabled"
    end
  end

  defp invitation_fixture(email \\ nil) do
    inviter = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!(display_name: "Cadence Operations")

    assert {:ok, %{mode: :invited, invitation: invitation, invitation_token: invitation_token}} =
             Cadence.Accounts.establish_organization_access(
               email || "invitee-#{System.unique_integer([:positive])}@example.com",
               organization.organization_id,
               membership_role: :organization_admin,
               invited_by_user_id: inviter.user_id,
               display_name: "Invited Operator",
               force_invitation: true
             )

    %{
      path: "/invitations/#{invitation_token}",
      row: Repo.get!(OrganizationInvitationRow, invitation.organization_invitation_id)
    }
  end

  defp invitation_vue(view_or_html) do
    vue = Test.get_vue(view_or_html, id: "organization-invitation-page-component")

    assert vue.component == "OrganizationInvitationPage"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props |> Map.keys() |> Enum.sort() == ["page"]
    assert vue.handlers == %{}

    vue
  end
end
