defmodule CadenceWeb.MissionApplicationsLive do
  @moduledoc "Mission-scoped inventory for registered product applications."

  use CadenceWeb, :live_view

  alias Cadence.Applications.HostContext
  alias CadenceWeb.{ApplicationInventory, ApplicationInventoryCard, ApplicationInventoryLifecycle}

  @impl true
  def mount(_params, _session, socket) do
    host_context = HostContext.mission(socket.assigns.current_mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "#{socket.assigns.current_mission.display_name} Applications")
     |> assign(:nav_item, :mission_applications)
     |> assign(:application_host_context, host_context)
     |> stream_configure(:applications,
       dom_id: fn application ->
         ApplicationInventoryCard.dom_id(host_context, application.application_key)
       end
     )
     |> stream(:applications, application_rows(socket.assigns.current_scope, host_context))}
  end

  @impl true
  def handle_event("install_application", %{"key" => application_key}, socket) do
    ApplicationInventoryLifecycle.install(
      socket,
      application_key,
      :allowed,
      &refresh_applications/1
    )
  end

  def handle_event("disable_application", %{"key" => application_key}, socket) do
    ApplicationInventoryLifecycle.disable(socket, application_key, &refresh_applications/1)
  end

  def handle_event("uninstall_application", %{"key" => application_key}, socket) do
    ApplicationInventoryLifecycle.uninstall(socket, application_key, &refresh_applications/1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="mission-applications-page" class="space-y-6">
        <.page_header
          title="Applications"
          subtitle="Install mission-scoped product capabilities and open their host-rendered workspaces."
          breadcrumbs={[
            {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
            {"Applications", nil}
          ]}
        />

        <section
          id="mission-applications-list"
          class="grid gap-4 lg:grid-cols-2"
          phx-update="stream"
        >
          <ApplicationInventoryCard.application_inventory_card
            :for={{dom_id, app} <- @streams.applications}
            id={dom_id}
            app={app}
            host_context={@application_host_context}
            scope_label="Mission Application"
            manage_path={~p"/missions/#{@current_mission.mission_id}/applications/#{app.application_key}"}
          />
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp application_rows(scope, host_context) do
    case ApplicationInventory.catalog(scope, host_context) do
      {:ok, applications} -> applications
      {:error, _reason} -> []
    end
  end

  defp refresh_applications(socket) do
    stream(
      socket,
      :applications,
      application_rows(
        socket.assigns.current_scope,
        socket.assigns.application_host_context
      ),
      reset: true
    )
  end
end
