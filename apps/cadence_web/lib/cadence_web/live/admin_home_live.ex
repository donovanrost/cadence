defmodule CadenceWeb.AdminHomeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Platform Admin")
     |> assign(:nav_item, :admin_dashboard)
     |> assign(:org_count, Cadence.count_organizations())
     |> assign(:user_count, Cadence.count_users())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div>
        <h1 class="text-2xl font-bold text-base-content">Platform Administration</h1>
        <p class="mt-1 text-sm text-base-content/50">
          Manage organizations, users, and system settings
        </p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="card bg-base-200 hover-glow-cyan transition-glow">
          <div class="card-body p-6">
            <p class="hud-label">Organizations</p>
            <p class="text-3xl font-bold mt-2">{@org_count}</p>
            <.link navigate={~p"/admin/organizations"} class="btn btn-primary btn-sm mt-4 w-full">
              Manage Organizations
            </.link>
          </div>
        </div>

        <div class="card bg-base-200 hover-glow-purple transition-glow">
          <div class="card-body p-6">
            <p class="hud-label">Users</p>
            <p class="text-3xl font-bold mt-2">{@user_count}</p>
            <button class="btn btn-secondary btn-sm mt-4 w-full" disabled>
              Manage Users <span class="text-xs">(Coming Soon)</span>
            </button>
          </div>
        </div>
      </div>

      <div>
        <h2 class="text-lg font-bold mb-4">Quick Actions</h2>
        <.link
          navigate={~p"/admin/organizations/new"}
          class="card bg-base-200 p-6 hover:bg-base-300 transition-all hover-glow-cyan"
        >
          <div class="flex items-center gap-4">
            <div>
              <h3 class="font-semibold">Create New Organization</h3>
              <p class="text-sm text-base-content/60">Add a new organization to the system</p>
            </div>
          </div>
        </.link>
      </div>
    </div>
    """
  end
end
