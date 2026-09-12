defmodule CadenceWeb.UserSessionLive do
  @moduledoc "Session transport for the frontend-owned sign-in screen."
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, %{
       version: 1,
       csrf_token: Plug.CSRFProtection.get_csrf_token_for(~p"/sign-in")
     })
     |> assign(:page_title, "Sign in")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_scope]}>
      <.vue
        id="user-session-component"
        v-component="UserSession"
        page={@page}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end
end
