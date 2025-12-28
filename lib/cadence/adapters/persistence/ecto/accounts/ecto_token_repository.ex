defmodule Cadence.Adapters.Persistence.Ecto.Accounts.EctoTokenRepository do
  @moduledoc """
  Ecto-based implementation of the TokenRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for user tokens using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :token_repository, Cadence.Adapters.Persistence.Ecto.Accounts.EctoTokenRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Accounts.TokenRepository.impl()
      {:ok, token} = repo.find(id)
  """

  @behaviour Cadence.Ports.Repository.Accounts.TokenRepository

  import Ecto.Query

  alias Cadence.Accounts.UserToken, as: TokenSchema
  alias Cadence.Adapters.Persistence.Ecto.Accounts.EctoUserRepository
  alias Cadence.Domain.Accounts.Entities.UserToken, as: TokenEntity
  alias Cadence.Repo

  # Token validity periods (matching domain entity)
  @session_validity_days 14
  @magic_link_validity_minutes 15
  @change_email_validity_days 7

  # ===========================================================================
  # Token CRUD Operations
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(TokenSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def find_by_token_and_context(token, context) do
    query =
      from t in TokenSchema,
        where: t.token == ^token,
        where: t.context == ^context

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def save(%TokenEntity{} = entity) do
    attrs = entity_to_schema_attrs(entity)

    %TokenSchema{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  @impl true
  def delete(id) do
    case Repo.get(TokenSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, schema_to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @impl true
  def delete_by_token_and_context(token, context) do
    query =
      from t in TokenSchema,
        where: t.token == ^token,
        where: t.context == ^context

    Repo.delete_all(query)
    :ok
  end

  # ===========================================================================
  # Session Operations
  # ===========================================================================

  @impl true
  def find_user_by_session_token(token) do
    query =
      from t in TokenSchema,
        join: u in assoc(t, :user),
        where: t.token == ^token,
        where: t.context == "session",
        where: t.inserted_at > ago(@session_validity_days, "day"),
        select: {u, t.authenticated_at}

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      {user_schema, authenticated_at} ->
        user = EctoUserRepository.schema_to_entity(user_schema)
        {:ok, user, authenticated_at}
    end
  end

  @impl true
  def list_sessions_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    query =
      from t in TokenSchema,
        where: t.user_id == ^user_id,
        where: t.context == "session",
        order_by: [desc: t.inserted_at],
        limit: ^limit

    query
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def delete_all_sessions_for_user(user_id) do
    query =
      from t in TokenSchema,
        where: t.user_id == ^user_id,
        where: t.context == "session"

    Repo.delete_all(query)
    :ok
  end

  # ===========================================================================
  # Magic Link Operations
  # ===========================================================================

  @impl true
  def find_user_by_login_token(hashed_token) do
    query =
      from t in TokenSchema,
        join: u in assoc(t, :user),
        where: t.token == ^hashed_token,
        where: t.context == "login",
        where: t.inserted_at > ago(@magic_link_validity_minutes, "minute"),
        where: t.sent_to == u.email,
        select: u

    case Repo.one(query) do
      nil -> {:error, :not_found}
      user_schema -> {:ok, EctoUserRepository.schema_to_entity(user_schema)}
    end
  end

  @impl true
  def delete_all_login_tokens_for_user(user_id) do
    query =
      from t in TokenSchema,
        where: t.user_id == ^user_id,
        where: t.context == "login"

    Repo.delete_all(query)
    :ok
  end

  # ===========================================================================
  # Email Change Operations
  # ===========================================================================

  @impl true
  def find_change_email_token(hashed_token, context) do
    query =
      from t in TokenSchema,
        where: t.token == ^hashed_token,
        where: t.context == ^context,
        where: t.inserted_at > ago(@change_email_validity_days, "day")

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def delete_all_change_email_tokens_for_user(user_id) do
    query =
      from t in TokenSchema,
        where: t.user_id == ^user_id,
        where: like(t.context, "change:%")

    Repo.delete_all(query)
    :ok
  end

  # ===========================================================================
  # Bulk Token Operations
  # ===========================================================================

  @impl true
  def list_all_for_user(user_id) do
    query =
      from t in TokenSchema,
        where: t.user_id == ^user_id,
        order_by: [desc: t.inserted_at]

    query
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def delete_all_for_user(user_id) do
    # First get all tokens so we can return them
    tokens = list_all_for_user(user_id)

    # Then delete them
    query =
      from t in TokenSchema,
        where: t.user_id == ^user_id

    Repo.delete_all(query)

    {:ok, tokens}
  end

  # ===========================================================================
  # Cleanup Operations
  # ===========================================================================

  @impl true
  def delete_expired_tokens do
    now = DateTime.utc_now()
    session_cutoff = DateTime.add(now, -@session_validity_days, :day)
    login_cutoff = DateTime.add(now, -@magic_link_validity_minutes, :minute)
    change_email_cutoff = DateTime.add(now, -@change_email_validity_days, :day)

    # Delete expired session tokens
    session_query =
      from t in TokenSchema,
        where: t.context == "session",
        where: t.inserted_at < ^session_cutoff

    {session_count, _} = Repo.delete_all(session_query)

    # Delete expired login tokens
    login_query =
      from t in TokenSchema,
        where: t.context == "login",
        where: t.inserted_at < ^login_cutoff

    {login_count, _} = Repo.delete_all(login_query)

    # Delete expired change email tokens
    change_query =
      from t in TokenSchema,
        where: like(t.context, "change:%"),
        where: t.inserted_at < ^change_email_cutoff

    {change_count, _} = Repo.delete_all(change_query)

    {:ok, session_count + login_count + change_count}
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec schema_to_entity(TokenSchema.t()) :: TokenEntity.t()
  def schema_to_entity(%TokenSchema{} = schema) do
    %TokenEntity{
      id: schema.id,
      token: schema.token,
      context: schema.context,
      user_id: schema.user_id,
      sent_to: schema.sent_to,
      authenticated_at: schema.authenticated_at,
      created_at: schema.inserted_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for persistence.
  """
  @spec entity_to_schema_attrs(TokenEntity.t()) :: map()
  def entity_to_schema_attrs(%TokenEntity{} = entity) do
    %{
      token: entity.token,
      context: entity.context,
      user_id: entity.user_id,
      sent_to: entity.sent_to,
      authenticated_at: entity.authenticated_at
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp handle_result({:ok, schema}), do: {:ok, schema_to_entity(schema)}
  defp handle_result({:error, changeset}), do: {:error, extract_errors(changeset)}

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    {:validation, errors}
  end
end
