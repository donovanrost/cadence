defmodule CadenceWeb.AdminHomeLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="admin-home-page">
        <.vue
          id="admin-home-component"
          v-component="FederatedFullPageSurface"
          application_key="organization_admin"
          surface_id="admin_home"
          host_scope="admin"
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
