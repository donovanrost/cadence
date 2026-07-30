defmodule CadenceWeb.ScopeLoader do
  @moduledoc false

  import Phoenix.Component

  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Auth.Scope

  @spec assign_scope_from_session(Phoenix.LiveView.Socket.t(), map()) ::
          Phoenix.LiveView.Socket.t()
  def assign_scope_from_session(socket, session) do
    allow_browser_test_sandbox_owner(browser_test_sandbox_owner_key(session))

    case session["user_session_token"] do
      token when is_binary(token) ->
        case Cadence.Auth.authenticate_browser_session(token,
               current_organization_id: session["current_organization_id"],
               admin_mode?: CadenceWeb.AdminMode.active?(session["admin_mode_expires_at"])
             ) do
          {:ok, %Scope{} = scope} -> assign(socket, :current_scope, scope)
          _error -> assign(socket, :current_scope, nil)
        end

      _other ->
        assign(socket, :current_scope, nil)
    end
  end

  @spec browser_test_sandbox_owner_key(map() | term()) :: binary() | nil
  def browser_test_sandbox_owner_key(session) when is_map(session) do
    session_value(session, "browser_test_sandbox_owner_key")
  end

  def browser_test_sandbox_owner_key(_session), do: nil

  @spec allow_browser_test_sandbox_owner(binary() | nil) :: :ok | {:error, term()}
  def allow_browser_test_sandbox_owner(session_key \\ nil) do
    case browser_test_sandbox_owner(session_key) do
      {:ok, owner} ->
        allow_sandbox_owner(owner)

      {:error, reason} ->
        {:error, reason}

      :none ->
        :ok
    end
  end

  @spec allow_browser_test_sandbox_owner(binary() | nil, pid()) :: :ok | {:error, term()}
  def allow_browser_test_sandbox_owner(session_key, client_pid) when is_pid(client_pid) do
    case browser_test_sandbox_owner(session_key) do
      {:ok, owner} ->
        allow_sandbox_owner(owner, client_pid)

      {:error, reason} ->
        {:error, reason}

      :none ->
        :ok
    end
  end

  @spec browser_test_sandbox_owner(binary() | nil) :: {:ok, pid()} | :none | {:error, term()}
  def browser_test_sandbox_owner(session_key \\ nil) do
    case Application.get_env(:cadence_web, :browser_test_sandbox_owner) do
      %{owner: owner, key: ^session_key} when is_pid(owner) and is_binary(session_key) ->
        {:ok, owner}

      %{owner: owner, key: _key} when is_pid(owner) and is_binary(session_key) ->
        {:error, :browser_test_sandbox_owner_key_mismatch}

      owner when is_pid(owner) ->
        {:ok, owner}

      _owner when is_binary(session_key) ->
        {:error, :browser_test_sandbox_owner_missing}

      _owner ->
        :none
    end
  end

  defp allow_sandbox_owner(owner, client_pid \\ self()) do
    Sandbox.allow(Cadence.Repo, owner, client_pid)
    :ok
  catch
    :exit, reason -> {:error, {:browser_test_sandbox_owner_unavailable, reason}}
  end

  defp session_value(session, key) when is_map(session) do
    Map.get(session, key) || Map.get(session, :browser_test_sandbox_owner_key)
  end
end
