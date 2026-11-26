defmodule CadenceWeb.OrganizationAuth do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  alias Cadence.Auth.Scope
  alias CadenceWeb.ScopeLoader

  def on_mount(:require_organization_scope, _params, session, socket) do
    socket = ScopeLoader.assign_scope_from_session(socket, session)

    case socket.assigns[:current_scope] do
      %Scope{} = scope ->
        cond do
          scope.organization_membership != nil or
              (Scope.admin_mode?(scope) and scope.organization != nil) ->
            {:cont,
             socket
             |> assign(:nav_context, :organization)
             |> CadenceWeb.NotificationsBell.attach()}

          Scope.admin_mode?(scope) ->
            # L7: platform admin lives in the console (the legacy /admin only redirects there).
            {:halt, redirect(socket, to: "/console/admin")}

          true ->
            {:halt, redirect(socket, to: "/console/no-organization")}
        end

      _other ->
        {:halt, redirect(socket, to: "/console/sign-in")}
    end
  end

  def on_mount(:require_organization_admin, _params, _session, socket) do
    case socket.assigns[:current_scope] do
      %Scope{capabilities: capabilities} ->
        if MapSet.member?(capabilities, :organization_admin) or
             MapSet.member?(capabilities, :platform_admin) do
          {:cont, socket}
        else
          {:halt,
           socket
           |> redirect(to: "/console")}
        end

      _other ->
        {:halt, redirect(socket, to: "/console/sign-in")}
    end
  end
end
