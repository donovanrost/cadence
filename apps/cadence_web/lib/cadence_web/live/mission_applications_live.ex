defmodule CadenceWeb.MissionApplicationsLive do
  @moduledoc "Mission-scoped inventory for registered product applications."

  use CadenceWeb, :live_view

  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "#{socket.assigns.current_mission.display_name} Applications")
     |> assign(:nav_item, :mission_applications)
     |> CadenceWeb.ApplicationManagement.load()}
  end

  @impl true
  defdelegate handle_event(event, params, socket), to: CadenceWeb.ApplicationManagement

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        :if={@presentation}
        id="mission-applications-page-component"
        v-component="MissionApplicationManagement"
        presentation={@presentation}
        v-on:install={JS.push("install")}
        v-on:disable={JS.push("disable")}
        v-on:uninstall={JS.push("uninstall")}
        v-ssr={false}
        class="contents"
      />
      <p :if={@management_error} id="application-management-error" role="alert">{@management_error}</p>
    </Layouts.app>
    """
  end
end
