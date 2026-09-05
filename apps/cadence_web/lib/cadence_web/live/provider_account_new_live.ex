defmodule CadenceWeb.ProviderAccountNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="provider-account-new-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="provider_account_new"
        host_scope="organization"
        organization_id={@current_scope.organization.organization_id}
        query_params={%{}}
        v-ssr={false}
        class="max-w-3xl space-y-6"
      />
    </Layouts.app>
    """
  end
end
