defmodule Cadence.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Cadence.Accounts` context.
  """

  import Ecto.Query
  import Cadence.OrganizationsFixtures

  alias Cadence.Accounts
  alias Cadence.Accounts.Scope

  def unique_user_email, do: "user-#{Ecto.UUID.generate()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    # Convert to map if keyword list
    attrs = if is_list(attrs), do: Enum.into(attrs, %{}), else: attrs

    # Create an organization if not provided
    organization = Map.get(attrs, :organization) || organization_fixture()

    attrs
    |> Map.delete(:organization)
    |> Map.put_new(:email, unique_user_email())
    |> Map.put(:organization_id, organization.id)
  end

  @doc """
  Creates an unconfirmed user (domain entity).

  Use `unconfirmed_user_schema_fixture/1` if you need an Ecto schema.
  """
  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  @doc """
  Creates an unconfirmed user and returns Ecto schema for backward compatibility.
  """
  def unconfirmed_user_schema_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)
    Cadence.Repo.get!(Cadence.Accounts.User, user.id)
  end

  @doc """
  Creates a confirmed user and returns Ecto schema for backward compatibility.
  """
  def user_fixture(attrs \\ %{}) do
    # Use domain entity for the confirmation flow
    user_entity = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user_entity, url)
      end)

    {:ok, {confirmed_user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    # Reload as Ecto schema for backward compatibility with tests
    # that expect Ecto associations and preloading
    Cadence.Repo.get!(Cadence.Accounts.User, confirmed_user.id)
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    # Accept either domain entity or Ecto schema
    user_id = if is_struct(user, Cadence.Accounts.User), do: user.id, else: user.id

    {:ok, {_updated_entity, _expired_tokens}} =
      Accounts.update_user_password(user_id, %{password: valid_user_password()})

    # Reload as Ecto schema for backward compatibility
    Cadence.Repo.get!(Cadence.Accounts.User, user_id)
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Cadence.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Cadence.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Cadence.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
