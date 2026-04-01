defmodule Cadence.Test.Adapters.InMemoryTokenRepository do
  @moduledoc """
  In-memory token repository for testing.

  Implements `Cadence.Ports.Repository.Accounts.TokenRepository` behavior
  by storing tokens in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryTokenRepository.start_link()
        Application.put_env(:cadence, :token_repository, InMemoryTokenRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :token_repository)
          InMemoryTokenRepository.stop()
        end)
        :ok
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Accounts.TokenRepository

  alias Cadence.Domain.Accounts.Entities.User
  alias Cadence.Domain.Accounts.Entities.UserToken

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn ->
        %{
          tokens: %{},
          # Index by token+context for fast lookups
          token_index: %{},
          # Store users for session lookups (simplified for testing)
          users: %{}
        }
      end,
      name: name
    )
  end

  def stop(pid \\ __MODULE__) do
    try do
      Agent.stop(pid)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  # ============================================================================
  # TokenRepository Implementation
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.tokens, id) end) do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  @impl true
  def find_by_token_and_context(token, context) do
    key = {token, context}

    case Agent.get(__MODULE__, fn state -> Map.get(state.token_index, key) end) do
      nil -> {:error, :not_found}
      token_entity -> {:ok, token_entity}
    end
  end

  @impl true
  def save(%UserToken{} = token) do
    token =
      if token.id do
        token
      else
        %{token | id: Ecto.UUID.generate(), created_at: token.created_at || DateTime.utc_now()}
      end

    Agent.update(__MODULE__, fn state ->
      key = {token.token, token.context}

      %{
        state
        | tokens: Map.put(state.tokens, token.id, token),
          token_index: Map.put(state.token_index, key, token)
      }
    end)

    {:ok, token}
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.tokens, id) do
        {nil, _} ->
          {{:error, :not_found}, state}

        {token, new_tokens} ->
          key = {token.token, token.context}

          new_state = %{
            state
            | tokens: new_tokens,
              token_index: Map.delete(state.token_index, key)
          }

          {{:ok, token}, new_state}
      end
    end)
  end

  @impl true
  def delete_by_token_and_context(token, context) do
    Agent.update(__MODULE__, fn state ->
      key = {token, context}

      case Map.get(state.token_index, key) do
        nil ->
          state

        token_entity ->
          %{
            state
            | tokens: Map.delete(state.tokens, token_entity.id),
              token_index: Map.delete(state.token_index, key)
          }
      end
    end)

    :ok
  end

  # ============================================================================
  # Session Operations
  # ============================================================================

  @impl true
  def find_user_by_session_token(token) do
    Agent.get(__MODULE__, fn state ->
      with {:ok, token_entity} <- fetch_token(state, token, "session"),
           :ok <- ensure_valid_session_token(token_entity),
           {:ok, user} <- fetch_user(state, token_entity.user_id) do
        {:ok, user, token_entity.authenticated_at}
      end
    end)
  end

  @impl true
  def list_sessions_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    Agent.get(__MODULE__, fn state ->
      state.tokens
      |> Map.values()
      |> Enum.filter(fn t -> t.user_id == user_id && t.context == "session" end)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def delete_all_sessions_for_user(user_id) do
    Agent.update(__MODULE__, fn state ->
      {to_delete, remaining} =
        state.tokens
        |> Map.values()
        |> Enum.split_with(fn t -> t.user_id == user_id && t.context == "session" end)

      new_tokens = Map.new(remaining, fn t -> {t.id, t} end)

      new_index =
        Enum.reduce(to_delete, state.token_index, fn t, idx ->
          Map.delete(idx, {t.token, t.context})
        end)

      %{state | tokens: new_tokens, token_index: new_index}
    end)

    :ok
  end

  # ============================================================================
  # Magic Link Operations
  # ============================================================================

  @impl true
  def find_user_by_login_token(hashed_token) do
    Agent.get(__MODULE__, fn state ->
      with {:ok, token_entity} <- fetch_token(state, hashed_token, "login"),
           :ok <- ensure_valid_login_token(token_entity),
           {:ok, user} <- fetch_user(state, token_entity.user_id),
           :ok <- ensure_token_sent_to_user(token_entity, user) do
        {:ok, user}
      end
    end)
  end

  @impl true
  def delete_all_login_tokens_for_user(user_id) do
    Agent.update(__MODULE__, fn state ->
      {to_delete, remaining} =
        state.tokens
        |> Map.values()
        |> Enum.split_with(fn t -> t.user_id == user_id && t.context == "login" end)

      new_tokens = Map.new(remaining, fn t -> {t.id, t} end)

      new_index =
        Enum.reduce(to_delete, state.token_index, fn t, idx ->
          Map.delete(idx, {t.token, t.context})
        end)

      %{state | tokens: new_tokens, token_index: new_index}
    end)

    :ok
  end

  # ============================================================================
  # Email Change Operations
  # ============================================================================

  @impl true
  def find_change_email_token(hashed_token, context) do
    Agent.get(__MODULE__, fn state ->
      with {:ok, token_entity} <- fetch_token(state, hashed_token, context),
           :ok <- ensure_valid_change_email_token(token_entity) do
        {:ok, token_entity}
      end
    end)
  end

  defp fetch_token(state, token, context) do
    case Map.get(state.token_index, {token, context}) do
      nil -> {:error, :not_found}
      token_entity -> {:ok, token_entity}
    end
  end

  defp fetch_user(state, user_id) do
    case Map.get(state.users, user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp ensure_valid_session_token(token_entity) do
    if UserToken.valid_session_token?(token_entity), do: :ok, else: {:error, :expired}
  end

  defp ensure_valid_login_token(token_entity) do
    if UserToken.valid_login_token?(token_entity), do: :ok, else: {:error, :expired}
  end

  defp ensure_valid_change_email_token(token_entity) do
    if UserToken.valid_change_email_token?(token_entity), do: :ok, else: {:error, :expired}
  end

  defp ensure_token_sent_to_user(token_entity, user) do
    if token_entity.sent_to == user.email, do: :ok, else: {:error, :not_found}
  end

  @impl true
  def delete_all_change_email_tokens_for_user(user_id) do
    Agent.update(__MODULE__, fn state ->
      {to_delete, remaining} =
        state.tokens
        |> Map.values()
        |> Enum.split_with(fn t ->
          t.user_id == user_id && String.starts_with?(t.context, "change:")
        end)

      new_tokens = Map.new(remaining, fn t -> {t.id, t} end)

      new_index =
        Enum.reduce(to_delete, state.token_index, fn t, idx ->
          Map.delete(idx, {t.token, t.context})
        end)

      %{state | tokens: new_tokens, token_index: new_index}
    end)

    :ok
  end

  # ============================================================================
  # Bulk Token Operations
  # ============================================================================

  @impl true
  def list_all_for_user(user_id) do
    Agent.get(__MODULE__, fn state ->
      state.tokens
      |> Map.values()
      |> Enum.filter(&(&1.user_id == user_id))
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    end)
  end

  @impl true
  def delete_all_for_user(user_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      {to_delete, remaining} =
        state.tokens
        |> Map.values()
        |> Enum.split_with(fn token -> token.user_id == user_id end)

      new_tokens = Map.new(remaining, fn token -> {token.id, token} end)

      new_index =
        Enum.reduce(to_delete, state.token_index, fn token, idx ->
          Map.delete(idx, {token.token, token.context})
        end)

      {{:ok, to_delete}, %{state | tokens: new_tokens, token_index: new_index}}
    end)
  end

  # ============================================================================
  # Cleanup Operations
  # ============================================================================

  @impl true
  def delete_expired_tokens do
    deleted_count =
      Agent.get_and_update(__MODULE__, fn state ->
        {expired, valid} =
          state.tokens
          |> Map.values()
          |> Enum.split_with(&token_expired?/1)

        new_tokens = Map.new(valid, fn t -> {t.id, t} end)

        new_index =
          Enum.reduce(expired, state.token_index, fn t, idx ->
            Map.delete(idx, {t.token, t.context})
          end)

        {length(expired), %{state | tokens: new_tokens, token_index: new_index}}
      end)

    {:ok, deleted_count}
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Registers a user for session lookups.

  This is needed because the in-memory repo needs users to return from
  find_user_by_session_token.
  """
  def register_user(%User{} = user) do
    Agent.update(__MODULE__, fn state ->
      %{state | users: Map.put(state.users, user.id, user)}
    end)

    :ok
  end

  @doc """
  Updates a token for tests by token value and context.
  """
  def update_token(token, context, attrs) when is_map(attrs) do
    Agent.get_and_update(__MODULE__, fn state ->
      key = {token, context}

      case Map.get(state.token_index, key) do
        nil ->
          {{:error, :not_found}, state}

        token_entity ->
          updated = struct(token_entity, attrs)
          new_tokens = Map.put(state.tokens, updated.id, updated)
          new_index = Map.put(state.token_index, key, updated)

          {{:ok, updated}, %{state | tokens: new_tokens, token_index: new_index}}
      end
    end)
  end

  @doc """
  Returns all tokens in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.tokens) end)
  end

  @doc """
  Returns the count of tokens.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.tokens) end)
  end

  @doc """
  Clears all data from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ ->
      %{tokens: %{}, token_index: %{}, users: %{}}
    end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp token_expired?(%UserToken{context: "session"} = token) do
    not UserToken.valid_session_token?(token)
  end

  defp token_expired?(%UserToken{context: "login"} = token) do
    not UserToken.valid_login_token?(token)
  end

  defp token_expired?(%UserToken{context: "change:" <> _} = token) do
    not UserToken.valid_change_email_token?(token)
  end

  defp token_expired?(_), do: false

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit), do: Enum.take(items, limit)
end
