# Apogee console QA personas (development only).
#
# Creates three password users in the Reflect Orbital demo organization so console e2e
# tests can exercise capability-gated UI and the two-person rule without the environment
# administrator (whose admin mode would hide gating bugs). Rerunnable: existing users and
# memberships are left as they are.
#
#   cd apps/cadence_web
#   mix run --no-start ../../dev/apogee_qa_personas.exs
#
# Requires the Reflect Orbital seed (dev/reflect_orbital_demo.exs). See docs/apogee/qa/runbook.md.
defmodule Cadence.Dev.ApogeeQaPersonas do
  @moduledoc false

  alias Cadence.Accounts.{
    OrganizationMembership,
    OrganizationMembershipRow,
    Password,
    User,
    UserLocalCredentialRow,
    UserRow
  }

  alias Cadence.{Ids, Repo}

  @organization_id "org-reflect-orbital-demo"
  @password "apogee-qa-password"

  @personas [
    %{email: "qa-operator@example.com", display_name: "QA Operator", role: :member},
    %{email: "qa-second@example.com", display_name: "QA Second Operator", role: :member},
    %{email: "qa-org-admin@example.com", display_name: "QA Org Admin", role: :organization_admin},
    # A second organization admin: approvals that need "another admin" (policy versions,
    # two-person commanding, #38) can't be given by the author.
    %{
      email: "qa-org-admin-2@example.com",
      display_name: "QA Org Admin 2",
      role: :organization_admin
    }
  ]

  def run do
    unless Code.ensure_loaded?(Mix) and Mix.env() == :dev,
      do: raise("Apogee QA personas are for the development database only")

    Logger.configure(level: :warning)
    {:ok, _apps} = Application.ensure_all_started(:cadence)

    {:ok, _organization} = Cadence.Organizations.fetch_organization(@organization_id)

    Enum.each(@personas, fn persona ->
      user = ensure_user(persona)
      ensure_membership(user, persona.role)
      IO.puts("#{persona.email}  #{persona.role}")
    end)

    IO.puts("Password for all personas: #{@password}")
  end

  defp ensure_user(%{email: email, display_name: display_name}) do
    case Cadence.Accounts.fetch_user_by_email(email) do
      {:ok, user} -> user
      {:error, _not_found} -> insert_user(email, display_name)
    end
  end

  defp insert_user(email, display_name) do
    user =
      User.new(%{
        user_id: Ids.new("user"),
        email: email,
        display_name: display_name,
        capabilities: [],
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{"fixture" => "apogee-qa"}
      })

    password = Password.hash_password(@password)

    {:ok, _rows} =
      Repo.transaction(fn ->
        {:ok, _user_row} = Repo.insert(UserRow.changeset(user))

        {:ok, _credential_row} =
          Repo.insert(
            UserLocalCredentialRow.changeset(%{
              local_credential_id: Ids.new("cred"),
              user_id: user.user_id,
              provider_key: "password",
              password_hash: password.password_hash,
              password_salt: password.password_salt,
              password_iterations: password.password_iterations,
              lifecycle_state: "active",
              metadata: %{"fixture" => "apogee-qa"}
            })
          )
      end)

    user
  end

  defp ensure_membership(user, role) do
    case Cadence.Accounts.fetch_user_membership(user.user_id, @organization_id) do
      {:ok, membership} ->
        membership

      {:error, :not_found} ->
        membership =
          OrganizationMembership.new(%{
            user_id: user.user_id,
            organization_id: @organization_id,
            role: role,
            lifecycle_state: :active,
            metadata: %{"fixture" => "apogee-qa"}
          })

        {:ok, _row} = membership |> OrganizationMembershipRow.changeset() |> Repo.insert()
        membership
    end
  end
end

Cadence.Dev.ApogeeQaPersonas.run()
