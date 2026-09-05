defmodule CadenceWeb.AdminOrganizationInviteLive do
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
      <.vue
        id="admin-organization-invite-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="admin_organization_invite"
        host_scope="admin"
        query_params={%{organization_id: @organization.organization_id}}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end
end
