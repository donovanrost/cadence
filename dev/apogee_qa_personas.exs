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
# The password (#242): E2E_PERSONA_PASSWORD (at least 12 characters, never printed).
# E2E_RESET_PERSONA_PASSWORDS=1 also sets the
# EXISTING personas' passwords to it through Cadence.Accounts.FixturePasswords (all their
# sessions signed out); it refuses without E2E_PERSONA_PASSWORD.
#
# Requires the Reflect Orbital seed (dev/reflect_orbital_demo.exs). See docs/dev-environment.md.
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

  alias Cadence.Accounts.FixturePasswords
  alias Cadence.{Ids, Repo}

  @organization_id "org-reflect-orbital-demo"

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

    env = System.get_env()
    # Both read before anything is written: a bad value stops the run with nothing changed.
    {password, _source} = settle(FixturePasswords.persona_password(env))
    reset? = settle(FixturePasswords.reset?(env))

    Logger.configure(level: :warning)
    {:ok, _apps} = Application.ensure_all_started(:cadence)

    {:ok, _organization} = Cadence.Organizations.fetch_organization(@organization_id)

    Enum.each(@personas, fn persona ->
      user = ensure_user(persona, password, reset?)
      ensure_membership(user, persona.role)
      IO.puts("#{persona.email}  #{persona.role}")
    end)

    IO.puts("Password for all personas: from E2E_PERSONA_PASSWORD (not printed)")
  end

  defp settle({:ok, password, source}), do: {password, source}
  defp settle({:ok, value}), do: value
  defp settle({:error, reason}), do: raise("Apogee QA personas: #{reason}")

  defp ensure_user(%{email: email, display_name: display_name}, password, reset?) do
    case Cadence.Accounts.fetch_user_by_email(email) do
      {:ok, user} ->
        if reset?, do: :ok = reset!(user, password)
        user

      {:error, _not_found} ->
        insert_user(email, display_name, password)
    end
  end

  # Through the app's credential path (FixturePasswords), never a Repo write here.
  defp reset!(user, password) do
    case FixturePasswords.set(user.user_id, password, "apogee-qa") do
      :ok -> :ok
      {:error, reason} -> raise("Apogee QA personas: #{user.email} not reset: #{inspect(reason)}")
    end
  end

  defp insert_user(email, display_name, password) do
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

    password = Password.hash_password(password)

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
