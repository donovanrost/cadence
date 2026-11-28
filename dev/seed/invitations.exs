defmodule EarendilInvitations do
  @moduledoc "Accepts dev invitations through the public API and the dev mailbox JSON."

  import EarendilRestClient,
    only: [guest: 1, request!: 3, request!: 4, request!: 5, select_organization: 2, sign_in: 4]

  def ensure_person(admin, organization_id, email, role, name) do
    password = System.fetch_env!("E2E_PERSONA_PASSWORD")
    path = "/organizations/#{organization_id}"
    {admin, directory} = request!(admin, :get, path <> "/people")
    member = Enum.find(directory["members"], &(&1["email"] == email))

    admin =
      if member do
        admin
      else
        pending =
          Enum.find(directory["invitations"], fn row ->
            row["email"] == email and row["status"] == "pending"
          end)

        if pending && pending["role"] != role,
          do: raise("#{email} has a pending invitation with the wrong role")

        admin =
          if pending do
            admin
          else
            {admin, _invitation} =
              request!(admin, :post, path <> "/invitations", %{email: email, role: role})

            admin
          end

        accept_from_mailbox(admin, email, name, password)
        admin
      end

    {person, _session} = sign_in(admin.base, email, password, admin?: false)
    {person, _session} = select_organization(person, organization_id)
    {admin, person}
  end

  defp accept_from_mailbox(admin, email, name, password) do
    {_, messages} = request!(admin, :get, "/dev/mailbox/json", nil, api?: false)

    token =
      Enum.find_value(messages, &mailbox_token(admin, &1, email)) ||
        raise("No open dev invitation for #{email} in /dev/mailbox/json")

    {guest, token, kind} = token

    {_, _accepted} =
      request!(guest, :post, "/auth/invitations/#{token}/accept", %{
        kind: kind,
        name: name,
        password: password
      })

    :ok
  end

  defp mailbox_token(admin, message, email) do
    with true <- Enum.any?(message["to"], &String.contains?(&1, email)),
         [_, candidate] <-
           Regex.run(~r{/console/invitations/([^\s/]+)}, message["text_body"] || ""),
         {guest, view} <-
           admin.base |> guest() |> request!(:get, "/auth/invitations/#{candidate}"),
         true <- view["email"] == email and view["case"] in ~w(new_account existing_account) do
      {guest, candidate, view["case"]}
    else
      _ -> nil
    end
  end
end
