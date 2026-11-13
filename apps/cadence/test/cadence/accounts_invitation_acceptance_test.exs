defmodule Cadence.AccountsInvitationAcceptanceTest do
  @moduledoc """
  Accepting an invitation by its emailed token. An existing account proves itself with its own
  password (attempt-limited) and is never overwritten, signed out or reactivated.
  """
  use Cadence.DataCase, async: false

  @moduletag :capture_log

  alias Cadence.Accounts

  alias Cadence.Accounts.{
    AttemptLimit,
    Authentication,
    OrganizationInvitationRow,
    Password,
    Token,
    User,
    UserLocalCredentialRow,
    UserRow
  }

  alias Cadence.Ids
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization

  @existing_password "existing-password-123"
  @new_password "a-brand-new-password"

  setup do
    AttemptLimit.reset()
    on_exit(&AttemptLimit.reset/0)
    n = System.unique_integer([:positive])

    {:ok, org} =
      Organizations.persist_organization(
        Organization.new(%{
          organization_id: "org-accept-#{n}",
          slug: "accept-#{n}",
          display_name: "Accept #{n}"
        })
      )

    %{org: org, email: "invitee-#{n}@example.test"}
  end

  defp invite!(org, email) do
    inviter = account!("inviter-#{System.unique_integer([:positive])}@example.test")

    {:ok, %{mode: :invited, invitation_token: token}} =
      Accounts.establish_organization_access(email, org.organization_id,
        membership_role: :member,
        invited_by_user_id: inviter.user_id,
        force_invitation: true
      )

    token
  end

  defp account!(email, opts \\ []) do
    user =
      User.new(%{
        user_id: Ids.new("user"),
        email: email,
        display_name: "Original Name",
        capabilities: [],
        confirmed_at: Keyword.get(opts, :confirmed_at, DateTime.utc_now()),
        lifecycle_state: Keyword.get(opts, :lifecycle_state, :active),
        metadata: %{}
      })

    Repo.insert!(UserRow.changeset(user))
    hash = Password.hash_password(@existing_password)

    Repo.insert!(
      UserLocalCredentialRow.changeset(%{
        local_credential_id: Ids.new("cred"),
        user_id: user.user_id,
        provider_key: "password",
        password_hash: hash.password_hash,
        password_salt: hash.password_salt,
        password_iterations: hash.password_iterations,
        lifecycle_state: "active",
        metadata: %{}
      })
    )

    user
  end

  defp accept(token, attrs), do: Accounts.accept_organization_invitation(token, attrs)
  defp member?(org, user), do: match?({:ok, _}, membership(org, user))

  defp membership(org, user),
    do: Accounts.fetch_user_membership(user.user_id, org.organization_id)

  defp signed_in?(token), do: match?({:ok, _}, Accounts.authenticate_user_session(token))

  defp status(token) do
    Repo.get_by!(OrganizationInvitationRow, token_digest: Token.digest(token)).status
  end

  test "an existing account joins with its own password and nothing about it changes", c do
    user = account!(c.email)
    {:ok, other_session} = Authentication.issue_browser_session(user, nil)
    token = invite!(c.org, c.email)

    assert {:ok, accepted} =
             accept(token, %{display_name: "Hijacked", password: @existing_password})

    assert accepted.user.user_id == user.user_id
    assert member?(c.org, user)
    assert signed_in?(accepted.session_token)

    # Not overwritten, not signed out.
    assert Repo.get!(UserRow, user.user_id).display_name == "Original Name"
    assert {:ok, _} = Accounts.sign_in(c.email, @existing_password)
    assert signed_in?(other_session.session_token)
  end

  test "a wrong password for an existing account is refused and doesn't use the invitation", c do
    user = account!(c.email)
    token = invite!(c.org, c.email)

    assert {:error, :invalid_credentials} =
             accept(token, %{display_name: "Hijacked", password: @new_password})

    refute member?(c.org, user)
    assert status(token) == "pending"
    assert {:error, :invalid_credentials} = Accounts.sign_in(c.email, @new_password)
    assert {:ok, _} = Accounts.sign_in(c.email, @existing_password)
  end

  test "an existing account's password check is attempt-limited, the right password included",
       c do
    account!(c.email)
    token = invite!(c.org, c.email)

    for _ <- 1..6 do
      assert {:error, :invalid_credentials} =
               Accounts.accept_organization_invitation(token, %{password: "wrong"},
                 ip: "10.7.7.7"
               )
    end

    assert {:error, {:too_many_attempts, _}} =
             Accounts.accept_organization_invitation(token, %{password: @existing_password},
               ip: "10.7.7.7"
             )

    # The same budget as sign-in for that account.
    assert {:error, {:too_many_attempts, _}} =
             Accounts.sign_in(c.email, @existing_password, ip: "10.7.7.7")
  end

  test "a disabled account isn't reactivated; it says so only after the right password", c do
    user = account!(c.email, lifecycle_state: :disabled)
    token = invite!(c.org, c.email)

    assert {:error, :invalid_credentials} = accept(token, %{password: "wrong-password-1"})
    assert {:error, :account_disabled} = accept(token, %{password: @existing_password})

    assert Repo.get!(UserRow, user.user_id).lifecycle_state == "disabled"
    refute member?(c.org, user)
    assert status(token) == "pending"
  end

  test "an unconfirmed account is confirmed by the emailed token, nothing else changes", c do
    user = account!(c.email, confirmed_at: nil)
    token = invite!(c.org, c.email)

    assert {:ok, _} = accept(token, %{password: @existing_password})
    row = Repo.get!(UserRow, user.user_id)
    assert row.confirmed_at
    assert row.display_name == "Original Name"
  end

  test "with no account, it creates one with the given name and password", c do
    token = invite!(c.org, c.email)

    assert {:error, {:invalid_param, "password", :too_short}} =
             accept(token, %{display_name: "Ana", password: "short"})

    assert {:ok, accepted} = accept(token, %{display_name: "Ana", password: @new_password})
    assert accepted.user.display_name == "Ana"
    assert member?(c.org, accepted.user)
    assert {:ok, _} = Accounts.sign_in(c.email, @new_password)
    assert status(token) == "accepted"
  end
end
