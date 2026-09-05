defmodule CadenceWeb.MissionNewLive do
  @moduledoc false

  # Authz note: Any active organization member can create a mission. This gate
  # should tighten once platform-wide authorization is defined (likely to the
  # :organization_admin role, possibly a finer capability).
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Mission")
     |> assign(:nav_item, :missions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="mission-new-component"
        v-component="FederatedFullPageSurface"
        application_key="mission_catalog"
        surface_id="mission_new"
        host_scope="organization"
        organization_id={@current_scope.organization.organization_id}
        query_params={%{organization_id: @current_scope.organization.organization_id}}
        v-ssr={false}
        class="space-y-6 max-w-xl"
      />
    </Layouts.app>
    """
  end
end
