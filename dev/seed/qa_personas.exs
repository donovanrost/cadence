defmodule QaRestPersonas do
  @moduledoc "Creates QA people through invitations and accepts them from the dev mailbox."

  @people [
    {"qa-operator@example.com", "member", "QA Operator"},
    {"qa-second@example.com", "member", "QA Second Operator"},
    {"qa-org-admin@example.com", "organization_admin", "QA Org Admin"},
    {"qa-org-admin-2@example.com", "organization_admin", "QA Org Admin 2"}
  ]

  def seed(client, organization_id) do
    client =
      Enum.reduce(@people, client, fn {email, role, name}, admin ->
        {admin, _person} =
          EarendilInvitations.ensure_person(admin, organization_id, email, role, name)

        admin
      end)

    IO.puts("  four QA people joined through dev invitations")
    client
  end
end
