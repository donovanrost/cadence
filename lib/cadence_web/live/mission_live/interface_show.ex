defmodule CadenceWeb.MissionLive.InterfaceShow do
  @moduledoc """
  LiveView for showing a single interface and configuring VCID mappings.
  """

  use CadenceWeb, :live_view

  alias Cadence.{Interfaces, Missions}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(
         socket,
         action,
         %{"id" => mission_id, "interface_id" => interface_id} = params
       ) do
    scope = socket.assigns.current_scope

    with {:ok, mission, interface} <- fetch_mission_interface(mission_id, interface_id),
         :ok <- authorize_manage_interfaces(scope, mission) do
      target_interfaces = Interfaces.list_target_interfaces_for_interface(interface)
      targets = Enum.map(target_interfaces, & &1.target)
      vcids = Interfaces.list_vcids_for_interface(interface)

      target_interface =
        case action do
          :edit_scid -> fetch_target_interface!(params["target_interface_id"], interface)
          _ -> nil
        end

      {:noreply,
       socket
       |> assign(:page_title, "Interface: #{interface.name}")
       |> assign(:mission, mission)
       |> assign(:interface, interface)
       |> assign(:targets, targets)
       |> assign(:target_interfaces, target_interfaces)
       |> assign(:vcids, vcids)
       |> assign(:target_interface, target_interface)}
    else
      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to manage interfaces")
         |> push_navigate(to: ~p"/missions/#{mission_id}/interfaces")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Interface not found in this mission")
         |> push_navigate(to: ~p"/missions/#{mission_id}/interfaces")}
    end
  end

  @impl true
  def handle_info({CadenceWeb.InterfaceTargetScidLive.FormComponent, {:saved, _mapping}}, socket) do
    target_interfaces = Interfaces.list_target_interfaces_for_interface(socket.assigns.interface)
    targets = Enum.map(target_interfaces, & &1.target)

    {:noreply,
     socket
     |> assign(:target_interfaces, target_interfaces)
     |> assign(:targets, targets)}
  end

  def handle_info(
        {CadenceWeb.InterfaceLive.ProtocolConfigComponent, {:config_saved, interface}},
        socket
      ) do
    {:noreply, assign(socket, :interface, interface)}
  end

  def handle_info(
        {CadenceWeb.InterfaceLive.ProtocolConfigComponent, {:vcid_saved, _vcid}},
        socket
      ) do
    vcids = Interfaces.list_vcids_for_interface(socket.assigns.interface)
    {:noreply, assign(socket, :vcids, vcids)}
  end

  def handle_info(
        {CadenceWeb.InterfaceLive.ProtocolConfigComponent, {:vcid_deleted, _vcid}},
        socket
      ) do
    vcids = Interfaces.list_vcids_for_interface(socket.assigns.interface)
    {:noreply, assign(socket, :vcids, vcids)}
  end

  defp fetch_target_interface!(mapping_id, interface) do
    mapping = Interfaces.get_target_interface_by_id!(mapping_id)

    if mapping.interface_id == interface.id do
      mapping
    else
      raise ArgumentError, "Target-interface mapping not found"
    end
  end

  defp fetch_mission_interface(mission_id, interface_id) do
    mission = Missions.get_mission!(mission_id)
    interface = Interfaces.get_interface!(interface_id)

    if interface.mission_id == mission.id do
      {:ok, mission, interface}
    else
      {:error, :not_found}
    end
  end

  defp authorize_manage_interfaces(scope, mission) do
    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok -> :ok
      {:error, _} -> {:error, :unauthorized}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4 space-y-6">
      <.header>
        {@interface.name}
        <:subtitle>Interface details, targets, and VCID routing.</:subtitle>
        <:actions>
          <.link navigate={~p"/missions/#{@mission}/interfaces"}>
            <.button class="btn-ghost">Back</.button>
          </.link>
          <.link patch={~p"/missions/#{@mission}/interfaces/#{@interface}/edit"}>
            <.button>Edit</.button>
          </.link>
        </:actions>
      </.header>

      <div class="grid gap-4 md:grid-cols-3">
        <div class="rounded-sm border border-base-300 bg-base-200/40 p-4">
          <p class="text-xs uppercase tracking-wide text-base-content/60">Connection</p>
          <p class="mt-2 text-sm font-semibold text-base-content">
            {String.replace(@interface.connection_type || "none", "_", " ")}
          </p>
          <p class="text-xs text-base-content/60 mt-1">
            {interface_endpoint(@interface)}
          </p>
        </div>
        <div class="rounded-sm border border-base-300 bg-base-200/40 p-4">
          <p class="text-xs uppercase tracking-wide text-base-content/60">Targets</p>
          <p class="mt-2 text-sm font-semibold text-base-content">
            {length(@target_interfaces)} routed
          </p>
          <p class="text-xs text-base-content/60 mt-1">
            SCID-driven routing for TM frames
          </p>
        </div>
      </div>

      <div class="rounded-sm border border-base-300 bg-base-100">
        <div class="border-b border-base-300 px-4 py-3">
          <h3 class="text-sm font-semibold text-base-content">Targets on this Interface</h3>
        </div>
        <div class="p-4">
          <.table id="interface-targets" rows={@target_interfaces}>
            <:col :let={mapping} label="Name">{mapping.target.name}</:col>
            <:col :let={mapping} label="Identifier">{mapping.target.identifier}</:col>
            <:col :let={mapping} label="SCID">
              <%= if is_nil(mapping.scid) do %>
                <span class="text-xs text-base-content/50">Unassigned</span>
              <% else %>
                <span class="text-xs font-medium text-base-content">{mapping.scid}</span>
              <% end %>
            </:col>
            <:action :let={mapping}>
              <.link patch={
                ~p"/missions/#{@mission}/interfaces/#{@interface}/targets/#{mapping}/scid/edit"
              }>
                Set SCID
              </.link>
            </:action>
          </.table>
        </div>
      </div>

      <.live_component
        module={CadenceWeb.InterfaceLive.ProtocolConfigComponent}
        id="protocol-config"
        interface={@interface}
        interface_vcids={@vcids}
        targets={@targets}
      />
    </div>

    <.modal
      :if={@live_action == :edit_scid}
      id="interface-target-scid-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/interfaces/#{@interface}")}
    >
      <.live_component
        module={CadenceWeb.InterfaceTargetScidLive.FormComponent}
        id={@target_interface.id || :scid}
        title="Set SCID"
        action={:edit}
        target_interface={@target_interface}
        patch={~p"/missions/#{@mission}/interfaces/#{@interface}"}
      />
    </.modal>
    """
  end

  defp interface_endpoint(interface) do
    cond do
      interface.connection_type in ["tcp_client", "udp_client"] ->
        "#{interface.host}:#{interface.port}"

      interface.connection_type in ["tcp_server", "udp_server"] ->
        "#{interface.bind_address || "0.0.0.0"}:#{interface.bind_port}"

      true ->
        "Not configured"
    end
  end
end
