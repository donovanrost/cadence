defmodule CadenceWeb.CatalogCommandSnapshotShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"snapshot_id" => snapshot_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Command Snapshot")
     |> assign(:nav_item, :catalog)
     |> assign(:snapshot_id, snapshot_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-base-content">Command Snapshot</h1>
    </div>
    """
  end
end
