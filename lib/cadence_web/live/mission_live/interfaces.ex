defmodule CadenceWeb.MissionLive.Interfaces do
  @moduledoc """
  LiveView for managing interfaces within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Interfaces, Targets}
  alias Cadence.Interfaces.Events.InterfaceConnectionEvent

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :interface_connection_status, %{})}
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

    # Subscribe to real-time interface status updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:events")
    end

    interfaces = Interfaces.list_interfaces(mission)
    targets = Targets.list_targets(mission)
    interface_targets = build_interface_targets(interfaces)

    # Build a map of interface_id -> connection status for runtime state
    interface_connection_status = build_connection_status(interfaces, mission.id)

    socket
    |> assign(:page_title, "Interfaces")
    |> assign(:interfaces, interfaces)
    |> assign(:targets, targets)
    |> assign(:interface_targets, interface_targets)
    |> assign(:interface_connection_status, interface_connection_status)
    |> assign(:interface, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    interfaces = Interfaces.list_interfaces(mission)
    targets = Targets.list_targets(mission)
    interface_targets = build_interface_targets(interfaces)

    interface_connection_status = build_connection_status(interfaces, mission.id)

    socket
    |> assign(:page_title, "New Interface")
    |> assign(:interfaces, interfaces)
    |> assign(:targets, targets)
    |> assign(:interface_targets, interface_targets)
    |> assign(:interface_connection_status, interface_connection_status)
    |> assign(:interface, %Interfaces.InterfaceSchema{})
  end

  defp apply_action(socket, :edit, %{"interface_id" => interface_id}) do
    mission = socket.assigns.mission
    interface = Interfaces.get_interface!(interface_id)
    interfaces = Interfaces.list_interfaces(mission)
    targets = Targets.list_targets(mission)
    interface_targets = build_interface_targets(interfaces)

    if interface.mission_id == mission.id do
      interface_connection_status = build_connection_status(interfaces, mission.id)

      socket
      |> assign(:page_title, "Edit Interface")
      |> assign(:interfaces, interfaces)
      |> assign(:targets, targets)
      |> assign(:interface_targets, interface_targets)
      |> assign(:interface_connection_status, interface_connection_status)
      |> assign(:interface, interface)
    else
      socket
      |> put_flash(:error, "Interface not found in this mission")
      |> push_patch(to: ~p"/missions/#{mission}/interfaces")
    end
  end

  @impl true
  def handle_info({CadenceWeb.InterfaceLive.FormComponent, {:saved, _interface}}, socket) do
    interfaces = Interfaces.list_interfaces(socket.assigns.mission)
    interface_targets = build_interface_targets(interfaces)

    interface_connection_status =
      build_connection_status(interfaces, socket.assigns.mission.id)

    {:noreply,
     socket
     |> assign(:interfaces, interfaces)
     |> assign(:interface_targets, interface_targets)
     |> assign(:interface_connection_status, interface_connection_status)}
  end

  # Real-time interface connection status updates via PubSub
  def handle_info({:interface_connection_event, %InterfaceConnectionEvent{} = event}, socket) do
    # Update the connection status map with the new state
    interface_connection_status =
      Map.put(
        socket.assigns[:interface_connection_status] || %{},
        event.interface_id,
        %{state: event.new_state, client_count: event.client_count}
      )

    {:noreply, assign(socket, :interface_connection_status, interface_connection_status)}
  end

  # Catch-all for other PubSub events we don't handle
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete", %{"id" => interface_id}, socket) do
    with {:ok, interface} <- fetch_interface(socket, interface_id),
         :ok <- authorize_manage_interfaces(socket),
         {:ok, _} <- Interfaces.delete_interface(interface) do
      interfaces = list_interfaces(socket)
      interface_targets = build_interface_targets(interfaces)

      {:noreply,
       socket
       |> put_flash(:info, "Interface deleted successfully")
       |> assign(:interfaces, interfaces)
       |> assign(:interface_targets, interface_targets)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Interface not found in this mission")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete interfaces")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete interface")}
    end
  end

  defp build_interface_targets(interfaces) do
    interfaces
    |> Enum.map(fn interface ->
      targets = Interfaces.list_targets_for_interface(interface, preload: false)
      {interface.id, targets}
    end)
    |> Map.new()
  end

  defp fetch_interface(socket, interface_id) do
    mission = socket.assigns.mission

    case Interfaces.get_interface(interface_id) do
      nil ->
        {:error, :not_found}

      interface ->
        if interface.mission_id == mission.id do
          {:ok, interface}
        else
          {:error, :not_found}
        end
    end
  end

  defp authorize_manage_interfaces(socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok -> :ok
      {:error, _} -> {:error, :unauthorized}
    end
  end

  defp list_interfaces(socket) do
    Interfaces.list_interfaces(socket.assigns.mission)
  end

  # Build initial connection status - starts as disconnected, updated via PubSub
  defp build_connection_status(interfaces, _mission_id) do
    # Initial state is disconnected for all interfaces
    # Real-time updates come via PubSub :interface_connection_event
    Enum.reduce(interfaces, %{}, fn interface, acc ->
      Map.put(acc, interface.id, %{state: :unknown, client_count: 0})
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <.header>
        Interfaces
        <:subtitle>Manage communication interfaces for this mission</:subtitle>
        <:actions>
          <.link patch={~p"/missions/#{@mission}/interfaces/new"}>
            <.button>New Interface</.button>
          </.link>
        </:actions>
      </.header>

      <.table id="interfaces" rows={@interfaces}>
        <:col :let={interface} label="Name">
          <.link navigate={~p"/missions/#{@mission}/interfaces/#{interface}"}>
            {interface.name}
          </.link>
        </:col>
        <:col :let={interface} label="Connection Type">
          {String.replace(interface.connection_type || "none", "_", " ") |> String.capitalize()}
        </:col>
        <:col :let={interface} label="Targets">
          <% targets = Map.get(@interface_targets, interface.id, []) %>
          <%= if Enum.empty?(targets) do %>
            <span class="text-gray-400 italic text-sm">No targets</span>
          <% else %>
            <div class="flex flex-wrap gap-1">
              <%= for target <- targets do %>
                <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-700/10">
                  {target.identifier}
                </span>
              <% end %>
            </div>
          <% end %>
        </:col>
        <:col :let={interface} label="Status">
          <.status_badge status={interface.status} />
        </:col>
        <:col :let={interface} label="Connection">
          <% conn_status =
            Map.get(@interface_connection_status, interface.id, %{
              state: :disconnected,
              client_count: 0
            }) %>
          <%= case conn_status.state do %>
            <% :connected -> %>
              <span class="inline-flex items-center rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-800">
                <span class="mr-1.5 h-2 w-2 rounded-full bg-green-500 animate-pulse"></span>
                Connected ({conn_status.client_count})
              </span>
            <% :disconnected -> %>
              <span class="inline-flex items-center rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-800">
                <span class="mr-1.5 h-2 w-2 rounded-full bg-gray-400"></span> Disconnected
              </span>
            <% _ -> %>
              <span class="inline-flex items-center rounded-full bg-yellow-100 px-2.5 py-0.5 text-xs font-medium text-yellow-800">
                Unknown
              </span>
          <% end %>
        </:col>
        <:col :let={interface} label="Auto Reconnect">
          <.status_badge
            status={interface.auto_reconnect}
            true_label="Enabled"
            false_label="Disabled"
          />
        </:col>
        <:action :let={interface}>
          <.link navigate={~p"/missions/#{@mission}/interfaces/#{interface}"}>Details</.link>
          <.link patch={~p"/missions/#{@mission}/interfaces/#{interface}/edit"}>Edit</.link>
          <.link
            phx-click={JS.push("delete", value: %{id: interface.id})}
            data-confirm="Are you sure you want to delete this interface?"
          >
            Delete
          </.link>
        </:action>
      </.table>

      <%= if Enum.empty?(@interfaces) do %>
        <div class="text-center py-12">
          <.icon name="hero-signal" class="mx-auto h-12 w-12 text-gray-400" />
          <h3 class="mt-2 text-sm font-semibold text-gray-900">No interfaces</h3>
          <p class="mt-1 text-sm text-gray-500">Get started by creating a new interface.</p>
          <div class="mt-6">
            <.link patch={~p"/missions/#{@mission}/interfaces/new"}>
              <.button>
                <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" /> New Interface
              </.button>
            </.link>
          </div>
        </div>
      <% end %>
    </div>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="interface-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/interfaces")}
    >
      <.live_component
        module={CadenceWeb.InterfaceLive.FormComponent}
        id={@interface.id || :new}
        title={@page_title}
        action={if @live_action == :new, do: :new_interface, else: :edit}
        interface={@interface}
        mission={@mission}
        targets={@targets}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/interfaces"}
      />
    </.modal>
    """
  end
end
