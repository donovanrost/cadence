defmodule CadenceWeb.CatalogIndexLive do
  @moduledoc false

  # TODO(authz): Catalog upload currently permitted for any active org member.
  # Tighten once finer-grained catalog capability is defined.
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Catalog")
     |> assign(:nav_item, :catalog)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-base-content">Catalog</h1>
    </div>
    """
  end
end
