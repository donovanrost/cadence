defmodule CadenceWeb.LiveVuePocLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "LiveVue PoC")
     |> assign(:live_vue_message, "Vue is mounted inside a Cadence LiveView")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="livevue-poc-page" class="space-y-6">
      <.page_header
        title="LiveVue PoC"
        subtitle="A Vue component mounted inside the authenticated Cadence LiveView shell."
      />

      <.vue
        id="livevue-poc-component"
        v-component="LiveVueDemo"
        message={@live_vue_message}
        v-ssr={false}
      />
    </div>
    """
  end
end
