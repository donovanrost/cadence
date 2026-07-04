defmodule CadenceWeb.ScopeLoader do
  @moduledoc false

  import Phoenix.Component

  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Auth.Scope

  @spec assign_scope_from_session(Phoenix.LiveView.Socket.t(), map()) ::
          Phoenix.LiveView.Socket.t()
  def assign_scope_from_session(socket, session) do
    allow_browser_test_sandbox_owner(session_value(session, "browser_test_sandbox_owner_key"))

    case session["user_session_token"] do
      token when is_binary(token) ->
        case Cadence.authenticate_api_token(token,
               current_organization_id: session["current_organization_id"]
             ) do
          {:ok, %Scope{} = scope} -> assign(socket, :current_scope, scope)
          _error -> assign(socket, :current_scope, nil)
        end

      _other ->
        assign(socket, :current_scope, nil)
    end
  end

  @spec allow_browser_test_sandbox_owner(binary() | nil) :: :ok
  def allow_browser_test_sandbox_owner(session_key \\ nil) do
    case Application.get_env(:cadence_web, :browser_test_sandbox_owner) do
      %{owner: owner, key: ^session_key} when is_pid(owner) and is_binary(session_key) ->
        Sandbox.allow(Cadence.Repo, owner, self())
        :ok

      owner when is_pid(owner) ->
        Sandbox.allow(Cadence.Repo, owner, self())
        :ok

      _owner ->
        :ok
    end
  catch
    :exit, _reason -> :ok
  end

  defp session_value(session, key) when is_map(session) do
    Map.get(session, key) || Map.get(session, :browser_test_sandbox_owner_key)
  end
end
