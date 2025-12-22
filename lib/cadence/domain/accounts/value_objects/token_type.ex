defmodule Cadence.Domain.Accounts.ValueObjects.TokenType do
  @moduledoc """
  Value object representing the type/context of a user token.

  Token types determine the purpose and validity rules for tokens:
  - `:session` - Browser session tokens (long-lived)
  - `:login` - Magic link login tokens (short-lived)
  - `:reset_password` - Password reset tokens
  - `:change_email` - Email change confirmation tokens

  ## Usage

      iex> TokenType.valid?(:session)
      true

      iex> TokenType.validity_days(:session)
      60

      iex> TokenType.validity_days(:login)
      1
  """

  @type t :: :session | :login | :reset_password | :change_email

  @types [:session, :login, :reset_password, :change_email]

  # Token validity in days
  @validity %{
    session: 60,
    login: 1,
    reset_password: 1,
    change_email: 7
  }

  @doc """
  Returns all valid token types.
  """
  @spec all() :: [t()]
  def all, do: @types

  @doc """
  Checks if the given value is a valid token type.
  """
  @spec valid?(term()) :: boolean()
  def valid?(type) when type in @types, do: true
  def valid?(_), do: false

  @doc """
  Validates and returns the token type.
  """
  @spec validate(term()) :: {:ok, t()} | {:error, :invalid_token_type}
  def validate(type) when type in @types, do: {:ok, type}
  def validate(type) when is_binary(type) do
    case parse(type) do
      {:ok, parsed} -> {:ok, parsed}
      :error -> {:error, :invalid_token_type}
    end
  end
  def validate(_), do: {:error, :invalid_token_type}

  @doc """
  Parses a string into a token type atom.

  Handles legacy "change:email" format by extracting the type.
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse("session"), do: {:ok, :session}
  def parse("login"), do: {:ok, :login}
  def parse("reset_password"), do: {:ok, :reset_password}
  def parse("change_email"), do: {:ok, :change_email}
  # Handle legacy format "change:email@example.com"
  def parse("change:" <> _), do: {:ok, :change_email}
  def parse(_), do: :error

  @doc """
  Converts a token type to its string context representation.

  For change_email, an email address can be appended.
  """
  @spec to_context(t(), keyword()) :: String.t()
  def to_context(:session, _opts), do: "session"
  def to_context(:login, _opts), do: "login"
  def to_context(:reset_password, _opts), do: "reset_password"
  def to_context(:change_email, opts) do
    case Keyword.get(opts, :email) do
      nil -> "change_email"
      email -> "change:#{email}"
    end
  end

  @doc """
  Returns the validity period in days for a token type.
  """
  @spec validity_days(t()) :: pos_integer()
  def validity_days(type) when type in @types do
    Map.fetch!(@validity, type)
  end

  @doc """
  Returns the validity period as a duration for use with DateTime.
  """
  @spec validity_duration(t()) :: {integer(), :day}
  def validity_duration(type) do
    {validity_days(type), :day}
  end

  @doc """
  Checks if a token of this type should be hashed before storage.

  Session and login tokens are hashed for security.
  """
  @spec requires_hashing?(t()) :: boolean()
  def requires_hashing?(:session), do: true
  def requires_hashing?(:login), do: true
  def requires_hashing?(:reset_password), do: true
  def requires_hashing?(:change_email), do: true

  @doc """
  Checks if a token of this type is single-use.

  Login, reset_password, and change_email tokens are invalidated after use.
  """
  @spec single_use?(t()) :: boolean()
  def single_use?(:session), do: false
  def single_use?(:login), do: true
  def single_use?(:reset_password), do: true
  def single_use?(:change_email), do: true

  @doc """
  Returns the token size in bytes.
  """
  @spec token_size() :: pos_integer()
  def token_size, do: 32

  @doc """
  Returns a human-readable display name for the token type.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:session), do: "Session"
  def display_name(:login), do: "Login Link"
  def display_name(:reset_password), do: "Password Reset"
  def display_name(:change_email), do: "Email Change"

  @doc """
  Checks if this token type requires email verification context.
  """
  @spec requires_email_context?(t()) :: boolean()
  def requires_email_context?(:change_email), do: true
  def requires_email_context?(_), do: false
end
