defmodule CadenceWeb.AdminOrganizationListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    organizations = Cadence.Organizations.list_organizations()

    {:ok,
     socket
     |> assign(:page_title, "Organizations")
     |> assign(:nav_item, :admin_organizations)
     |> assign(:organizations_empty?, organizations == [])
     |> assign(:organization_rows, Enum.map(organizations, &organization_row/1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="admin-organizations-page" class="space-y-6">
      <.page_header
        title="Organizations"
        breadcrumbs={[{"Platform Admin", ~p"/admin"}, {"Organizations", nil}]}
      >
        <:actions>
          <.button navigate={~p"/admin/organizations/new"}>Create organization</.button>
        </:actions>
      </.page_header>

      <.empty_state
        :if={@organizations_empty?}
        title="No organizations yet"
        description="Create one to bring a customer onto the platform."
        action_label="Create organization"
        action_navigate={~p"/admin/organizations/new"}
      />

      <.card :if={!@organizations_empty?} padding={:none}>
        <.vue
          id="admin-organization-list-component"
          v-component="AdminOrganizationList"
          rows={@organization_rows}
          v-ssr={false}
        />
      </.card>
    </div>
    """
  end

  defp organization_row(organization) do
    %{
      id: "admin-organization-#{organization.organization_id}",
      display_name: organization.display_name,
      slug: organization.slug,
      href: ~p"/admin/organizations/#{organization.organization_id}"
    }
  end
end
