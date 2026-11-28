defmodule QaRestPersonas do
  @moduledoc "Stages QA people through invitations; accepting them waits on dev mailbox #745."

  import EarendilRestClient, only: [request!: 3, request!: 4]

  @people [
    {"qa-operator@example.com", "member"},
    {"qa-second@example.com", "member"},
    {"qa-org-admin@example.com", "organization_admin"},
    {"qa-org-admin-2@example.com", "organization_admin"}
  ]

  def seed(client, organization_id) do
    path = "/organizations/#{organization_id}"
    {client, directory} = request!(client, :get, path <> "/people")

    client =
      Enum.reduce(@people, client, fn {email, role}, client ->
        member = Enum.find(directory["members"], &(&1["email"] == email))

        pending =
          Enum.find(directory["invitations"], fn invitation ->
            invitation["email"] == email and invitation["status"] == "pending"
          end)

        cond do
          member ->
            client

          pending && pending["role"] == role ->
            client

          pending ->
            raise "QA persona #{email} has a pending invitation with the wrong role"

          true ->
            {client, _} =
              request!(client, :post, path <> "/invitations", %{email: email, role: role})

            client
        end
      end)

    IO.puts("  QA people present or invited; acceptance and sessions wait on #745")
    client
  end
end
