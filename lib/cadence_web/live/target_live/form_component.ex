defmodule CadenceWeb.TargetLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.{Interfaces, Targets}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Configure target details. The identifier must be unique within this mission.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="target-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="Satellite 1" />
        <.input
          field={@form[:identifier]}
          type="text"
          label="Identifier"
          placeholder="SAT-1"
          phx-debounce="blur"
        />
        <p class="mt-2 text-sm text-gray-600">
          Uppercase alphanumeric with hyphens/underscores (e.g., SAT-1, GROUND_STATION_ALPHA)
        </p>

        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          prompt="Choose a target type"
          options={[
            {"Spacecraft", "spacecraft"},
            {"Ground Station", "ground_station"},
            {"Simulator", "simulator"},
            {"Relay", "relay"}
          ]}
        />

        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={[
            {"Offline", "offline"},
            {"Online", "online"},
            {"Standby", "standby"},
            {"Fault", "fault"}
          ]}
        />

        <hr class="my-6 border-zinc-300" />

        <div>
          <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-2">
            Associated Interfaces
          </label>
          <p class="text-sm text-gray-600 mb-3">
            Select interfaces that communicate with this target.
          </p>

          <%= if Enum.empty?(@available_interfaces) do %>
            <p class="text-sm text-gray-500 italic">
              No interfaces defined for this mission. Create interfaces first.
            </p>
          <% else %>
            <div class="space-y-2 max-h-48 overflow-y-auto border border-zinc-200 rounded-lg p-3">
              <%= for interface <- @available_interfaces do %>
                <% is_selected = Map.has_key?(@selected_interfaces, interface.id) %>
                <% current_direction = Map.get(@selected_interfaces, interface.id, "read_write") %>
                <div class="flex items-center justify-between py-2 px-3 rounded-md hover:bg-zinc-50">
                  <label class="flex items-center gap-3 cursor-pointer flex-1">
                    <input
                      type="checkbox"
                      name="interface_associations[]"
                      value={interface.id}
                      checked={is_selected}
                      phx-click="toggle_interface"
                      phx-value-interface-id={interface.id}
                      phx-target={@myself}
                      class="rounded border-zinc-300 text-zinc-900 focus:ring-zinc-900"
                    />
                    <span class="text-sm font-medium text-zinc-700">
                      <%= interface.name %>
                      <span class="text-zinc-500">(<%= String.replace(interface.connection_type || "none", "_", " ") %>)</span>
                    </span>
                  </label>
                  <%= if is_selected do %>
                    <select
                      name={"interface_direction[#{interface.id}]"}
                      phx-change="update_interface_direction"
                      phx-value-interface-id={interface.id}
                      phx-target={@myself}
                      class="text-sm rounded-md border-zinc-300 py-1 pl-2 pr-8 focus:border-zinc-400 focus:ring-zinc-400"
                    >
                      <option value="read" selected={current_direction == "read"}>Read (Telemetry)</option>
                      <option value="write" selected={current_direction == "write"}>Write (Commands)</option>
                      <option value="read_write" selected={current_direction == "read_write"}>Read/Write</option>
                    </select>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%= if @action == :edit and (@target.config != %{} or @target.metadata != %{}) do %>
          <hr class="my-6 border-zinc-300" />
          <div class="space-y-4">
            <%= if @target.config != %{} do %>
              <div>
                <label class="block text-sm font-semibold leading-6 text-zinc-800">
                  Configuration (Read-only)
                </label>
                <pre class="mt-2 block w-full rounded-lg text-zinc-900 bg-zinc-50 border border-zinc-300 py-2 px-3 text-sm font-mono overflow-x-auto"><%= Jason.encode!(@target.config, pretty: true) %></pre>
              </div>
            <% end %>

            <%= if @target.metadata != %{} do %>
              <div>
                <label class="block text-sm font-semibold leading-6 text-zinc-800">
                  Metadata (Read-only)
                </label>
                <pre class="mt-2 block w-full rounded-lg text-zinc-900 bg-zinc-50 border border-zinc-300 py-2 px-3 text-sm font-mono overflow-x-auto"><%= Jason.encode!(@target.metadata, pretty: true) %></pre>
              </div>
            <% end %>
          </div>
        <% end %>

        <:actions>
          <.button phx-disable-with="Saving...">Save Target</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{target: target} = assigns, socket) do
    changeset = Targets.change_target(target)

    # Load available interfaces from assigns or default to empty
    available_interfaces = Map.get(assigns, :interfaces, [])

    # Load current interface associations if editing an existing target
    selected_interfaces =
      if target.id do
        target
        |> Interfaces.list_interfaces_for_target()
        |> Enum.map(fn interface ->
          # Get the direction from the join table
          target_interface = Interfaces.get_target_interface(target, interface)
          direction = if target_interface, do: target_interface.direction, else: "read_write"
          {interface.id, direction}
        end)
        |> Map.new()
      else
        %{}
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:available_interfaces, available_interfaces)
     |> assign(:selected_interfaces, selected_interfaces)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"target" => target_params}, socket) do
    changeset =
      socket.assigns.target
      |> Targets.change_target(target_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("toggle_interface", %{"interface-id" => interface_id}, socket) do
    selected_interfaces = socket.assigns.selected_interfaces

    updated_interfaces =
      if Map.has_key?(selected_interfaces, interface_id) do
        Map.delete(selected_interfaces, interface_id)
      else
        Map.put(selected_interfaces, interface_id, "read_write")
      end

    {:noreply, assign(socket, :selected_interfaces, updated_interfaces)}
  end

  def handle_event("update_interface_direction", %{"interface-id" => interface_id, "value" => direction}, socket) do
    selected_interfaces = socket.assigns.selected_interfaces
    updated_interfaces = Map.put(selected_interfaces, interface_id, direction)
    {:noreply, assign(socket, :selected_interfaces, updated_interfaces)}
  end

  def handle_event("save", %{"target" => target_params}, socket) do
    save_target(socket, socket.assigns.action, target_params)
  end

  defp save_target(socket, :edit, target_params) do
    # Check authorization
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case Targets.update_target(socket.assigns.target, target_params) do
          {:ok, target} ->
            # Sync interface associations
            sync_interface_associations(target, socket.assigns.selected_interfaces, socket.assigns.available_interfaces)
            notify_parent({:saved, target})

            {:noreply,
             socket
             |> put_flash(:info, "Target updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to update targets in this mission")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp save_target(socket, :new, target_params) do
    # Check authorization
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        # Add mission_id to params
        params_with_mission = Map.put(target_params, "mission_id", mission.id)

        case Targets.create_target(params_with_mission) do
          {:ok, target} ->
            # Add interface associations for new target
            sync_interface_associations(target, socket.assigns.selected_interfaces, socket.assigns.available_interfaces)
            notify_parent({:saved, target})

            {:noreply,
             socket
             |> put_flash(:info, "Target created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to create targets in this mission")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  # Syncs interface associations: removes old ones, adds/updates new ones
  defp sync_interface_associations(target, selected_interfaces, available_interfaces) do
    # Get current associations
    current_interfaces = Interfaces.list_interfaces_for_target(target)
    current_interface_ids = MapSet.new(Enum.map(current_interfaces, & &1.id))
    selected_interface_ids = MapSet.new(Map.keys(selected_interfaces))

    # Remove interfaces that are no longer selected
    interfaces_to_remove = MapSet.difference(current_interface_ids, selected_interface_ids)
    for interface_id <- interfaces_to_remove do
      interface = Enum.find(current_interfaces, &(&1.id == interface_id))
      if interface, do: Interfaces.remove_target_from_interface(target, interface)
    end

    # Add or update interfaces that are selected
    for {interface_id, direction} <- selected_interfaces do
      interface = Enum.find(available_interfaces, &(&1.id == interface_id))
      if interface do
        if MapSet.member?(current_interface_ids, interface_id) do
          # Update direction if changed
          Interfaces.update_target_interface_direction(target, interface, direction)
        else
          # Add new association
          Interfaces.add_target_to_interface(target, interface, direction)
        end
      end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
