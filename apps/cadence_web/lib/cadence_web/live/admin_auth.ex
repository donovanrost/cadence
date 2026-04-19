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
        if MapSet.member?(scope.capabilities, :platform_admin) do
          {:cont, assign(socket, :nav_context, :admin)}
        else
          {:halt, redirect(socket, to: "/")}
        end

      _other ->
        {:halt, redirect(socket, to: "/sign-in")}
    end
  end
end
