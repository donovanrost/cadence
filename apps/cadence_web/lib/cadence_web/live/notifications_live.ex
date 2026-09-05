defmodule CadenceWeb.NotificationsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="notifications-page-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="notifications"
        host_scope="user"
        user_id={@current_scope.user.user_id}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
