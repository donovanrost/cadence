defmodule CadenceWeb.AdminOrganizationListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Organizations")
     |> assign(:nav_item, :admin_organizations)
     |> assign(:organizations, Cadence.Organizations.list_organizations())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title="Organizations"
        breadcrumbs={[{"Platform Admin", ~p"/admin"}, {"Organizations", nil}]}
      >
        <:actions>
          <.button navigate={~p"/admin/organizations/new"}>Create organization</.button>
        </:actions>
      </.page_header>

      <.empty_state
        :if={@organizations == []}
        title="No organizations yet"
        description="Create one to bring a customer onto the platform."
        action_label="Create organization"
        action_navigate={~p"/admin/organizations/new"}
      />

      <.card :if={@organizations != []} padding={:none}>
        <.table id="admin-orgs-table" rows={@organizations}>
          <:col :let={org} label="Name" class="font-medium">
            <.link
              navigate={~p"/admin/organizations/#{org.organization_id}"}
              class="text-primary hover:underline"
            >
              {org.display_name}
            </.link>
          </:col>
          <:col :let={org} label="Slug" mono>{org.slug}</:col>
        </.table>
      </.card>
    </div>
    """
  end
end
