defmodule CadenceWeb.MissionLive.Interfaces do
  @moduledoc """
  LiveView for managing interfaces within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Interfaces, Targets}

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
    interfaces = Interfaces.list_interfaces(mission)
    targets = Targets.list_targets(mission)
    interface_protocol_counts = build_protocol_counts(interfaces)
    interface_targets = build_interface_targets(interfaces)

    socket
    |> assign(:page_title, "Interfaces")
    |> assign(:interfaces, interfaces)
    |> assign(:targets, targets)
    |> assign(:interface_protocol_counts, interface_protocol_counts)
    |> assign(:interface_targets, interface_targets)
    |> assign(:interface, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    interfaces = Interfaces.list_interfaces(mission)
    targets = Targets.list_targets(mission)
    interface_protocol_counts = build_protocol_counts(interfaces)
    interface_targets = build_interface_targets(interfaces)

    socket
    |> assign(:page_title, "New Interface")
    |> assign(:interfaces, interfaces)
    |> assign(:targets, targets)
    |> assign(:interface_protocol_counts, interface_protocol_counts)
    |> assign(:interface_targets, interface_targets)
    |> assign(:interface, %Interfaces.InterfaceSchema{})
  end

  defp apply_action(socket, :edit, %{"interface_id" => interface_id}) do
    mission = socket.assigns.mission
    interface = Interfaces.get_interface!(interface_id)
    interfaces = Interfaces.list_interfaces(mission)
    targets = Targets.list_targets(mission)
    interface_protocol_counts = build_protocol_counts(interfaces)
    interface_targets = build_interface_targets(interfaces)

    if interface.mission_id == mission.id do
      socket
      |> assign(:page_title, "Edit Interface")
      |> assign(:interfaces, interfaces)
      |> assign(:targets, targets)
      |> assign(:interface_protocol_counts, interface_protocol_counts)
      |> assign(:interface_targets, interface_targets)
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
    interface_protocol_counts = build_protocol_counts(interfaces)
    interface_targets = build_interface_targets(interfaces)

    {:noreply,
     socket
     |> assign(:interfaces, interfaces)
     |> assign(:interface_protocol_counts, interface_protocol_counts)
     |> assign(:interface_targets, interface_targets)}
  end

  @impl true
  def handle_event("delete", %{"id" => interface_id}, socket) do
    interface = Interfaces.get_interface!(interface_id)
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    if interface.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          case Interfaces.delete_interface(interface) do
            {:ok, _} ->
              interfaces = Interfaces.list_interfaces(mission)
              interface_protocol_counts = build_protocol_counts(interfaces)
              interface_targets = build_interface_targets(interfaces)

              {:noreply,
               socket
               |> put_flash(:info, "Interface deleted successfully")
               |> assign(:interfaces, interfaces)
               |> assign(:interface_protocol_counts, interface_protocol_counts)
               |> assign(:interface_targets, interface_targets)}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to delete interface")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to delete interfaces")}
      end
    else
      {:noreply, put_flash(socket, :error, "Interface not found in this mission")}
    end
  end

  defp build_protocol_counts(interfaces) do
    interfaces
    |> Enum.map(fn interface ->
      protocol_count =
        interface.id
        |> Interfaces.list_protocols()
        |> length()

      {interface.id, protocol_count}
    end)
    |> Map.new()
  end

  defp build_interface_targets(interfaces) do
    interfaces
    |> Enum.map(fn interface ->
      targets = Interfaces.list_targets_for_interface(interface, preload: false)
      {interface.id, targets}
    end)
    |> Map.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
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
      <:col :let={interface} label="Name"><%= interface.name %></:col>
      <:col :let={interface} label="Connection Type">
        <%= String.replace(interface.connection_type || "none", "_", " ") |> String.capitalize() %>
      </:col>
      <:col :let={interface} label="Targets">
        <% targets = Map.get(@interface_targets, interface.id, []) %>
        <%= if Enum.empty?(targets) do %>
          <span class="text-gray-400 italic text-sm">No targets</span>
        <% else %>
          <div class="flex flex-wrap gap-1">
            <%= for target <- targets do %>
              <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-700/10">
                <%= target.identifier %>
              </span>
            <% end %>
          </div>
        <% end %>
      </:col>
      <:col :let={interface} label="Protocols">
        <%= case Map.get(@interface_protocol_counts, interface.id, 0) do %>
          <% 0 -> %>
            <span class="text-gray-500">No protocols</span>
          <% 1 -> %>
            <.link navigate={~p"/missions/#{@mission}/interfaces/#{interface}/protocols"} class="text-blue-600 hover:underline">
              1 protocol
            </.link>
          <% count -> %>
            <.link navigate={~p"/missions/#{@mission}/interfaces/#{interface}/protocols"} class="text-blue-600 hover:underline">
              <%= count %> protocols
            </.link>
        <% end %>
      </:col>
      <:col :let={interface} label="Status">
        <span class={[
          "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset",
          interface.status == "connected" && "bg-green-50 text-green-700 ring-green-600/20",
          interface.status == "disconnected" && "bg-gray-50 text-gray-600 ring-gray-500/10",
          interface.status == "connecting" && "bg-yellow-50 text-yellow-700 ring-yellow-600/20",
          interface.status == "error" && "bg-red-50 text-red-700 ring-red-600/10"
        ]}>
          <%= interface.status %>
        </span>
      </:col>
      <:col :let={interface} label="Auto Reconnect">
        <span class={[
          "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset",
          interface.auto_reconnect && "bg-green-50 text-green-700 ring-green-600/20",
          !interface.auto_reconnect && "bg-gray-50 text-gray-600 ring-gray-500/10"
        ]}>
          <%= if interface.auto_reconnect, do: "Enabled", else: "Disabled" %>
        </span>
      </:col>
      <:action :let={interface}>
        <.link navigate={~p"/missions/#{@mission}/interfaces/#{interface}/protocols"}>
          Protocols
        </.link>
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
              <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" />
              New Interface
            </.button>
          </.link>
        </div>
      </div>
    <% end %>

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
