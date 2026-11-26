defmodule CadenceWeb.UserNotifierTest do
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  test "an invitation email links to the console's invitation screen" do
    inviter = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!(display_name: "Cadence Operations")

    assert {:ok, %{mode: :invited, invitation: invitation}} =
             Cadence.Accounts.establish_organization_access(
               "invitee-#{System.unique_integer([:positive])}@example.com",
               organization.organization_id,
               invited_by_user_id: inviter.user_id,
               force_invitation: true
             )

    token = "a token/with+reserved chars"

    assert {:ok, email} = CadenceWeb.UserNotifier.deliver(invitation, organization, token)

    assert email.text_body =~
             CadenceWeb.Endpoint.url() <> "/console/invitations/" <> URI.encode_www_form(token)
  end
end
