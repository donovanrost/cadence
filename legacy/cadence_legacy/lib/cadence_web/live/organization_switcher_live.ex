defmodule CadenceWeb.OrganizationSwitcherLive do
  use CadenceWeb, :live_view

  alias Cadence.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.scope

    {:ok,
     socket
     |> assign(:current_organization, scope.current_organization)
     |> assign(:all_organizations, scope.all_organizations)}
  end

  @impl true
  def handle_event("switch_organization", %{"organization_id" => org_id}, socket) do
    case Scope.switch_organization(socket.assigns.scope, org_id) do
      {:ok, new_scope} ->
        # Store the new current organization in the session
        {:noreply,
         socket
         |> put_flash(:info, "Switched to #{new_scope.current_organization.name}")
         |> push_event("update_session", %{current_organization_id: org_id})
         |> assign(:scope, new_scope)
         |> assign(:current_organization, new_scope.current_organization)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Unauthorized to access that organization")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative inline-block text-left">
      <div>
        <button
          type="button"
          phx-click="toggle_dropdown"
          class="inline-flex w-full justify-center gap-x-1.5 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          <%= if @current_organization do %>
            {@current_organization.name}
          <% else %>
            Select Organization
          <% end %>
          <svg class="-mr-1 h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
            <path
              fill-rule="evenodd"
              d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
              clip-rule="evenodd"
            />
          </svg>
        </button>
      </div>

      <div
        id="org-dropdown"
        class="absolute right-0 z-10 mt-2 w-56 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none hidden"
        role="menu"
      >
        <div class="py-1" role="none">
          <%= for org <- @all_organizations do %>
            <button
              type="button"
              phx-click="switch_organization"
              phx-value-organization_id={org.id}
              class={[
                "block w-full text-left px-4 py-2 text-sm",
                (org.id == @current_organization.id &&
                   "bg-gray-100 text-gray-900 font-semibold") || "text-gray-700 hover:bg-gray-50"
              ]}
              role="menuitem"
            >
              {org.name}
              <%= if org.id == @current_organization.id do %>
                <span class="float-right">✓</span>
              <% end %>
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
