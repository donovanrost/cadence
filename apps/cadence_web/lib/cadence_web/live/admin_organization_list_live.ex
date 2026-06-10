defmodule CadenceWeb.AdminOrganizationListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Organizations")
     |> assign(:nav_item, :admin_organizations)
     |> assign(:organizations, Cadence.list_organizations())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header title="Organizations" back_label="Platform Admin" back_navigate={~p"/admin"}>
        <:actions>
          <.button navigate={~p"/admin/organizations/new"}>
            Create Organization
          </.button>
        </:actions>
      </.page_header>

      <%= if @organizations == [] do %>
        <.empty_state title="No organizations yet." description="Create the first one." />
      <% else %>
        <div class="space-y-3">
          <.link
            :for={org <- @organizations}
            navigate={~p"/admin/organizations/#{org.organization_id}"}
            class="block"
          >
            <.card padding={:none} class="hover:bg-base-300 transition-all">
              <div class="flex items-center justify-between p-4">
                <div>
                  <p class="font-semibold">{org.display_name}</p>
                  <p class="text-sm text-base-content/60 font-mono">{org.slug}</p>
                </div>
                <span class="text-primary text-sm">View &rarr;</span>
              </div>
            </.card>
          </.link>
        </div>
      <% end %>
    </div>
    """
  end
end
