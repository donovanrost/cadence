defmodule CadenceWeb.CommsOverviewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.CommsOverviewPresenter

  @impl true
  def mount(_params, _session, socket) do
    presentation =
      CommsOverviewPresenter.build(
        socket.assigns.current_scope,
        socket.assigns.current_mission
      )

    {:ok,
     socket
     |> assign(:page_title, "Comms")
     |> assign(:nav_item, :comms_overview)
     |> assign(:presentation, presentation)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-overview-component"
        v-component="CommsOverviewPage"
        presentation={@presentation}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  @doc false
  def presentation_attrs(attrs), do: CommsOverviewPresenter.presentation_attrs(attrs)
end
