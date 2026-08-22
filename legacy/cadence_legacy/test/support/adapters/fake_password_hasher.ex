defmodule Cadence.Test.Adapters.FakePasswordHasher do
  @moduledoc """
  Fake password hasher for testing.

  Implements `Cadence.Ports.Security.PasswordHasher` behavior with fast,
  predictable operations suitable for testing.

  The "hash" is simply the password with a prefix, making it easy to
  verify expected behavior in tests without the cost of real hashing.

  ## Usage

      setup do
        Application.put_env(:cadence, :password_hasher, FakePasswordHasher)
        on_exit(fn ->
          Application.delete_env(:cadence, :password_hasher)
        end)
        :ok
      end

      test "hashes password" do
        hash = FakePasswordHasher.hash_password("secret123")
        assert FakePasswordHasher.verify_password("secret123", hash)
      end

  ## Security Warning

  This implementation provides NO security and should NEVER be used
  in production. It is purely for testing purposes.
  """

  @behaviour Cadence.Ports.Security.PasswordHasher

  @prefix "FAKE_HASH:"

  @impl true
  def hash_password(password) do
    @prefix <> password
  end

  @impl true
  def verify_password(password, hash) do
    hash == @prefix <> password
  end

  @impl true
  def no_user_verify do
    # Simulate the timing of a failed verification
    # In a fake implementation, we just return false immediately
    false
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns the hash prefix used by this fake hasher.

  Useful for tests that need to construct expected hash values.
  """
  def prefix, do: @prefix

  @doc """
  Checks if a hash was created by this fake hasher.
  """
  def fake_hash?(hash) when is_binary(hash) do
    String.starts_with?(hash, @prefix)
  end

  def fake_hash?(_), do: false

  @doc """
  Extracts the original password from a fake hash.

  Returns `{:ok, password}` if successful, `:error` otherwise.
  """
  def extract_password(hash) when is_binary(hash) do
    if fake_hash?(hash) do
      {:ok, String.replace_prefix(hash, @prefix, "")}
    else
      :error
    end
  end

  def extract_password(_), do: :error
end
