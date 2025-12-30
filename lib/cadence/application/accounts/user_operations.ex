defmodule Cadence.Application.Accounts.UserOperations do
  @moduledoc """
  Use case module for user write operations.

  Provides operations for registering, updating, and managing users.

  ## Usage

      # Register a new user
      {:ok, user} = UserOperations.register(%{
        email: "user@example.com",
        password: "secure_password_123",
        organization_id: org_id
      })

      # Update user email
      {:ok, user} = UserOperations.update_email(user_id, "new@example.com")

      # Change password
      {:ok, user} = UserOperations.update_password(user_id, current_password, new_password)
  """

  alias Cadence.Application.Accounts.UserQueries
  alias Cadence.Application.Organizations.MembershipOperations
  alias Cadence.Domain.Accounts.Entities.User
  alias Cadence.Ports.Repository.Accounts.UserRepository
  alias Cadence.Ports.Security.PasswordHasher

  @type user_id :: String.t()
  @type attrs :: map()

  # Get configured repository
  defp repo do
    UserRepository.impl()
  end

  # ===========================================================================
  # User Registration
  # ===========================================================================

  @doc """
  Registers a new user.

  ## Attributes

  Required:
  - `:email` - Valid email address
  - `:organization_id` - Organization ID (unless system_admin)

  Optional:
  - `:password` - Plain-text password (will be hashed)
  - `:role` - User role (defaults to :member)
  - `:system_admin` - Whether this is a system admin (defaults to false)

  ## Examples

      {:ok, user} = UserOperations.register(%{
        email: "user@example.com",
        password: "secure_password_123",
        organization_id: org_id
      })
  """
  @spec register(attrs()) :: {:ok, User.t()} | {:error, term()}
  def register(attrs) do
    with {:ok, hashed_password} <- maybe_hash_password(attrs[:password]),
         attrs <- Map.put(attrs, :hashed_password, hashed_password),
         {:ok, user} <- User.new(attrs),
         {:ok, saved} <- repo().save(user),
         :ok <- maybe_create_organization_membership(saved, attrs) do
      {:ok, saved}
    end
  end

  defp maybe_create_organization_membership(user, attrs) do
    org_id = attrs[:organization_id]

    if is_nil(org_id) do
      :ok
    else
      role = attrs[:role] || "member"

      membership_attrs = %{
        organization_id: org_id,
        user_id: user.id,
        role: role
      }

      case MembershipOperations.create(membership_attrs) do
        {:ok, _membership} -> :ok
        {:error, reason} -> {:error, {:membership_creation_failed, reason}}
      end
    end
  end

  @doc """
  Registers a new user without a password (for magic link auth).
  """
  @spec register_passwordless(attrs()) :: {:ok, User.t()} | {:error, term()}
  def register_passwordless(attrs) do
    attrs = Map.delete(attrs, :password)
    register(attrs)
  end

  # ===========================================================================
  # User Updates
  # ===========================================================================

  @doc """
  Updates a user's email address.

  The new email must be unique across all users.
  """
  @spec update_email(user_id(), String.t()) :: {:ok, User.t()} | {:error, term()}
  def update_email(user_id, new_email) do
    with {:ok, user} <- UserQueries.find(user_id),
         {:ok, updated} <- User.update_email(user, new_email) do
      repo().save(updated)
    end
  end

  @doc """
  Updates a user's password.

  Requires the current password for verification.
  """
  @spec update_password(user_id(), String.t(), String.t()) :: {:ok, User.t()} | {:error, term()}
  def update_password(user_id, current_password, new_password) do
    with {:ok, user} <- UserQueries.find(user_id),
         :ok <- verify_current_password(user, current_password),
         :ok <- User.validate_password(new_password),
         hashed <- PasswordHasher.hash(new_password),
         {:ok, updated} <- User.set_hashed_password(user, hashed) do
      repo().save(updated)
    end
  end

  @doc """
  Sets a password for a user (without requiring current password).

  Used for initial password setup or password reset.
  """
  @spec set_password(user_id(), String.t()) :: {:ok, User.t()} | {:error, term()}
  def set_password(user_id, new_password) do
    with {:ok, user} <- UserQueries.find(user_id),
         :ok <- User.validate_password(new_password),
         hashed <- PasswordHasher.hash(new_password),
         {:ok, updated} <- User.set_hashed_password(user, hashed) do
      repo().save(updated)
    end
  end

  @doc """
  Updates a user's role within their organization.
  """
  @spec update_role(user_id(), atom()) :: {:ok, User.t()} | {:error, term()}
  def update_role(user_id, new_role) do
    with {:ok, user} <- UserQueries.find(user_id),
         {:ok, updated} <- User.update_role(user, new_role) do
      repo().save(updated)
    end
  end

  # ===========================================================================
  # Email Confirmation
  # ===========================================================================

  @doc """
  Confirms a user's email address.
  """
  @spec confirm(user_id()) :: {:ok, User.t()} | {:error, term()}
  def confirm(user_id) do
    with {:ok, user} <- UserQueries.find(user_id),
         {:ok, confirmed} <- User.confirm(user) do
      repo().save(confirmed)
    end
  end

  # ===========================================================================
  # System Admin Management
  # ===========================================================================

  @doc """
  Promotes a user to system admin.
  """
  @spec make_system_admin(user_id()) :: {:ok, User.t()} | {:error, term()}
  def make_system_admin(user_id) do
    with {:ok, user} <- UserQueries.find(user_id),
         {:ok, updated} <- User.make_system_admin(user) do
      repo().save(updated)
    end
  end

  @doc """
  Removes system admin status from a user.
  """
  @spec revoke_system_admin(user_id()) :: {:ok, User.t()} | {:error, term()}
  def revoke_system_admin(user_id) do
    with {:ok, user} <- UserQueries.find(user_id),
         {:ok, updated} <- User.revoke_system_admin(user) do
      repo().save(updated)
    end
  end

  # ===========================================================================
  # System Admin Management
  # ===========================================================================

  @doc """
  Ensures a system admin user exists with the given email and password.

  If the user already exists:
  - Updates the password if provided
  - Ensures system_admin flag is true

  If the user doesn't exist:
  - Creates a new system admin user with confirmed email

  This function is idempotent and safe to call on every application start.
  """
  @spec ensure_system_admin(String.t(), String.t()) :: {:ok, User.t()} | {:error, term()}
  def ensure_system_admin(email, password) when is_binary(email) and is_binary(password) do
    case repo().find_by_email(email) do
      {:ok, user} ->
        update_existing_system_admin(user, password)

      {:error, :not_found} ->
        create_system_admin(email, password)
    end
  end

  defp create_system_admin(email, password) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, hashed_password} <- maybe_hash_password(password),
         {:ok, user} <-
           User.new(%{
             email: email,
             hashed_password: hashed_password,
             system_admin: true,
             confirmed_at: now
           }) do
      repo().save(user)
    end
  end

  defp update_existing_system_admin(user, password) do
    with {:ok, hashed_password} <- maybe_hash_password(password),
         {:ok, updated} <- User.set_hashed_password(user, hashed_password),
         {:ok, admin} <- User.make_system_admin(updated) do
      repo().save(admin)
    end
  end

  # ===========================================================================
  # Deletion
  # ===========================================================================

  @doc """
  Deletes a user.
  """
  @spec delete(user_id()) :: {:ok, User.t()} | {:error, term()}
  def delete(user_id), do: repo().delete(user_id)

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp maybe_hash_password(nil), do: {:ok, nil}

  defp maybe_hash_password(password) do
    case User.validate_password(password) do
      :ok -> {:ok, PasswordHasher.hash(password)}
      error -> error
    end
  end

  defp verify_current_password(%User{hashed_password: nil}, _password) do
    {:error, :no_password_set}
  end

  defp verify_current_password(%User{hashed_password: hash}, password) do
    if PasswordHasher.verify(password, hash) do
      :ok
    else
      {:error, :invalid_password}
    end
  end
end
