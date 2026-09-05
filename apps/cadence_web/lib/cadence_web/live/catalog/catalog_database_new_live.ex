defmodule CadenceWeb.CatalogDatabaseNewLive do
  @moduledoc false

  # Authz note: any signed-in mission member can create a catalog database.
  # Tighten once platform-wide authorization is defined.
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New catalog database")
     |> assign(:nav_item, :catalog)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="catalog-database-new-component"
        v-component="FederatedFullPageSurface"
        application_key="mission_catalog"
        surface_id="catalog_database_new"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{}}
          v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
