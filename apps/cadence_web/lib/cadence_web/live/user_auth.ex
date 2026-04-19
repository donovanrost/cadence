defmodule CadenceWeb.UserAuth do
  @moduledoc false

  import Phoenix.LiveView

  alias Cadence.Auth.Scope
  alias CadenceWeb.ScopeLoader

  def on_mount(:require_user_scope, _params, session, socket) do
    socket = ScopeLoader.assign_scope_from_session(socket, session)

    case socket.assigns[:current_scope] do
      %Scope{user: %_{} = _user} ->
        {:cont, socket}

      _other ->
        {:halt, redirect(socket, to: "/sign-in")}
    end
  end

  def on_mount(:attach_notifications_bell, _params, _session, socket) do
    {:cont, CadenceWeb.NotificationsBell.attach(socket)}
  end
end
