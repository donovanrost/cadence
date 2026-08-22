defmodule CadenceWeb.MissionLive.Transports do
  @moduledoc """
  LiveView for managing transport interfaces within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.Transports
  alias Cadence.Transports.Interface

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

    interfaces = Transports.list_interfaces(org_id, mission.id)

    socket
    |> assign(:page_title, "Transports")
    |> assign(:interfaces, interfaces)
    |> assign(:interface, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    interfaces = Transports.list_interfaces(org_id, mission.id)

    socket
    |> assign(:page_title, "New Transport")
    |> assign(:interfaces, interfaces)
    |> assign(:interface, %Interface{})
  end

  defp apply_action(socket, :edit, %{"transport_id" => transport_id}) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    case Transports.get_interface(org_id, mission.id, transport_id) do
      {:ok, interface} ->
        interfaces = Transports.list_interfaces(org_id, mission.id)

        socket
        |> assign(:page_title, "Edit Transport")
        |> assign(:interfaces, interfaces)
        |> assign(:interface, interface)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Transport not found")
        |> push_patch(to: ~p"/missions/#{mission}/transports")
    end
  end

  @impl true
  def handle_info({CadenceWeb.TransportLive.FormComponent, {:saved, _interface}}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    interfaces = Transports.list_interfaces(org_id, mission.id)
    {:noreply, assign(socket, :interfaces, interfaces)}
  end

  @impl true
  def handle_event("delete", %{"id" => transport_id}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    with :ok <- authorize_manage(socket),
         {:ok, transport} <- Transports.get_interface(org_id, mission.id, transport_id),
         {:ok, _} <- Transports.delete_interface(org_id, mission.id, transport) do
      interfaces = Transports.list_interfaces(org_id, mission.id)

      {:noreply,
       socket
       |> put_flash(:info, "Transport deleted successfully")
       |> assign(:interfaces, interfaces)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Transport not found")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete transports")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete transport")}
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
        Transports
        <:subtitle>Configure transport interfaces for data ingress and egress</:subtitle>
        <:actions>
          <.link patch={~p"/missions/#{@mission}/transports/new"}>
            <.button>New Transport</.button>
          </.link>
        </:actions>
      </.header>

      <.table id="transports" rows={@interfaces}>
        <:col :let={interface} label="Name">
          <.link
            navigate={~p"/missions/#{@mission}/transports/#{interface}"}
            class="link link-primary"
          >
            {interface.name}
          </.link>
        </:col>
        <:col :let={interface} label="Type">
          <.transport_type_badge type={interface.type} />
        </:col>
        <:col :let={interface} label="Directions">
          <div class="flex flex-wrap gap-1">
            <%= for dir <- interface.allowed_directions || [:both] do %>
              <.direction_badge direction={dir} />
            <% end %>
          </div>
        </:col>
        <:col :let={interface} label="Status">
          <.enabled_indicator enabled={interface.enabled} />
        </:col>
        <:col :let={interface} label="Tags">
          <%= if interface.tags && interface.tags != [] do %>
            <div class="flex flex-wrap gap-1">
              <%= for tag <- interface.tags do %>
                <span class="badge badge-sm badge-ghost">{tag}</span>
              <% end %>
            </div>
          <% else %>
            <span class="text-base-content/40 text-sm">-</span>
          <% end %>
        </:col>
        <:action :let={interface}>
          <.link navigate={~p"/missions/#{@mission}/transports/#{interface}"}>View</.link>
          <.link patch={~p"/missions/#{@mission}/transports/#{interface}/edit"}>Edit</.link>
          <.link
            phx-click={JS.push("delete", value: %{id: interface.id})}
            data-confirm="Are you sure you want to delete this transport?"
          >
            Delete
          </.link>
        </:action>
      </.table>

      <%= if @interfaces == [] do %>
        <div class="text-center py-12">
          <.icon name="hero-arrow-path-rounded-square" class="mx-auto h-12 w-12 text-gray-400" />
          <h3 class="mt-2 text-sm font-semibold text-gray-900">No transports</h3>
          <p class="mt-1 text-sm text-gray-500">
            Get started by creating a new transport interface.
          </p>
          <div class="mt-6">
            <.link patch={~p"/missions/#{@mission}/transports/new"}>
              <.button>
                <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" /> New Transport
              </.button>
            </.link>
          </div>
        </div>
      <% end %>
    </div>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="transport-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/transports")}
    >
      <.live_component
        module={CadenceWeb.TransportLive.FormComponent}
        id={@interface.id || :new}
        title={@page_title}
        action={@live_action}
        interface={@interface}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/transports"}
      />
    </.modal>
    """
  end
end
