defmodule CadenceWeb.LiveAuth do
  @moduledoc """
  on_mount hooks for LiveView authorization.

  Usage in LiveView modules:

      defmodule MyAppWeb.SomeLive do
        use MyAppWeb, :live_view

        on_mount {CadenceWeb.LiveAuth, :require_authenticated}
        on_mount {CadenceWeb.LiveAuth, :require_system_admin}
        on_mount {CadenceWeb.LiveAuth, :require_organization}
      end
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Cadence.Accounts.Scope

  @doc """
  Called by live_session to initialize session data from connection assigns.
  """
  def on_session_init(conn) do
    %{"current_scope" => conn.assigns.current_scope}
  end

  @doc """
  on_mount callback for LiveView authorization.

  When called without an atom (from `on_mount CadenceWeb.LiveAuth`),
  it assigns the current_scope to the socket.

  Available hooks:
  - `:require_authenticated` - Ensures the user is authenticated
  - `:require_system_admin` - Ensures the user is a system admin
  - `:require_organization` - Ensures the user has a current organization
  """
  def on_mount(:default, _params, _session, socket) do
    # This is called when using: on_mount CadenceWeb.LiveAuth
    # The current_scope should already be in socket.assigns from the LiveView mount
    # which copies all conn.assigns
    {:cont, socket}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    # Get scope from session (passed via live_session session: option)
    current_scope = Map.get(session, "current_scope")

    require Logger

    Logger.debug(
      "LiveAuth.require_authenticated - current_scope from session: #{inspect(current_scope)}"
    )

    # Assign it to socket so it's available in LiveView
    socket = assign(socket, :current_scope, current_scope)

    cond do
      is_nil(current_scope) ->
        Logger.debug("LiveAuth.require_authenticated - FAILED: current_scope is nil")

        socket =
          socket
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: "/users/log-in")

        {:halt, socket}

      is_nil(current_scope.user) ->
        Logger.debug("LiveAuth.require_authenticated - FAILED: current_scope.user is nil")

        socket =
          socket
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: "/users/log-in")

        {:halt, socket}

      true ->
        Logger.debug("LiveAuth.require_authenticated - PASSED")
        {:cont, socket}
    end
  end

  def on_mount(:require_system_admin, _params, _session, socket) do
    require Logger
    current_scope = Map.get(socket.assigns, :current_scope)
    is_admin = current_scope && Scope.system_admin?(current_scope)

    Logger.debug("LiveAuth.require_system_admin - current_scope: #{inspect(current_scope)}")
    Logger.debug("LiveAuth.require_system_admin - is_admin: #{inspect(is_admin)}")

    if is_admin do
      Logger.debug("LiveAuth.require_system_admin - PASSED")
      {:cont, socket}
    else
      Logger.debug("LiveAuth.require_system_admin - FAILED")

      socket =
        socket
        |> put_flash(:error, "You must be a system administrator to access this page.")
        |> redirect(to: "/")

      {:halt, socket}
    end
  end

  def on_mount(:require_organization, _params, _session, socket) do
    if socket.assigns[:current_scope] && socket.assigns.current_scope.current_organization do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You must select an organization to access this page.")
        |> redirect(to: "/")

      {:halt, socket}
    end
  end

  def on_mount(:assign_scope, _params, session, socket) do
    scope = session["current_scope"]
    {:cont, assign(socket, :scope, scope)}
  end

  def on_mount(:put_current_path, _params, _session, socket) do
    # Assign the current path to the socket for use in navigation highlighting
    {:cont,
     attach_hook(socket, :set_current_path, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :current_path, URI.parse(uri).path)}
     end)}
  end

  def on_mount(:load_mission, params, _session, socket) do
    # Load mission from route params for the mission sidebar layout
    # Supports both :id and :mission_id param names
    mission_id = params["id"] || params["mission_id"]

    if mission_id do
      case Cadence.Missions.get_mission(mission_id) do
        nil ->
          socket =
            socket
            |> put_flash(:error, "Mission not found.")
            |> redirect(to: "/missions")

          {:halt, socket}

        mission ->
          {:cont, assign(socket, :mission, mission)}
      end
    else
      {:cont, assign(socket, :mission, nil)}
    end
  end
end
