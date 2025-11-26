defmodule CadenceWeb.MissionLive.Show do
  use CadenceWeb, :live_view

  alias Cadence.{Databases, Interfaces, Missions, Targets}
  alias Cadence.Telemetry.Database.DerivedItem

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope

    # Check if user can view this mission
    case Bodyguard.permit(Cadence.Missions.Policy, :view, scope, mission) do
      :ok ->
        targets = Targets.list_targets(mission)
        interfaces = Interfaces.list_interfaces(mission)
        interface_protocol_counts = build_protocol_counts(interfaces)
        interface_targets = build_interface_targets(interfaces)
        definition_sets = Databases.list_definition_sets(mission)
        derived_items = DerivedItem.list_all(mission.id)

        {:noreply,
         socket
         |> assign(:page_title, "Show Mission")
         |> assign(:mission, mission)
         |> assign(:targets, targets)
         |> assign(:target, nil)
         |> assign(:interfaces, interfaces)
         |> assign(:interface, nil)
         |> assign(:interface_protocol_counts, interface_protocol_counts)
         |> assign(:interface_targets, interface_targets)
         |> assign(:definition_sets, definition_sets)
         |> assign(:definition_set, nil)
         |> assign(:derived_items, derived_items)
         |> assign(:derived_item, nil)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission) do
      :ok ->
        targets = Targets.list_targets(mission)
        interfaces = Interfaces.list_interfaces(mission)
        interface_protocol_counts = build_protocol_counts(interfaces)
        interface_targets = build_interface_targets(interfaces)
        definition_sets = Databases.list_definition_sets(mission)
        derived_items = DerivedItem.list_all(mission.id)

        {:noreply,
         socket
         |> assign(:page_title, "Edit Mission")
         |> assign(:mission, mission)
         |> assign(:targets, targets)
         |> assign(:target, nil)
         |> assign(:interfaces, interfaces)
         |> assign(:interface, nil)
         |> assign(:interface_protocol_counts, interface_protocol_counts)
         |> assign(:interface_targets, interface_targets)
         |> assign(:definition_sets, definition_sets)
         |> assign(:definition_set, nil)
         |> assign(:derived_items, derived_items)
         |> assign(:derived_item, nil)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to edit this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :new_target, %{"id" => id}) do
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        targets = Targets.list_targets(mission)
        interfaces = Interfaces.list_interfaces(mission)
        interface_protocol_counts = build_protocol_counts(interfaces)
        interface_targets = build_interface_targets(interfaces)
        definition_sets = Databases.list_definition_sets(mission)
        derived_items = DerivedItem.list_all(mission.id)

        {:noreply,
         socket
         |> assign(:page_title, "New Target")
         |> assign(:mission, mission)
         |> assign(:targets, targets)
         |> assign(:target, %Targets.Target{})
         |> assign(:interfaces, interfaces)
         |> assign(:interface, nil)
         |> assign(:interface_protocol_counts, interface_protocol_counts)
         |> assign(:interface_targets, interface_targets)
         |> assign(:definition_sets, definition_sets)
         |> assign(:definition_set, nil)
         |> assign(:derived_items, derived_items)
         |> assign(:derived_item, nil)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to create targets in this mission")
         |> push_patch(to: ~p"/missions/#{id}")}
    end
  end

  defp apply_action(socket, :edit_target, %{"id" => id, "target_id" => target_id}) do
    mission = Missions.get_mission!(id)
    target = Targets.get_target!(target_id)
    scope = socket.assigns.current_scope

    # Verify target belongs to this mission
    if target.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          targets = Targets.list_targets(mission)
          interfaces = Interfaces.list_interfaces(mission)
          interface_protocol_counts = build_protocol_counts(interfaces)
          interface_targets = build_interface_targets(interfaces)
          definition_sets = Databases.list_definition_sets(mission)
          derived_items = DerivedItem.list_all(mission.id)

          {:noreply,
           socket
           |> assign(:page_title, "Edit Target")
           |> assign(:mission, mission)
           |> assign(:targets, targets)
           |> assign(:target, target)
           |> assign(:interfaces, interfaces)
           |> assign(:interface, nil)
           |> assign(:interface_protocol_counts, interface_protocol_counts)
           |> assign(:interface_targets, interface_targets)
           |> assign(:definition_sets, definition_sets)
           |> assign(:definition_set, nil)
           |> assign(:derived_items, derived_items)
           |> assign(:derived_item, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don't have permission to edit targets in this mission")
           |> push_patch(to: ~p"/missions/#{id}")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Target not found in this mission")
       |> push_patch(to: ~p"/missions/#{id}")}
    end
  end

  defp apply_action(socket, :new_interface, %{"id" => id}) do
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        targets = Targets.list_targets(mission)
        interfaces = Interfaces.list_interfaces(mission)
        interface_protocol_counts = build_protocol_counts(interfaces)
        interface_targets = build_interface_targets(interfaces)
        definition_sets = Databases.list_definition_sets(mission)
        derived_items = DerivedItem.list_all(mission.id)

        {:noreply,
         socket
         |> assign(:page_title, "New Interface")
         |> assign(:mission, mission)
         |> assign(:targets, targets)
         |> assign(:target, nil)
         |> assign(:interfaces, interfaces)
         |> assign(:interface, %Interfaces.InterfaceSchema{})
         |> assign(:interface_protocol_counts, interface_protocol_counts)
         |> assign(:interface_targets, interface_targets)
         |> assign(:definition_sets, definition_sets)
         |> assign(:definition_set, nil)
         |> assign(:derived_items, derived_items)
         |> assign(:derived_item, nil)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to create interfaces in this mission")
         |> push_patch(to: ~p"/missions/#{id}")}
    end
  end

  defp apply_action(socket, :edit_interface, %{"id" => id, "interface_id" => interface_id}) do
    mission = Missions.get_mission!(id)
    interface = Interfaces.get_interface!(interface_id)
    scope = socket.assigns.current_scope

    # Verify interface belongs to this mission
    if interface.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          targets = Targets.list_targets(mission)
          interfaces = Interfaces.list_interfaces(mission)
          interface_protocol_counts = build_protocol_counts(interfaces)
          interface_targets = build_interface_targets(interfaces)
          definition_sets = Databases.list_definition_sets(mission)
          derived_items = DerivedItem.list_all(mission.id)

          {:noreply,
           socket
           |> assign(:page_title, "Edit Interface")
           |> assign(:mission, mission)
           |> assign(:targets, targets)
           |> assign(:target, nil)
           |> assign(:interfaces, interfaces)
           |> assign(:interface, interface)
           |> assign(:interface_protocol_counts, interface_protocol_counts)
           |> assign(:interface_targets, interface_targets)
           |> assign(:definition_sets, definition_sets)
           |> assign(:definition_set, nil)
           |> assign(:derived_items, derived_items)
           |> assign(:derived_item, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don't have permission to edit interfaces in this mission")
           |> push_patch(to: ~p"/missions/#{id}")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Interface not found in this mission")
       |> push_patch(to: ~p"/missions/#{id}")}
    end
  end

  defp apply_action(socket, :new_database, %{"id" => id}) do
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        targets = Targets.list_targets(mission)
        interfaces = Interfaces.list_interfaces(mission)
        interface_protocol_counts = build_protocol_counts(interfaces)
        interface_targets = build_interface_targets(interfaces)
        definition_sets = Databases.list_definition_sets(mission)
        derived_items = DerivedItem.list_all(mission.id)

        {:noreply,
         socket
         |> assign(:page_title, "Import Database")
         |> assign(:mission, mission)
         |> assign(:targets, targets)
         |> assign(:target, nil)
         |> assign(:interfaces, interfaces)
         |> assign(:interface, nil)
         |> assign(:interface_protocol_counts, interface_protocol_counts)
         |> assign(:interface_targets, interface_targets)
         |> assign(:definition_sets, definition_sets)
         |> assign(:definition_set, nil)
         |> assign(:derived_items, derived_items)
         |> assign(:derived_item, nil)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to import databases in this mission")
         |> push_patch(to: ~p"/missions/#{id}")}
    end
  end

  defp apply_action(socket, :show_database, %{"id" => id, "database_id" => database_id}) do
    mission = Missions.get_mission!(id)
    definition_set = Databases.get_definition_set!(database_id)
    scope = socket.assigns.current_scope

    # Verify definition set belongs to this mission
    if definition_set.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :view, scope, mission) do
        :ok ->
          targets = Targets.list_targets(mission)
          interfaces = Interfaces.list_interfaces(mission)
          interface_protocol_counts = build_protocol_counts(interfaces)
          interface_targets = build_interface_targets(interfaces)
          definition_sets = Databases.list_definition_sets(mission)
          derived_items = DerivedItem.list_all(mission.id)

          {:noreply,
           socket
           |> assign(:page_title, "Database v#{definition_set.version}")
           |> assign(:mission, mission)
           |> assign(:targets, targets)
           |> assign(:target, nil)
           |> assign(:interfaces, interfaces)
           |> assign(:interface, nil)
           |> assign(:interface_protocol_counts, interface_protocol_counts)
           |> assign(:interface_targets, interface_targets)
           |> assign(:definition_sets, definition_sets)
           |> assign(:definition_set, definition_set)
           |> assign(:derived_items, derived_items)
           |> assign(:derived_item, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don't have permission to view this mission")
           |> push_patch(to: ~p"/missions/#{id}")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Database not found in this mission")
       |> push_patch(to: ~p"/missions/#{id}")}
    end
  end

  defp apply_action(socket, :new_derived_item, %{"id" => id}) do
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        targets = Targets.list_targets(mission)
        interfaces = Interfaces.list_interfaces(mission)
        interface_protocol_counts = build_protocol_counts(interfaces)
        interface_targets = build_interface_targets(interfaces)
        definition_sets = Databases.list_definition_sets(mission)
        derived_items = DerivedItem.list_all(mission.id)

        {:noreply,
         socket
         |> assign(:page_title, "New Derived Item")
         |> assign(:mission, mission)
         |> assign(:targets, targets)
         |> assign(:target, nil)
         |> assign(:interfaces, interfaces)
         |> assign(:interface, nil)
         |> assign(:interface_protocol_counts, interface_protocol_counts)
         |> assign(:interface_targets, interface_targets)
         |> assign(:definition_sets, definition_sets)
         |> assign(:definition_set, nil)
         |> assign(:derived_items, derived_items)
         |> assign(:derived_item, %DerivedItem{})}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to create derived items in this mission")
         |> push_patch(to: ~p"/missions/#{id}")}
    end
  end

  defp apply_action(socket, :edit_derived_item, %{"id" => id, "derived_item_id" => derived_item_id}) do
    mission = Missions.get_mission!(id)
    derived_item = DerivedItem.get!(derived_item_id)
    scope = socket.assigns.current_scope

    # Verify derived item belongs to this mission
    if derived_item.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          targets = Targets.list_targets(mission)
          interfaces = Interfaces.list_interfaces(mission)
          interface_protocol_counts = build_protocol_counts(interfaces)
          interface_targets = build_interface_targets(interfaces)
          definition_sets = Databases.list_definition_sets(mission)
          derived_items = DerivedItem.list_all(mission.id)

          {:noreply,
           socket
           |> assign(:page_title, "Edit Derived Item")
           |> assign(:mission, mission)
           |> assign(:targets, targets)
           |> assign(:target, nil)
           |> assign(:interfaces, interfaces)
           |> assign(:interface, nil)
           |> assign(:interface_protocol_counts, interface_protocol_counts)
           |> assign(:interface_targets, interface_targets)
           |> assign(:definition_sets, definition_sets)
           |> assign(:definition_set, nil)
           |> assign(:derived_items, derived_items)
           |> assign(:derived_item, derived_item)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don't have permission to edit derived items in this mission")
           |> push_patch(to: ~p"/missions/#{id}")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Derived item not found in this mission")
       |> push_patch(to: ~p"/missions/#{id}")}
    end
  end

  @impl true
  def handle_info({CadenceWeb.TargetLive.FormComponent, {:saved, _target}}, socket) do
    # Reload targets list after save
    targets = Targets.list_targets(socket.assigns.mission)
    {:noreply, assign(socket, :targets, targets)}
  end

  @impl true
  def handle_info({CadenceWeb.InterfaceLive.FormComponent, {:saved, _interface}}, socket) do
    # Reload interfaces list after save
    interfaces = Interfaces.list_interfaces(socket.assigns.mission)
    interface_protocol_counts = build_protocol_counts(interfaces)
    interface_targets = build_interface_targets(interfaces)

    {:noreply,
     socket
     |> assign(:interfaces, interfaces)
     |> assign(:interface_protocol_counts, interface_protocol_counts)
     |> assign(:interface_targets, interface_targets)}
  end

  def handle_info({CadenceWeb.DatabaseLive.FormComponent, {:saved, _definition_set}}, socket) do
    # Reload definition sets list after save
    definition_sets = Databases.list_definition_sets(socket.assigns.mission)
    {:noreply, assign(socket, :definition_sets, definition_sets)}
  end

  def handle_info({CadenceWeb.DatabaseLive.ShowComponent, {:published, _definition_set}}, socket) do
    # Reload definition sets list after publish
    definition_sets = Databases.list_definition_sets(socket.assigns.mission)
    {:noreply, assign(socket, :definition_sets, definition_sets)}
  end

  def handle_info({CadenceWeb.DatabaseLive.ShowComponent, {:deleted, _definition_set}}, socket) do
    # Reload definition sets list after delete
    definition_sets = Databases.list_definition_sets(socket.assigns.mission)
    {:noreply, assign(socket, :definition_sets, definition_sets)}
  end

  def handle_info({CadenceWeb.DerivedItemLive.FormComponent, {:saved, _derived_item}}, socket) do
    # Reload derived items list after save
    derived_items = DerivedItem.list_all(socket.assigns.mission.id)
    {:noreply, assign(socket, :derived_items, derived_items)}
  end

  def handle_info({CadenceWeb.DerivedItemLive.FormComponent, {:deleted, _derived_item}}, socket) do
    # Reload derived items list after delete
    derived_items = DerivedItem.list_all(socket.assigns.mission.id)
    {:noreply, assign(socket, :derived_items, derived_items)}
  end

  @impl true
  def handle_event("delete_target", %{"id" => target_id}, socket) do
    target = Targets.get_target!(target_id)
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    # Verify target belongs to this mission
    if target.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          case Targets.delete_target(target) do
            {:ok, _} ->
              targets = Targets.list_targets(mission)

              {:noreply,
               socket
               |> put_flash(:info, "Target deleted successfully")
               |> assign(:targets, targets)}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to delete target")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to delete targets")}
      end
    else
      {:noreply, put_flash(socket, :error, "Target not found in this mission")}
    end
  end

  @impl true
  def handle_event("delete_interface", %{"id" => interface_id}, socket) do
    interface = Interfaces.get_interface!(interface_id)
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    # Verify interface belongs to this mission
    if interface.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          case Interfaces.delete_interface(interface) do
            {:ok, _} ->
              interfaces = Interfaces.list_interfaces(mission)
              interface_protocol_counts = build_protocol_counts(interfaces)

              {:noreply,
               socket
               |> put_flash(:info, "Interface deleted successfully")
               |> assign(:interfaces, interfaces)
               |> assign(:interface_protocol_counts, interface_protocol_counts)}

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

  @impl true
  def handle_event("start_mission", _params, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    # Check if user can manage this mission
    case Bodyguard.permit(Cadence.Missions.Policy, :manage, scope, mission) do
      :ok ->
        case Missions.start_mission(mission) do
          {:ok, _pid} ->
            {:noreply,
             socket
             |> put_flash(:info, "Mission started successfully")
             |> assign(:mission_running, true)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start mission: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to start this mission")}
    end
  end

  @impl true
  def handle_event("stop_mission", _params, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    # Check if user can manage this mission
    case Bodyguard.permit(Cadence.Missions.Policy, :manage, scope, mission) do
      :ok ->
        case Missions.stop_mission(mission.id) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "Mission stopped successfully")
             |> assign(:mission_running, false)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to stop mission: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to stop this mission")}
    end
  end

  # Build a map of interface_id => protocol_count for display
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

  # Build a map of interface_id => list of associated targets for display
  defp build_interface_targets(interfaces) do
    interfaces
    |> Enum.map(fn interface ->
      targets = Interfaces.list_targets_for_interface(interface, preload: false)
      {interface.id, targets}
    end)
    |> Map.new()
  end

  defp page_title(:show), do: "Show Mission"
  defp page_title(:edit), do: "Edit Mission"
  defp page_title(:new_target), do: "New Target"
  defp page_title(:edit_target), do: "Edit Target"
  defp page_title(:new_interface), do: "New Interface"
  defp page_title(:edit_interface), do: "Edit Interface"
  defp page_title(:new_database), do: "Import Database"
  defp page_title(:show_database), do: "Database Details"
  defp page_title(:new_derived_item), do: "New Derived Item"
  defp page_title(:edit_derived_item), do: "Edit Derived Item"
end
