defmodule CadenceWeb.AdminHomeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Platform Admin")
     |> assign(:nav_item, :admin_dashboard)
     |> assign(:org_count, Cadence.Organizations.count_organizations())
     |> assign(:user_count, Cadence.count_users())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <.page_header
        title="Platform Administration"
        subtitle="Manage organizations, users, and system settings"
      />

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <.card title="Organizations">
          <p class="mt-2 font-mono text-3xl font-bold">{@org_count}</p>
          <.button navigate={~p"/admin/organizations"} class="mt-4 w-full">
            Manage Organizations
          </.button>
        </.card>

        <.card title="Users">
          <p class="mt-2 font-mono text-3xl font-bold">{@user_count}</p>
          <.button variant={:secondary} class="mt-4 w-full" disabled>
            Manage Users <span class="text-xs">(Coming Soon)</span>
          </.button>
        </.card>

        <.card title="Runtime">
          <p class="mt-2 text-sm text-base-content/70">
            Inspect process-local runtime diagnostics and dashboard invalidation decisions.
          </p>
          <.button navigate={~p"/admin/runtime"} class="mt-4 w-full">
            View Runtime
          </.button>
        </.card>
      </div>

      <div>
        <h2 class="text-lg font-bold mb-4">Quick Actions</h2>
        <.link navigate={~p"/admin/organizations/new"} class="block">
          <.card hover_glow>
            <div class="flex items-center gap-4">
              <div>
                <h3 class="font-semibold">Create New Organization</h3>
                <p class="text-sm text-base-content/60">Add a new organization to the system</p>
              </div>
            </div>
          </.card>
        </.link>
      </div>
    </div>
    """
  end
end
