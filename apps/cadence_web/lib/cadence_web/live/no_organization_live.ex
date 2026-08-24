defmodule CadenceWeb.NoOrganizationLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias CadenceWeb.ScopeLoader

  @impl true
  def mount(_params, %{"presentation" => presentation} = session, socket) do
    {:ok,
     socket
     |> ScopeLoader.assign_scope_from_session(session)
     |> assign(:presentation, presentation), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="no-organization-page-component"
        v-component="NoOrganizationPage"
        presentation={@presentation}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
