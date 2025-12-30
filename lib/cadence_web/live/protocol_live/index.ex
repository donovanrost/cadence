defmodule CadenceWeb.ProtocolLive.Index do
  use CadenceWeb, :live_view

  alias Cadence.{Interfaces, Missions}
  alias Cadence.Interfaces.InterfaceProtocol

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, :index, %{"id" => mission_id, "interface_id" => interface_id}) do
    # Use unscoped - authorization is handled via Bodyguard below
    mission = Missions.get_mission!(mission_id)
    interface = Interfaces.get_interface!(interface_id)
    scope = socket.assigns.current_scope

    # Verify interface belongs to mission
    if interface.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          protocols = Interfaces.list_protocols(interface)

          {:noreply,
           socket
           |> assign(:page_title, "Manage Protocols")
           |> assign(:mission, mission)
           |> assign(:interface, interface)
           |> assign(:protocols, protocols)
           |> assign(:protocol, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don't have permission to manage protocols")
           |> push_navigate(to: ~p"/missions/#{mission_id}")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Interface not found in this mission")
       |> push_navigate(to: ~p"/missions/#{mission_id}")}
    end
  end

  defp apply_action(socket, :new, %{"id" => mission_id, "interface_id" => interface_id}) do
    # Use unscoped - authorization is handled via Bodyguard below
    mission = Missions.get_mission!(mission_id)
    interface = Interfaces.get_interface!(interface_id)
    scope = socket.assigns.current_scope

    # Verify interface belongs to mission
    if interface.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          protocols = Interfaces.list_protocols(interface)

          {:noreply,
           socket
           |> assign(:page_title, "New Protocol")
           |> assign(:mission, mission)
           |> assign(:interface, interface)
           |> assign(:protocols, protocols)
           |> assign(:protocol, %InterfaceProtocol{})}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don't have permission to manage protocols")
           |> push_navigate(to: ~p"/missions/#{mission_id}")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Interface not found in this mission")
       |> push_navigate(to: ~p"/missions/#{mission_id}")}
    end
  end

  defp apply_action(socket, :edit, %{
         "id" => mission_id,
         "interface_id" => interface_id,
         "protocol_id" => protocol_id
       }) do
    # Use unscoped - authorization is handled via Bodyguard below
    mission = Missions.get_mission!(mission_id)
    interface = Interfaces.get_interface!(interface_id)
    protocol = Interfaces.get_protocol!(protocol_id)
    scope = socket.assigns.current_scope

    # Verify interface belongs to mission and protocol belongs to interface
    if interface.mission_id == mission.id && protocol.interface_id == interface.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          protocols = Interfaces.list_protocols(interface)

          {:noreply,
           socket
           |> assign(:page_title, "Edit Protocol")
           |> assign(:mission, mission)
           |> assign(:interface, interface)
           |> assign(:protocols, protocols)
           |> assign(:protocol, protocol)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don't have permission to manage protocols")
           |> push_navigate(to: ~p"/missions/#{mission_id}")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Protocol or interface not found")
       |> push_navigate(to: ~p"/missions/#{mission_id}")}
    end
  end

  @impl true
  def handle_info({CadenceWeb.ProtocolLive.FormComponent, {:saved, _protocol}}, socket) do
    # Reload protocols list after save
    protocols = Interfaces.list_protocols(socket.assigns.interface)
    {:noreply, assign(socket, :protocols, protocols)}
  end

  @impl true
  def handle_event("delete", %{"id" => protocol_id}, socket) do
    protocol = Interfaces.get_protocol!(protocol_id)
    interface = socket.assigns.interface
    _mission = socket.assigns.mission

    # Verify protocol belongs to this interface
    if protocol.interface_id == interface.id do
      case Interfaces.delete_protocol(protocol) do
        {:ok, _} ->
          protocols = Interfaces.list_protocols(interface)

          {:noreply,
           socket
           |> put_flash(:info, "Protocol deleted successfully")
           |> assign(:protocols, protocols)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete protocol")}
      end
    else
      {:noreply, put_flash(socket, :error, "Protocol not found in this interface")}
    end
  end

  @impl true
  def handle_event("move_up", %{"id" => protocol_id}, socket) do
    move_protocol(socket, protocol_id, :up)
  end

  @impl true
  def handle_event("move_down", %{"id" => protocol_id}, socket) do
    move_protocol(socket, protocol_id, :down)
  end

  defp move_protocol(socket, protocol_id, direction) do
    protocols = socket.assigns.protocols

    with {:ok, current_index} <- protocol_index(protocols, protocol_id),
         {:ok, new_index} <- target_index(current_index, length(protocols), direction),
         {:ok, updated_protocols} <-
           reorder_protocols(socket, protocols, current_index, new_index) do
      {:noreply,
       socket
       |> put_flash(:info, "Protocol order updated")
       |> assign(:protocols, updated_protocols)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Protocol not found")}

      {:error, :no_op} ->
        {:noreply, socket}

      {:error, :reorder_failed} ->
        {:noreply, put_flash(socket, :error, "Failed to reorder protocols")}
    end
  end

  # View helpers

  defp format_protocol_type(protocol_type) do
    case protocol_type do
      "length" -> "Length-Prefixed Protocol"
      "template" -> "Template Protocol (CCSDS)"
      "terminated" -> "Terminated Protocol"
      "fixed" -> "Fixed-Size Protocol"
      other -> String.capitalize(other)
    end
  end

  defp protocol_config_summary(protocol) do
    case protocol.protocol_type do
      "length" -> length_config_summary(protocol.protocol_config)
      "template" -> template_config_summary(protocol.protocol_config)
      "terminated" -> terminated_config_summary(protocol.protocol_config)
      "fixed" -> fixed_config_summary(protocol.protocol_config)
      _ -> "Custom configuration"
    end
  end

  defp protocol_index(protocols, protocol_id) do
    case Enum.find_index(protocols, &(&1.id == protocol_id)) do
      nil -> {:error, :not_found}
      index -> {:ok, index}
    end
  end

  defp target_index(current_index, _total, :up) do
    new_index = max(0, current_index - 1)
    ensure_move(current_index, new_index)
  end

  defp target_index(current_index, total, :down) do
    new_index = min(total - 1, current_index + 1)
    ensure_move(current_index, new_index)
  end

  defp ensure_move(current_index, current_index), do: {:error, :no_op}
  defp ensure_move(_current_index, new_index), do: {:ok, new_index}

  defp reorder_protocols(socket, protocols, current_index, new_index) do
    new_order =
      protocols
      |> List.replace_at(current_index, Enum.at(protocols, new_index))
      |> List.replace_at(new_index, Enum.at(protocols, current_index))

    protocol_ids = Enum.map(new_order, & &1.id)

    case Interfaces.reorder_protocols(socket.assigns.interface, protocol_ids) do
      {:ok, updated_protocols} -> {:ok, updated_protocols}
      {:error, _} -> {:error, :reorder_failed}
    end
  end

  defp length_config_summary(protocol_config) do
    bit_size = get_in(protocol_config, ["length_bit_size"]) || 32
    endian = get_in(protocol_config, ["length_endian"]) || "big"
    "#{bit_size}-bit length field, #{endian} endian"
  end

  defp template_config_summary(protocol_config) do
    sync = get_in(protocol_config, ["sync_pattern_hex"]) || "N/A"
    "Sync pattern: #{sync}"
  end

  defp terminated_config_summary(protocol_config) do
    term = get_in(protocol_config, ["terminator_hex"]) || "N/A"
    "Terminator: #{term}"
  end

  defp fixed_config_summary(protocol_config) do
    size = get_in(protocol_config, ["packet_size"]) || "N/A"
    "Packet size: #{size} bytes"
  end
end
