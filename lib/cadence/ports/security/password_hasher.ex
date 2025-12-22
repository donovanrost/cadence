defmodule Cadence.Ports.Security.PasswordHasher do
  @moduledoc """
  Port (behavior) defining the contract for password hashing operations.

  This abstraction enables:
  - Unit testing with fast, predictable hashing
  - Swapping hashing algorithms without changing domain logic
  - Proper separation of security concerns

  ## Implementations

  - `Cadence.Adapters.Security.BcryptPasswordHasher` - Production Bcrypt implementation
  - `Cadence.Test.Adapters.FakePasswordHasher` - Fast fake for tests

  ## Security Notes

  - Production implementations should use strong, slow hashing (bcrypt, argon2)
  - The `no_user_verify/0` callback prevents timing attacks during login
  """

  @type password :: String.t()
  @type hash :: String.t()

  @doc """
  Hashes a plain-text password.

  Returns the hashed password suitable for storage.
  """
  @callback hash_password(password()) :: hash()

  @doc """
  Verifies a plain-text password against a stored hash.

  Returns `true` if the password matches, `false` otherwise.
  """
  @callback verify_password(password(), hash()) :: boolean()

  @doc """
  Performs a dummy verification to prevent timing attacks.

  Call this when a user is not found to ensure login attempts
  for non-existent users take the same time as existing users.
  """
  @callback no_user_verify() :: boolean()

  # ============================================================================
  # Implementation Helper
  # ============================================================================

  @doc """
  Returns the configured password hasher implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :password_hasher,
      Cadence.Adapters.Security.BcryptPasswordHasher
    )
  end

  # ============================================================================
  # Convenience Functions
  # ============================================================================

  @doc """
  Hashes a password using the configured implementation.
  """
  @spec hash(password()) :: hash()
  def hash(password), do: impl().hash_password(password)

  @doc """
  Verifies a password using the configured implementation.
  """
  @spec verify(password(), hash()) :: boolean()
  def verify(password, hash), do: impl().verify_password(password, hash)

  @doc """
  Performs dummy verification using the configured implementation.
  """
  @spec dummy_verify() :: boolean()
  def dummy_verify, do: impl().no_user_verify()
end
