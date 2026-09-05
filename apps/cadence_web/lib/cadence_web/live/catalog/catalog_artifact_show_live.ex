defmodule CadenceWeb.CatalogArtifactShowLive do
  @moduledoc false

  # Authz note: Catalog management currently permitted for any active org member.
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"artifact_id" => artifact_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Catalog artifact")
     |> assign(:nav_item, :catalog)
     |> assign(:artifact, %{artifact_id: artifact_id})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="catalog-artifact-show-page-component"
        v-component="FederatedFullPageSurface"
        application_key="mission_catalog"
        surface_id="catalog_artifact_show"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{artifact_id: @artifact.artifact_id}}
          v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
