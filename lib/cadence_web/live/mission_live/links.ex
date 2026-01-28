defmodule CadenceWeb.MissionLive.Links do
  @moduledoc """
  LiveView for managing links (spacecraft by SCID) within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.Links
  alias Cadence.Links.Link

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        {:noreply, apply_action(socket, socket.assigns.live_action, params)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :index, _params) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    links = Links.list_links(org_id, mission.id)

    socket
    |> assign(:page_title, "Links")
    |> assign(:links, links)
    |> assign(:link, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    links = Links.list_links(org_id, mission.id)

    socket
    |> assign(:page_title, "New Link")
    |> assign(:links, links)
    |> assign(:link, %Link{})
  end

  @impl true
  def handle_info({CadenceWeb.LinkLive.FormComponent, {:saved, _link}}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    links = Links.list_links(org_id, mission.id)
    {:noreply, assign(socket, :links, links)}
  end

  @impl true
  def handle_event("delete", %{"id" => link_id}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    with :ok <- authorize_manage(socket),
         {:ok, link} <- Links.get_link(org_id, mission.id, link_id),
         {:ok, _} <- Links.delete_link(org_id, mission.id, link) do
      links = Links.list_links(org_id, mission.id)

      {:noreply,
       socket
       |> put_flash(:info, "Link deleted successfully")
       |> assign(:links, links)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Link not found")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete links")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete link")}
    end
  end

  defp authorize_manage(socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok -> :ok
      {:error, _} -> {:error, :unauthorized}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <.header>
        Links
        <:subtitle>Spacecraft links identified by SCID (Spacecraft ID)</:subtitle>
        <:actions>
          <.link patch={~p"/missions/#{@mission}/links/new"}>
            <.button>New Link</.button>
          </.link>
        </:actions>
      </.header>

      <.table id="links" rows={@links}>
        <:col :let={link} label="SCID">
          <span class="font-mono font-bold text-lg">{link.scid}</span>
        </:col>
        <:col :let={link} label="Name">
          <.link navigate={~p"/missions/#{@mission}/links/#{link}"} class="link link-primary">
            {link.name || "Unnamed"}
          </.link>
        </:col>
        <:col :let={link} label="Channels">
          <% channel_count = length(link.channels || []) %>
          <span class={[
            "badge",
            channel_count > 0 && "badge-primary",
            channel_count == 0 && "badge-ghost"
          ]}>
            {channel_count} channel(s)
          </span>
        </:col>
        <:col :let={link} label="Protocol">
          <%= if link.protocol_config do %>
            <span class="badge badge-sm badge-accent">Configured</span>
          <% else %>
            <span class="text-base-content/40 text-sm">Not configured</span>
          <% end %>
        </:col>
        <:action :let={link}>
          <.link navigate={~p"/missions/#{@mission}/links/#{link}"}>View</.link>
          <.link
            phx-click={JS.push("delete", value: %{id: link.id})}
            data-confirm="Are you sure you want to delete this link and all its channels?"
          >
            Delete
          </.link>
        </:action>
      </.table>

      <%= if @links == [] do %>
        <div class="text-center py-12">
          <.icon name="hero-link" class="mx-auto h-12 w-12 text-gray-400" />
          <h3 class="mt-2 text-sm font-semibold text-gray-900">No links</h3>
          <p class="mt-1 text-sm text-gray-500">
            Get started by creating a link for your spacecraft.
          </p>
          <div class="mt-6">
            <.link patch={~p"/missions/#{@mission}/links/new"}>
              <.button>
                <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" /> New Link
              </.button>
            </.link>
          </div>
        </div>
      <% end %>
    </div>

    <.modal
      :if={@live_action in [:new]}
      id="link-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/links")}
    >
      <.live_component
        module={CadenceWeb.LinkLive.FormComponent}
        id={@link.id || :new}
        title={@page_title}
        action={@live_action}
        link={@link}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/links"}
      />
    </.modal>
    """
  end
end
