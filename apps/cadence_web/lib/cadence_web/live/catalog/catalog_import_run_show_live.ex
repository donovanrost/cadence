defmodule CadenceWeb.CatalogImportRunShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"import_run_id" => import_run_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Catalog Import Run")
     |> assign(:nav_item, :catalog)
     |> assign(:import_run_id, import_run_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-base-content">Import Run</h1>
    </div>
    """
  end
end
