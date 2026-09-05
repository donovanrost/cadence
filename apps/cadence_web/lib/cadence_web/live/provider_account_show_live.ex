defmodule CadenceWeb.ProviderAccountShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"provider_account_id" => provider_account_id}, _session, socket) do
    {:ok, assign(socket, :provider_account, %{provider_account_id: provider_account_id})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="provider-account-show-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="provider_account_show"
        host_scope="organization"
        organization_id={@current_scope.organization.organization_id}
        query_params={%{organization_id: @current_scope.organization.organization_id, provider_account_id: @provider_account.provider_account_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
