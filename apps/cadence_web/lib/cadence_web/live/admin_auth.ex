defmodule CadenceWeb.AdminAuth do
  @moduledoc false

  import Phoenix.LiveView
  import Phoenix.Component

  alias Cadence.Auth.Scope
  alias CadenceWeb.ScopeLoader

  def on_mount(:require_platform_admin, _params, session, socket) do
    socket = ScopeLoader.assign_scope_from_session(socket, session)

    case socket.assigns[:current_scope] do
      %Scope{} = scope ->
        cond do
          Scope.admin_mode?(scope) ->
            {:cont,
             socket
             |> assign(:nav_context, :admin)
             |> CadenceWeb.NotificationsBell.attach()}

          Scope.platform_admin_eligible?(scope) ->
            {:halt, redirect(socket, to: "/admin-mode")}

          true ->
            {:halt, redirect(socket, to: "/")}
        end

      _other ->
        {:halt, redirect(socket, to: "/sign-in")}
    end
  end
end
