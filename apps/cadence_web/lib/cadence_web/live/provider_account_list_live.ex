defmodule CadenceWeb.ProviderAccountListLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="provider-account-list-page-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="provider_accounts"
        host_scope="organization"
        organization_id={@current_scope.organization.organization_id}
        query_params={%{organization_id: @current_scope.organization.organization_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
