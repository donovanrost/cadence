defmodule CadenceWeb.OpsContactDetailLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"provider_reservation_id" => reservation_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Provider reservation #{reservation_id}")
     |> assign(:ops_nav_item, :contacts)
     |> assign(:provider_reservation_id, reservation_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-detail-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="contact_detail"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"provider_reservation_id" => @provider_reservation_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
