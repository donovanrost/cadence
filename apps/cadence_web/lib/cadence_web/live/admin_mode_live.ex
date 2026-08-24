defmodule CadenceWeb.AdminModeLive do
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
        id="admin-mode-page-component"
        v-component="AdminModePage"
        presentation={@presentation}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
