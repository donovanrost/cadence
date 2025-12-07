defmodule CadenceWeb.AdminLive.Index do
  use CadenceWeb, :live_view

  alias Cadence.{Accounts, Organizations}

  @impl true
  def mount(_params, _session, socket) do
    # Get overview statistics
    organizations_count = Organizations.list_organizations() |> length()
    users_count = Accounts.list_all_users() |> length()

    socket =
      socket
      |> assign(:organizations_count, organizations_count)
      |> assign(:users_count, users_count)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto">
      <.header>
        System Administration
        <:subtitle>
          Manage organizations, users, and system settings
        </:subtitle>
      </.header>
      
    <!-- Stats Overview -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mt-8">
        <div class="card bg-base-200 p-6 hover-glow-cyan transition-glow">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-base-content/60">Organizations</p>
              <p class="text-3xl font-bold mt-2">{@organizations_count}</p>
            </div>
            <.icon name="hero-building-office" class="h-12 w-12 text-primary" />
          </div>
          <.link navigate={~p"/admin/organizations"} class="btn btn-primary btn-sm mt-4 w-full">
            Manage Organizations
          </.link>
        </div>

        <div class="card bg-base-200 p-6 hover-glow-purple transition-glow">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-base-content/60">Total Users</p>
              <p class="text-3xl font-bold mt-2">{@users_count}</p>
            </div>
            <.icon name="hero-users" class="h-12 w-12 text-secondary" />
          </div>
          <button class="btn btn-secondary btn-sm mt-4 w-full" disabled>
            Manage Users <span class="text-xs">(Coming Soon)</span>
          </button>
        </div>

        <div class="card bg-base-200 p-6 hover-glow-pink transition-glow">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-base-content/60">Invitations</p>
              <p class="text-3xl font-bold mt-2">0</p>
            </div>
            <.icon name="hero-envelope" class="h-12 w-12 text-accent" />
          </div>
          <button class="btn btn-accent btn-sm mt-4 w-full" disabled>
            Manage Invitations <span class="text-xs">(Coming Soon)</span>
          </button>
        </div>
      </div>
      
    <!-- Quick Actions -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">Quick Actions</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.link
            navigate={~p"/admin/organizations/new"}
            class="card bg-base-200 p-6 hover:bg-base-300 transition-all hover-glow-cyan"
          >
            <div class="flex items-center gap-4">
              <div class="rounded-full bg-primary/10 p-3">
                <.icon name="hero-plus-circle" class="h-6 w-6 text-primary" />
              </div>
              <div>
                <h3 class="font-semibold">Create New Organization</h3>
                <p class="text-sm text-base-content/60">Add a new organization to the system</p>
              </div>
            </div>
          </.link>

          <.link
            navigate={~p"/admin/design-system"}
            class="card bg-base-200 p-6 hover:bg-base-300 transition-all hover-glow-purple"
          >
            <div class="flex items-center gap-4">
              <div class="rounded-full bg-secondary/10 p-3">
                <.icon name="hero-paint-brush" class="h-6 w-6 text-secondary" />
              </div>
              <div>
                <h3 class="font-semibold">View Design System</h3>
                <p class="text-sm text-base-content/60">
                  Explore the vaporwave/Tokyo Night design language
                </p>
              </div>
            </div>
          </.link>
        </div>
      </div>
      
    <!-- System Info -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">System Information</h2>
        <div class="card bg-base-200 p-6">
          <.list>
            <:item title="Application">Cadence</:item>
            <:item title="Version">0.1.0</:item>
            <:item title="Phoenix Version">{Application.spec(:phoenix, :vsn)}</:item>
            <:item title="LiveView Version">{Application.spec(:phoenix_live_view, :vsn)}</:item>
            <:item title="Elixir Version">{System.version()}</:item>
          </.list>
        </div>
      </div>
    </div>
    """
  end
end
