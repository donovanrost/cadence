defmodule CadenceWeb.AdminAuth do
  @moduledoc false

  import Phoenix.LiveView
  import Phoenix.Component

  alias Cadence.Auth.Scope

  def on_mount(:require_platform_admin, _params, session, socket) do
    socket = authenticate_scope(socket, session)

    case socket.assigns[:current_scope] do
      %Scope{} = scope ->
        if MapSet.member?(scope.capabilities, :platform_admin) do
          {:cont, socket}
        else
          {:halt, redirect(socket, to: "/operator")}
        end

      _other ->
        {:halt, redirect(socket, to: "/sign-in")}
    end
  end

  defp authenticate_scope(socket, session) do
    if connected?(socket) do
      assign_scope_from_session(socket, session)
    else
      socket
    end
  end

  defp assign_scope_from_session(socket, session) do
    case session["user_session_token"] do
      token when is_binary(token) ->
        assign_scope_from_token(socket, token, session["current_organization_id"])

      _other ->
        assign(socket, :current_scope, nil)
    end
  end

  defp assign_scope_from_token(socket, token, current_organization_id) do
    case Cadence.authenticate_api_token(token,
           current_organization_id: current_organization_id
         ) do
      {:ok, %Scope{} = scope} -> assign(socket, :current_scope, scope)
      _error -> assign(socket, :current_scope, nil)
    end
  end
end
