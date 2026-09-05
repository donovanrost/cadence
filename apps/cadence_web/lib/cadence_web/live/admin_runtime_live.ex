defmodule CadenceWeb.AdminRuntimeLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="admin-runtime-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="admin_runtime"
        host_scope="admin"
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
