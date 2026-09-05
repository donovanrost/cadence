defmodule CadenceWeb.CatalogRevisionShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"catalog_revision_id" => catalog_revision_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Catalog revision")
     |> assign(:nav_item, :catalog)
     |> assign(:revision, %{catalog_revision_id: catalog_revision_id})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="catalog-revision-show-page">
        <.vue
          id="catalog-revision-show-component"
          v-component="FederatedFullPageSurface"
          application_key="mission_catalog"
          surface_id="catalog_revision_show"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id, catalog_revision_id: @revision.catalog_revision_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
