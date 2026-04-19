defmodule CadenceWeb.OrganizationAuth do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  alias Cadence.Auth.Scope
  alias CadenceWeb.ScopeLoader

  def on_mount(:require_organization_scope, _params, session, socket) do
    socket = ScopeLoader.assign_scope_from_session(socket, session)

    case socket.assigns[:current_scope] do
      %Scope{capabilities: capabilities} = scope ->
        cond do
          MapSet.member?(capabilities, :platform_admin) ->
            {:halt, redirect(socket, to: "/admin")}

          scope.organization_membership != nil ->
            {:cont,
             socket
             |> assign(:nav_context, :organization)
             |> CadenceWeb.NotificationsBell.attach()}

          true ->
            {:halt, redirect(socket, to: "/no-organization")}
        end

      _other ->
        {:halt, redirect(socket, to: "/sign-in")}
    end
  end
end
