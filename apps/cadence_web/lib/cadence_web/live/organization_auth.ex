defmodule CadenceWeb.OrganizationAuth do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  alias Cadence.Auth.Scope

  def on_mount(:require_organization_scope, _params, session, socket) do
    socket = assign_scope_from_session(socket, session)

    case socket.assigns[:current_scope] do
      %Scope{organization_membership: %_{} = _membership} ->
        {:cont, assign(socket, :nav_context, :organization)}

      %Scope{} ->
        {:halt, redirect(socket, to: "/no-organization")}

      _other ->
        {:halt, redirect(socket, to: "/sign-in")}
    end
  end

  defp assign_scope_from_session(socket, session) do
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
