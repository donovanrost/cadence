defmodule CadenceWeb.OrganizationInvitationLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias CadenceWeb.ScopeLoader

  @impl true
  def mount(_params, %{"page" => page} = session, socket) do
    {:ok,
     socket
     |> ScopeLoader.assign_scope_from_session(session)
     |> assign(:page, page), layout: {CadenceWeb.Layouts, :auth}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="organization-invitation-page-component"
        v-component="OrganizationInvitationPage"
        page={@page}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
