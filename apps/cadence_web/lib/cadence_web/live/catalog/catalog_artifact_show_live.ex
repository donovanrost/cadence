defmodule CadenceWeb.CatalogArtifactShowLive do
  @moduledoc false

  # TODO(authz): Catalog management currently permitted for any active org member.
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"artifact_id" => artifact_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Catalog Artifact")
     |> assign(:nav_item, :catalog)
     |> assign(:artifact_id, artifact_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-base-content">Artifact</h1>
    </div>
    """
  end
end
