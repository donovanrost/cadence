defmodule CadenceWeb.OpsContactRecordLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"contact_id" => contact_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Contact Record")
     |> assign(:ops_nav_item, :contacts)
     |> assign(:contact_id, contact_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-record-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="contact_record"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"contact_id" => @contact_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
