defmodule Cadence.Application.Accounts.UserQueries do
  @moduledoc """
  Query service for user-related read operations.

  Provides operations for finding and listing users.

  ## Usage

      # Find a user by ID
      {:ok, user} = UserQueries.find(user_id)

      # Find by email
      {:ok, user} = UserQueries.find_by_email("user@example.com")

      # List users in an organization
      users = UserQueries.list_for_organization(org_id)
  """

  alias Cadence.Domain.Accounts.Entities.User

  @type user_id :: String.t()
  @type org_id :: String.t()
  @type email :: String.t()
  @type opts :: keyword()

  # Get configured repository
  defp repo do
    Cadence.Ports.Repository.Accounts.UserRepository.impl()
  end

  # ===========================================================================
  # Finding Users
  # ===========================================================================

  @doc """
  Finds a user by ID.

  Returns `{:ok, user}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(user_id()) :: {:ok, User.t()} | {:error, :not_found}
  def find(user_id), do: repo().find(user_id)

  @doc """
  Finds a user by ID, raising if not found.
  """
  @spec find!(user_id()) :: User.t()
  def find!(user_id) do
    case find(user_id) do
      {:ok, user} -> user
      {:error, :not_found} -> raise ArgumentError, "User not found: #{user_id}"
    end
  end

  @doc """
  Finds a user by email address.

  Email lookup is case-insensitive.
  """
  @spec find_by_email(email()) :: {:ok, User.t()} | {:error, :not_found}
  def find_by_email(email), do: repo().find_by_email(email)

  @doc """
  Finds a user by email within an organization.
  """
  @spec find_by_email_in_organization(org_id(), email()) ::
          {:ok, User.t()} | {:error, :not_found}
  def find_by_email_in_organization(org_id, email) do
    repo().find_by_email_in_organization(org_id, email)
  end

  # ===========================================================================
  # Listing Users
  # ===========================================================================

  @doc """
  Lists all users with optional filtering.

  ## Options

  - `:organization_id` - Filter by organization
  - `:role` - Filter by role (:owner, :admin, :member)
  - `:system_admin` - Filter by system admin status
  - `:confirmed` - Filter by confirmation status
  - `:search` - Search by email
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  """
  @spec list(opts()) :: [User.t()]
  def list(opts \\ []), do: repo().list(opts)

  @doc """
  Lists all users in an organization.
  """
  @spec list_for_organization(org_id(), opts()) :: [User.t()]
  def list_for_organization(org_id, opts \\ []) do
    repo().list_for_organization(org_id, opts)
  end

  @doc """
  Counts the number of users in an organization.
  """
  @spec count_for_organization(org_id()) :: non_neg_integer()
  def count_for_organization(org_id), do: repo().count_for_organization(org_id)

  # ===========================================================================
  # Validation Queries
  # ===========================================================================

  @doc """
  Checks if an email is already taken.

  Optionally excludes a specific user ID from the check.
  """
  @spec email_taken?(email(), user_id() | nil) :: boolean()
  def email_taken?(email, exclude_user_id \\ nil) do
    repo().email_taken?(email, exclude_user_id)
  end
end
