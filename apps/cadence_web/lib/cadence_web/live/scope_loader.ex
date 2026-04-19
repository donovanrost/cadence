defmodule CadenceWeb.ScopeLoader do
  @moduledoc false

  import Phoenix.Component

  alias Cadence.Auth.Scope

  @spec assign_scope_from_session(Phoenix.LiveView.Socket.t(), map()) ::
          Phoenix.LiveView.Socket.t()
  def assign_scope_from_session(socket, session) do
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
end
