defmodule CadenceWeb.OrganizationHomeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    mission_count = org.organization_id |> Cadence.list_missions() |> length()

    {:ok,
     socket
     |> assign(:page_title, org.display_name)
     |> assign(:nav_item, :organization_home)
     |> assign(:organization, org)
     |> assign(:mission_count, mission_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-base-content">{@organization.display_name}</h1>
        <p class="mt-1 text-sm text-base-content/50 font-mono">{@organization.slug}</p>
      </div>

      <div class="card bg-base-200 hover-glow-cyan transition-glow max-w-md">
        <div class="card-body p-6">
          <p class="hud-label">Missions</p>
          <p class="text-3xl font-bold mt-2">{@mission_count}</p>
          <.link navigate={~p"/missions"} class="btn btn-primary btn-sm mt-4 w-full">
            View Missions
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
