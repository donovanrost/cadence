defmodule CadenceWeb.CatalogDatabaseShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"catalog_database_id" => catalog_database_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Catalog database")
     |> assign(:nav_item, :catalog)
     |> assign(:database, %{catalog_database_id: catalog_database_id})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="catalog-database-show-page">
        <.vue
          id="catalog-database-show-component"
          v-component="FederatedFullPageSurface"
          application_key="mission_catalog"
          surface_id="catalog_database_show"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id, catalog_database_id: @database.catalog_database_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
