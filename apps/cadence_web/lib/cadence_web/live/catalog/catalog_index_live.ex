defmodule CadenceWeb.CatalogIndexLive do
  @moduledoc false

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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="catalog-index-component"
        v-component="FederatedFullPageSurface"
        application_key="mission_catalog"
        surface_id="catalog_index"
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
