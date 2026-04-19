defmodule CadenceWeb.TestFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Accounts.{OrganizationMembership, Password, User}
  alias Cadence.Ids
  alias Cadence.Organizations.Organization

  alias Cadence.Persistence.Schemas.{
    OrganizationMembershipRow,
    UserLocalCredentialRow,
    UserRow
  }

  alias Cadence.Repo

  @default_password "durable-password-123"

  def default_password, do: @default_password

  @spec persist_user!(keyword()) :: User.t()
  def persist_user!(opts \\ []) do
    email = Keyword.get(opts, :email, "user-#{System.unique_integer([:positive])}@example.com")
    password = Keyword.get(opts, :password, @default_password)
    display_name = Keyword.get(opts, :display_name, "Durable User")
    capabilities = Keyword.get(opts, :capabilities, [])

    user =
      User.new(%{
        user_id: Keyword.get(opts, :user_id, Ids.new("user")),
        email: email,
        display_name: display_name,
        capabilities: capabilities,
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    user
  end

  @spec persist_org!(keyword()) :: Organization.t()
  def persist_org!(opts \\ []) do
    slug = Keyword.get(opts, :slug, "org-#{System.unique_integer([:positive])}")
    display_name = Keyword.get(opts, :display_name, "Cadence Org")

    org = Organization.new(%{display_name: display_name, slug: slug})
    assert {:ok, persisted} = Cadence.persist_organization(org)
    persisted
  end

  @spec grant_membership!(User.t(), Organization.t(), keyword()) :: OrganizationMembership.t()
  def grant_membership!(%User{} = user, %Organization{} = org, opts \\ []) do
    role = Keyword.get(opts, :role, :member)

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: org.organization_id,
        role: role,
        lifecycle_state: :active
      })

    assert {:ok, _row} = Repo.insert(OrganizationMembershipRow.changeset(membership))
    membership
  end

  @spec member_session_token!(User.t()) :: binary()
  def member_session_token!(%User{email: email}) do
    assert {:ok, session} = Cadence.sign_in(email, @default_password)
    session.session_token
  end

  @spec member_conn(User.t()) :: Plug.Conn.t()
  def member_conn(%User{} = user) do
    token = member_session_token!(user)
    Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{user_session_token: token})
  end
end
