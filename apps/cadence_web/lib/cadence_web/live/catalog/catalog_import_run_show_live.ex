defmodule CadenceWeb.CatalogImportRunShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"import_run_id" => import_run_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Import run")
     |> assign(:nav_item, :catalog)
     |> assign(:run, %{import_run_id: import_run_id})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="catalog-import-run-show-page">
        <.vue
          id="catalog-import-run-show-component"
          v-component="FederatedFullPageSurface"
          application_key="mission_catalog"
          surface_id="catalog_import_run_show"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{import_run_id: @run.import_run_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
