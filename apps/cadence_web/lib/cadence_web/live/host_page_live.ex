defmodule CadenceWeb.HostPageLive do
  @moduledoc "Authenticated context and event transport for the persistent Vue host."
  use CadenceWeb, :live_view

  alias Cadence.Reads.OperationalContext

  alias CadenceWeb.{HostContext, HostPageAuthorization}

  alias Plug.Conn.{InvalidQueryError, Query}

  @impl true
  def mount(_params, session, socket) do
    session =
      Map.take(session, ["user_session_token", "current_organization_id", "admin_mode_expires_at"])

    {:ok, Phoenix.LiveView.put_private(socket, :host_navigation_session, session)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    location = URI.parse(uri)
    path = location.path <> if(location.query, do: "?" <> location.query, else: "")

    case prepare_context(socket, path) do
      {:ok, socket} -> {:noreply, socket}
      {:halt, socket} -> {:noreply, socket}
      :error -> {:noreply, redirect(socket, to: "/console")}
    end
  end

  @impl true
  def handle_event("host:context", %{"path" => path}, socket) do
    case prepare_context(socket, path) do
      {:ok, socket} -> {:reply, %{ok: true, snapshot: snapshot(socket.assigns)}, socket}
      {:halt, socket} -> {:noreply, socket}
      :error -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:reply, %{ok: false}, socket}

  @impl true
  # L21: the notifications page is gone (DECISIONS #79); these broadcasts refresh nothing here.
  def handle_info({event, _record}, socket)
      when event in [:notification_created, :notification_updated, :invitation_accepted],
      do: {:noreply, socket}

  defp prepare_context(socket, path) do
    with {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params) do
      socket = assign(socket, host_path: path, page_title: "Cadence")

      socket =
        if socket.assigns[:ops_context_active?] do
          socket
          |> assign(:active_dashboard_id, info.params["dashboard_id"])
          |> assign(
            :ops_context,
            OperationalContext.pin_command_focus(
              socket.assigns.ops_context,
              info.params["focus_command_id"]
            )
          )
        else
          socket
        end

      {:ok, socket}
    else
      {:halt, socket} -> {:halt, socket}
      _invalid -> :error
    end
  end

  defp resolve_path(path) when is_binary(path) and byte_size(path) <= 8192 do
    with %URI{scheme: nil, host: nil, fragment: nil, path: "/" <> _} = uri <- URI.parse(path),
         %{phoenix_live_view: {__MODULE__, _, _, _}, host_policy: _} = info <-
           Phoenix.Router.route_info(CadenceWeb.Router, "GET", uri.path, "localhost") do
      # Resource identity comes from the matched path, never query parameters.
      params = Map.merge(Query.decode(uri.query || ""), info.path_params)
      {:ok, Map.put(info, :params, params)}
    else
      _invalid -> :error
    end
  rescue
    ArgumentError -> :error
    InvalidQueryError -> :error
  end

  defp resolve_path(_path), do: :error

  defp snapshot(assigns) do
    %{
      path: assigns.host_path,
      context:
        assigns
        |> HostContext.from_assigns()
        |> Map.drop([:nav_context, :nav_item, :ops_nav_item, :active_dashboard_id]),
      ops_page: assigns[:ops_page]
    }
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, snapshot: snapshot(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue id="application-shell" v-component="BrowserHost" snapshot={@snapshot} v-ssr={false} />
    </Layouts.app>
    """
  end
end
