defmodule CadenceWeb.OrganizationInvitationControllerTest do
  use CadenceWeb.ConnCase, async: true

  import Ecto.Changeset, only: [change: 2]
  import Phoenix.LiveViewTest

  alias Cadence.Accounts.OrganizationInvitationRow
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "GET keeps an available invitation in a connected non-SSR LiveVue page", %{conn: conn} do
    %{path: path} = invitation_fixture()

    {:ok, view, _html} = live(conn, path)
    vue = invitation_vue(view)
    presentation = vue.props["presentation"]

    assert presentation["root"]["attrs"]["id"] == "organization-invitation"
    assert presentation["error"] == nil

    assert presentation["form"]["attrs"]["id"] ==
             "organization-invitation-acceptance-form"

    assert presentation["form"]["attrs"]["action"] == path
    assert presentation["form"]["attrs"]["method"] == "post"

    assert Enum.map(presentation["form"]["fields"], & &1["input"]["attrs"]["name"]) == [
             "organization_invitation_acceptance[display_name]",
             "organization_invitation_acceptance[password]",
             "organization_invitation_acceptance[password_confirmation]"
           ]

    [csrf] = presentation["form"]["hidden_fields"]
    assert csrf["attrs"]["name"] == "_csrf_token"
    assert csrf["attrs"]["value"] != ""
  end

  test "GET preserves not-found status and unavailable presentation", %{conn: conn} do
    response = get(conn, "/invitations/not-a-valid-invitation-token")
    html = html_response(response, 404)
    presentation = invitation_vue(html).props["presentation"]

    assert presentation["error"]["attrs"]["id"] == "organization-invitation-error"
    assert presentation["error"]["text"] == "This invitation link is not valid."
    assert presentation["form"] == nil

    assert presentation["header"]["heading"]["text"] ==
             "This invitation is no longer available."
  end

  test "GET preserves gone status for expired and unavailable invitations", %{conn: conn} do
    expired = invitation_fixture()

    expired.row
    |> change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    expired_response = get(conn, expired.path)
    expired_presentation = expired_response |> html_response(410) |> invitation_vue()

    assert expired_presentation.props["presentation"]["error"]["text"] ==
             "This invitation link has expired."

    unavailable = invitation_fixture()

    unavailable.row
    |> change(status: "revoked")
    |> Repo.update!()

    unavailable_response = get(recycle(conn), unavailable.path)
    unavailable_presentation = unavailable_response |> html_response(410) |> invitation_vue()

    assert unavailable_presentation.props["presentation"]["error"]["text"] ==
             "This invitation can no longer be used."
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
    presentation = presentation["presentation"]

    assert presentation["error"]["text"] == "Password confirmation does not match."
    assert presentation["form"]["attrs"]["action"] == path

    [display_name, password, confirmation] = presentation["form"]["fields"]
    assert display_name["input"]["attrs"]["value"] == "Flight Operator"
    refute Map.has_key?(password["input"]["attrs"], "value")
    refute Map.has_key?(confirmation["input"]["attrs"], "value")
  end

  test "POST preserves malformed payload status and hides the unavailable form", %{conn: conn} do
    %{path: path} = invitation_fixture()

    response = post(conn, path, %{"organization_invitation_acceptance" => "invalid"})
    presentation = response |> html_response(422) |> invitation_vue() |> Map.fetch!(:props)
    presentation = presentation["presentation"]

    assert presentation["error"]["text"] == "Submit a valid invitation acceptance form."
    assert presentation["form"] == nil
  end

  defp invitation_fixture do
    inviter = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!(display_name: "Cadence Operations")

    assert {:ok, %{mode: :invited, invitation: invitation, invitation_token: invitation_token}} =
             Cadence.Accounts.establish_organization_access(
               "invitee-#{System.unique_integer([:positive])}@example.com",
               organization.organization_id,
               membership_role: :organization_admin,
               invited_by_user_id: inviter.user_id,
               display_name: "Invited Operator"
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
    assert vue.props |> Map.keys() |> Enum.sort() == ["presentation"]
    assert vue.handlers == %{}

    vue
  end
end
