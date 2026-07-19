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

  def on_mount(:attach_user_menu, _params, _session, socket) do
    {:cont,
     socket
     |> Phoenix.Component.assign(:user_menu_memberships, memberships_for(socket))
     |> Phoenix.Component.assign(:user_menu_platform_admin?, platform_admin?(socket))}
  end

  defp memberships_for(%{assigns: %{current_scope: %Scope{user: %{user_id: user_id}}}})
       when is_binary(user_id) do
    Cadence.Accounts.list_user_memberships(user_id)
  end

  defp memberships_for(_socket), do: []

  defp platform_admin?(%{assigns: %{current_scope: %Scope{capabilities: capabilities}}})
       when not is_nil(capabilities) do
    MapSet.member?(capabilities, :platform_admin)
  end

  defp platform_admin?(_socket), do: false
end
