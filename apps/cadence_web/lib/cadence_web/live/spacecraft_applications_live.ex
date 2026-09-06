defmodule CadenceWeb.SpacecraftApplicationsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Applications")
     |> assign(:nav_item, :spacecraft)
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
        id="spacecraft-applications-page-component"
        v-component="SpacecraftApplicationManagement"
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
