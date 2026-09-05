defmodule CadenceWeb.AdminOrganizationListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.AdminOrganizationListLive.Presentation

  @impl true
  def mount(_params, _session, socket) do
    organizations = Cadence.Organizations.list_organizations()

    {:ok,
     socket
     |> assign(:page_title, "Organizations")
     |> assign(:nav_item, :admin_organizations)
     |> assign(:presentation, Presentation.build(organizations))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="admin-organization-list-page-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="admin_organizations"
        host_scope="admin"
        v-ssr={false}
      />
    </Layouts.app>
    """
  end
end
