defmodule CadenceWeb.MissionLive.LinkProtocol do
  @moduledoc """
  Dedicated LiveView for link protocol configuration.

  Provides a full-page experience for the large, multi-section SDLP configuration form
  instead of showing it in a modal.
  """
  use CadenceWeb, :live_view

  alias Cadence.Links

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"link_id" => link_id}, _uri, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        {:noreply, load_link(socket, link_id)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp load_link(socket, link_id) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    case Links.get_link(org_id, mission.id, link_id) do
      {:ok, link} ->
        socket
        |> assign(:page_title, "Protocol Config: SCID #{link.scid}")
        |> assign(:link, link)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Link not found")
        |> push_navigate(to: ~p"/missions/#{mission}/links")
    end
  end

  @impl true
  def handle_info({CadenceWeb.LinkLive.ProtocolConfigComponent, {:config_saved, _config}}, socket) do
    # Flash is already set by the component, just reload the link to ensure data is fresh
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    {:ok, link} = Links.get_link(org_id, mission.id, socket.assigns.link.id)
    {:noreply, assign(socket, :link, link)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <%!-- Breadcrumb Navigation --%>
      <nav class="text-sm breadcrumbs mb-4">
        <ul>
          <li>
            <.link navigate={~p"/missions/#{@mission}"} class="link link-hover">
              {@mission.name}
            </.link>
          </li>
          <li>
            <.link navigate={~p"/missions/#{@mission}/links"} class="link link-hover">
              Links
            </.link>
          </li>
          <li>
            <.link navigate={~p"/missions/#{@mission}/links/#{@link}"} class="link link-hover">
              SCID {@link.scid}
            </.link>
          </li>
          <li class="text-base-content/70">Protocol Config</li>
        </ul>
      </nav>

      <.header>
        <div class="flex items-center gap-3">
          <.icon name="hero-cog-6-tooth" class="h-6 w-6" />
          <span>Protocol Configuration</span>
          <span class="font-mono text-base-content/60">SCID {@link.scid}</span>
        </div>
        <:actions>
          <.link navigate={~p"/missions/#{@mission}/links/#{@link}"}>
            <.button variant="ghost">
              <.icon name="hero-arrow-left" class="h-4 w-4 mr-1" /> Back to Link
            </.button>
          </.link>
        </:actions>
      </.header>

      <div class="mt-6">
        <.live_component
          module={CadenceWeb.LinkLive.ProtocolConfigComponent}
          id={"protocol-#{@link.id}"}
          link={@link}
          mission={@mission}
          current_scope={@current_scope}
        />
      </div>
    </div>
    """
  end
end
