defmodule CadenceWeb.OrganizationHomeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization

    {:ok,
     socket
     |> assign(:page_title, org.display_name)
     |> assign(:nav_item, :organization_home)
     |> assign(:organization, org)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-base-content">{@organization.display_name}</h1>
        <p class="mt-1 text-sm text-base-content/50 font-mono">{@organization.slug}</p>
      </div>
    </div>
    """
  end
end
