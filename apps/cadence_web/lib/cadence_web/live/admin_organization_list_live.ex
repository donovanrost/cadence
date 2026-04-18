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
      <div class="flex items-center justify-between">
        <div>
          <.link navigate={~p"/admin"} class="text-sm text-primary hover:underline">
            &larr; Platform Admin
          </.link>
          <h1 class="text-2xl font-bold text-base-content mt-1">Organizations</h1>
        </div>
        <.link navigate={~p"/admin/organizations/new"} class="btn btn-primary btn-sm">
          Create Organization
        </.link>
      </div>

      <%= if @organizations == [] do %>
        <div class="card bg-base-200">
          <div class="card-body p-8 text-center">
            <p class="text-base-content/50">No organizations yet. Create the first one.</p>
          </div>
        </div>
      <% else %>
        <div class="space-y-3">
          <.link
            :for={org <- @organizations}
            navigate={~p"/admin/organizations/#{org.organization_id}"}
            class="card bg-base-200 hover:bg-base-300 transition-all block"
          >
            <div class="card-body p-4 flex-row items-center justify-between">
              <div>
                <p class="font-semibold">{org.display_name}</p>
                <p class="text-sm text-base-content/60 font-mono">{org.slug}</p>
              </div>
              <span class="text-primary text-sm">View &rarr;</span>
            </div>
          </.link>
        </div>
      <% end %>
    </div>
    """
  end
end
