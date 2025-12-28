defmodule Cadence.Domain.Accounts.Entities.UserToken do
  @moduledoc """
  Pure domain entity representing a user authentication token.

  Tokens are used for various authentication flows:
  - Session tokens: Long-lived tokens stored in cookies
  - Login tokens: Short-lived magic link tokens
  - Email change tokens: Tokens sent to verify new email addresses

  This entity handles token generation, hashing, and validation logic
  without persistence concerns.

  ## Token Types

  - `:session` - Browser session tokens (14 days validity)
  - `:login` - Magic link login tokens (15 minutes validity)
  - `:change_email` - Email change confirmation tokens (7 days validity)

  ## Security

  Tokens stored in the database are hashed. The original token is only
  provided once at creation time and should be sent to the user via
  secure channel (email, cookie, etc.).
  """

  alias Cadence.Domain.Accounts.ValueObjects.TokenType

  @type t :: %__MODULE__{
          id: String.t() | nil,
          token: binary(),
          context: String.t(),
          user_id: String.t(),
          sent_to: String.t() | nil,
          authenticated_at: DateTime.t() | nil,
          created_at: DateTime.t() | nil
        }

  @enforce_keys [:token, :context, :user_id]
  defstruct [
    :id,
    :token,
    :context,
    :user_id,
    :sent_to,
    :authenticated_at,
    :created_at
  ]

  @hash_algorithm :sha256
  @rand_size 32

  # Validity periods
  @session_validity_days 14
  @magic_link_validity_minutes 15
  @change_email_validity_days 7

  # ===========================================================================
  # Token Generation
  # ===========================================================================

  @doc """
  Generates a session token for the given user.

  Returns `{raw_token, token_entity}` where:
  - `raw_token` is the token to store in the session cookie
  - `token_entity` is the entity to persist (token is NOT hashed for sessions)

  Session tokens are stored as-is since they're already in a signed cookie.
  """
  @spec build_session_token(String.t(), DateTime.t() | nil) :: {binary(), t()}
  def build_session_token(user_id, authenticated_at \\ nil) do
    build_session_token_with_bytes(
      user_id,
      authenticated_at,
      :crypto.strong_rand_bytes(@rand_size)
    )
  end

  @doc """
  Builds a session token with provided random bytes.

  Useful for testing with deterministic tokens.
  """
  @spec build_session_token_with_bytes(String.t(), DateTime.t() | nil, binary()) ::
          {binary(), t()}
  def build_session_token_with_bytes(user_id, authenticated_at, random_bytes) do
    token = random_bytes
    dt = authenticated_at || DateTime.utc_now() |> DateTime.truncate(:second)

    token_entity = %__MODULE__{
      token: token,
      context: "session",
      user_id: user_id,
      authenticated_at: dt,
      created_at: DateTime.utc_now()
    }

    {token, token_entity}
  end

  @doc """
  Generates a magic link login token for the given user.

  Returns `{url_safe_token, token_entity}` where:
  - `url_safe_token` is the base64-encoded token to include in the login URL
  - `token_entity` is the entity to persist (with hashed token)
  """
  @spec build_login_token(String.t(), String.t()) :: {String.t(), t()}
  def build_login_token(user_id, email) do
    build_login_token_with_bytes(user_id, email, :crypto.strong_rand_bytes(@rand_size))
  end

  @doc """
  Builds a login token with provided random bytes.
  """
  @spec build_login_token_with_bytes(String.t(), String.t(), binary()) :: {String.t(), t()}
  def build_login_token_with_bytes(user_id, email, random_bytes) do
    build_hashed_token(user_id, "login", email, random_bytes)
  end

  @doc """
  Generates an email change confirmation token.

  Returns `{url_safe_token, token_entity}` where:
  - `url_safe_token` is the base64-encoded token for the confirmation URL
  - `token_entity` is the entity to persist (with hashed token)

  The context includes the CURRENT email for verification.
  The sent_to field contains the NEW email.
  """
  @spec build_change_email_token(String.t(), String.t(), String.t()) :: {String.t(), t()}
  def build_change_email_token(user_id, current_email, new_email) do
    build_change_email_token_with_bytes(
      user_id,
      current_email,
      new_email,
      :crypto.strong_rand_bytes(@rand_size)
    )
  end

  @doc """
  Builds a change email token with provided random bytes.
  """
  @spec build_change_email_token_with_bytes(String.t(), String.t(), String.t(), binary()) ::
          {String.t(), t()}
  def build_change_email_token_with_bytes(user_id, current_email, new_email, random_bytes) do
    context = "change:#{current_email}"
    build_hashed_token(user_id, context, new_email, random_bytes)
  end

  # ===========================================================================
  # Token Verification
  # ===========================================================================

  @doc """
  Verifies a session token is valid based on age.

  Returns `true` if the token was created within the validity period.
  """
  @spec valid_session_token?(t()) :: boolean()
  def valid_session_token?(%__MODULE__{context: "session", created_at: created_at}) do
    not expired?(created_at, @session_validity_days, :day)
  end

  def valid_session_token?(_), do: false

  @doc """
  Verifies a magic link token and returns the hashed version for lookup.

  Returns `{:ok, hashed_token}` if the token can be decoded,
  or `:error` if the token is invalid.
  """
  @spec verify_login_token(String.t()) :: {:ok, binary()} | :error
  def verify_login_token(url_token) do
    case Base.url_decode64(url_token, padding: false) do
      {:ok, decoded} -> {:ok, hash_token(decoded)}
      :error -> :error
    end
  end

  @doc """
  Checks if a login token (from database) is still valid.
  """
  @spec valid_login_token?(t()) :: boolean()
  def valid_login_token?(%__MODULE__{context: "login", created_at: created_at}) do
    not expired?(created_at, @magic_link_validity_minutes, :minute)
  end

  def valid_login_token?(_), do: false

  @doc """
  Verifies a change email token and returns the hashed version for lookup.
  """
  @spec verify_change_email_token(String.t()) :: {:ok, binary()} | :error
  def verify_change_email_token(url_token) do
    case Base.url_decode64(url_token, padding: false) do
      {:ok, decoded} -> {:ok, hash_token(decoded)}
      :error -> :error
    end
  end

  @doc """
  Checks if a change email token is still valid.
  """
  @spec valid_change_email_token?(t()) :: boolean()
  def valid_change_email_token?(%__MODULE__{context: "change:" <> _, created_at: created_at}) do
    not expired?(created_at, @change_email_validity_days, :day)
  end

  def valid_change_email_token?(_), do: false

  @doc """
  Extracts the new email from a change email token's sent_to field.
  """
  @spec extract_new_email(t()) :: {:ok, String.t()} | :error
  def extract_new_email(%__MODULE__{context: "change:" <> _, sent_to: email})
      when is_binary(email) do
    {:ok, email}
  end

  def extract_new_email(_), do: :error

  # ===========================================================================
  # Reconstruction
  # ===========================================================================

  @doc """
  Reconstructs a token entity from persisted data.
  """
  @spec from_persistence(map()) :: t()
  def from_persistence(attrs) do
    %__MODULE__{
      id: attrs[:id],
      token: attrs[:token],
      context: attrs[:context],
      user_id: attrs[:user_id],
      sent_to: attrs[:sent_to],
      authenticated_at: attrs[:authenticated_at],
      created_at: attrs[:created_at]
    }
  end

  # ===========================================================================
  # Predicates
  # ===========================================================================

  @doc """
  Returns the token type based on context.
  """
  @spec token_type(t()) :: TokenType.t()
  def token_type(%__MODULE__{context: "session"}), do: :session
  def token_type(%__MODULE__{context: "login"}), do: :login
  def token_type(%__MODULE__{context: "change:" <> _}), do: :change_email

  @doc """
  Checks if this is a session token.
  """
  @spec session_token?(t()) :: boolean()
  def session_token?(%__MODULE__{context: "session"}), do: true
  def session_token?(_), do: false

  @doc """
  Checks if this is a login (magic link) token.
  """
  @spec login_token?(t()) :: boolean()
  def login_token?(%__MODULE__{context: "login"}), do: true
  def login_token?(_), do: false

  @doc """
  Returns the validity period for session tokens in days.
  """
  @spec session_validity_days() :: pos_integer()
  def session_validity_days, do: @session_validity_days

  @doc """
  Returns the validity period for magic link tokens in minutes.
  """
  @spec magic_link_validity_minutes() :: pos_integer()
  def magic_link_validity_minutes, do: @magic_link_validity_minutes

  @doc """
  Returns the random token size in bytes.
  """
  @spec token_size() :: pos_integer()
  def token_size, do: @rand_size

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp build_hashed_token(user_id, context, sent_to, random_bytes) do
    hashed = hash_token(random_bytes)
    url_token = Base.url_encode64(random_bytes, padding: false)

    token_entity = %__MODULE__{
      token: hashed,
      context: context,
      user_id: user_id,
      sent_to: sent_to,
      created_at: DateTime.utc_now()
    }

    {url_token, token_entity}
  end

  defp hash_token(token) do
    :crypto.hash(@hash_algorithm, token)
  end

  defp expired?(nil, _amount, _unit), do: true

  defp expired?(created_at, amount, :day) do
    cutoff = DateTime.add(DateTime.utc_now(), -amount, :day)
    DateTime.compare(created_at, cutoff) == :lt
  end

  defp expired?(created_at, amount, :minute) do
    cutoff = DateTime.add(DateTime.utc_now(), -amount, :minute)
    DateTime.compare(created_at, cutoff) == :lt
  end
end
