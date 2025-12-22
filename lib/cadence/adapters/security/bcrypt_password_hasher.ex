defmodule Cadence.Adapters.Security.BcryptPasswordHasher do
  @moduledoc """
  Bcrypt-based implementation of the PasswordHasher port.

  This adapter uses the Bcrypt library for secure password hashing,
  which is the default and recommended implementation for production.

  ## Usage

  This module is the default password hasher. It can also be
  explicitly configured:

      config :cadence, :password_hasher, Cadence.Adapters.Security.BcryptPasswordHasher

  Then accessed via:

      hasher = Cadence.Ports.Security.PasswordHasher.impl()
      hash = hasher.hash_password("secret123")
      true = hasher.verify_password("secret123", hash)

  ## Security

  - Uses Bcrypt's adaptive hashing with configurable work factor
  - Automatically generates random salt per password
  - Resistant to rainbow table attacks
  - Work factor increases computation time to resist brute force
  """

  @behaviour Cadence.Ports.Security.PasswordHasher

  @impl true
  def hash_password(password) when is_binary(password) do
    Bcrypt.hash_pwd_salt(password)
  end

  @impl true
  def verify_password(password, hash)
      when is_binary(password) and is_binary(hash) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hash)
  end

  def verify_password(_, _) do
    # Invalid input - still call no_user_verify to prevent timing attacks
    no_user_verify()
  end

  @impl true
  def no_user_verify do
    Bcrypt.no_user_verify()
    false
  end
end
