defmodule CadenceWeb.AdminOrganizationShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    {:ok, assign(socket, :organization, %{organization_id: org_id})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="admin-organization-show-page">
        <.vue
          id="admin-organization-show-component"
          v-component="FederatedFullPageSurface"
          application_key="organization_admin"
          surface_id="admin_organization_show"
          host_scope="admin"
          query_params={%{organization_id: @organization.organization_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
