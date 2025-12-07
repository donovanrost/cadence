defmodule CadenceWeb.InterfaceLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.Interfaces

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Configure interface connection and protocol settings.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="interface-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="Primary Telemetry" />

        <.input
          field={@form[:connection_type]}
          type="select"
          label="Connection Type"
          prompt="Choose connection type"
          options={[
            {"TCP Client (connect to)", "tcp_client"},
            {"TCP Server (accept from)", "tcp_server"},
            {"UDP Client", "udp_client"},
            {"UDP Server", "udp_server"},
            {"Serial Port", "serial"}
          ]}
        />

        <%!-- Connection-specific fields --%>
        <%= if @connection_type in ["tcp_client", "udp_client"] do %>
          <div class="grid grid-cols-2 gap-4">
            <.input field={@form[:host]} type="text" label="Host" placeholder="192.168.1.100" />
            <.input field={@form[:port]} type="number" label="Port" placeholder="8080" />
          </div>
        <% end %>

        <%= if @connection_type in ["tcp_server", "udp_server"] do %>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:bind_address]}
              type="text"
              label="Bind Address (optional)"
              placeholder="0.0.0.0"
            />
            <.input field={@form[:bind_port]} type="number" label="Bind Port" placeholder="9000" />
          </div>
        <% end %>

        <%= if @connection_type == "serial" do %>
          <.input
            field={@form[:host]}
            type="text"
            label="Device Path"
            placeholder="/dev/ttyUSB0"
          />
        <% end %>

        <hr class="my-6 border-zinc-300" />

        <div>
          <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-2">
            Associated Targets
          </label>
          <p class="text-sm text-gray-600 mb-3">
            Select targets that communicate through this interface. This determines how telemetry is routed.
          </p>

          <%= if Enum.empty?(@available_targets) do %>
            <p class="text-sm text-gray-500 italic">
              No targets defined for this mission. Create targets first.
            </p>
          <% else %>
            <div class="space-y-2 max-h-48 overflow-y-auto border border-zinc-200 rounded-lg p-3">
              <%= for target <- @available_targets do %>
                <% is_selected = Map.has_key?(@selected_targets, target.id) %>
                <% current_direction = Map.get(@selected_targets, target.id, "read_write") %>
                <div class="flex items-center justify-between py-2 px-3 rounded-md hover:bg-zinc-50">
                  <label class="flex items-center gap-3 cursor-pointer flex-1">
                    <input
                      type="checkbox"
                      name="target_associations[]"
                      value={target.id}
                      checked={is_selected}
                      phx-click="toggle_target"
                      phx-value-target-id={target.id}
                      phx-target={@myself}
                      class="rounded border-zinc-300 text-zinc-900 focus:ring-zinc-900"
                    />
                    <span class="text-sm font-medium text-zinc-700">
                      {target.name}
                      <span class="text-zinc-500">({target.identifier})</span>
                    </span>
                  </label>
                  <%= if is_selected do %>
                    <select
                      name={"target_direction[#{target.id}]"}
                      phx-change="update_direction"
                      phx-value-target-id={target.id}
                      phx-target={@myself}
                      class="text-sm rounded-md border-zinc-300 py-1 pl-2 pr-8 focus:border-zinc-400 focus:ring-zinc-400"
                    >
                      <option value="read" selected={current_direction == "read"}>
                        Read (Telemetry)
                      </option>
                      <option value="write" selected={current_direction == "write"}>
                        Write (Commands)
                      </option>
                      <option value="read_write" selected={current_direction == "read_write"}>
                        Read/Write
                      </option>
                    </select>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <hr class="my-6 border-zinc-300" />

        <p class="text-sm text-gray-600">
          Protocols can be configured after creating the interface.
        </p>

        <hr class="my-6 border-zinc-300" />

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:auto_reconnect]}
            type="checkbox"
            label="Auto-reconnect on disconnect"
          />
          <.input
            field={@form[:reconnect_delay_ms]}
            type="number"
            label="Reconnect Delay (ms)"
            placeholder="5000"
          />
        </div>

        <:actions>
          <.button phx-disable-with="Saving...">Save Interface</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{interface: interface} = assigns, socket) do
    changeset = Interfaces.change_interface(interface)

    # Load available targets from assigns or default to empty
    available_targets = Map.get(assigns, :targets, [])

    # Load current target associations if editing an existing interface
    selected_targets =
      if interface.id do
        interface
        |> Interfaces.list_targets_for_interface()
        |> Enum.map(fn target ->
          # Get the direction from the join table
          target_interface = Interfaces.get_target_interface(target, interface)
          direction = if target_interface, do: target_interface.direction, else: "read_write"
          {target.id, direction}
        end)
        |> Map.new()
      else
        %{}
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:connection_type, interface.connection_type)
     |> assign(:available_targets, available_targets)
     |> assign(:selected_targets, selected_targets)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"interface_schema" => interface_params}, socket) do
    # Update reactive assigns
    connection_type = Map.get(interface_params, "connection_type")

    changeset =
      socket.assigns.interface
      |> Interfaces.change_interface(interface_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:connection_type, connection_type)
     |> assign_form(changeset)}
  end

  def handle_event("toggle_target", %{"target-id" => target_id}, socket) do
    selected_targets = socket.assigns.selected_targets

    updated_targets =
      if Map.has_key?(selected_targets, target_id) do
        Map.delete(selected_targets, target_id)
      else
        Map.put(selected_targets, target_id, "read_write")
      end

    {:noreply, assign(socket, :selected_targets, updated_targets)}
  end

  def handle_event("update_direction", %{"target-id" => target_id, "value" => direction}, socket) do
    selected_targets = socket.assigns.selected_targets
    updated_targets = Map.put(selected_targets, target_id, direction)
    {:noreply, assign(socket, :selected_targets, updated_targets)}
  end

  def handle_event("save", %{"interface_schema" => interface_params}, socket) do
    save_interface(socket, socket.assigns.action, interface_params)
  end

  defp save_interface(socket, :edit, interface_params) do
    # Check authorization
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case Interfaces.update_interface(socket.assigns.interface, interface_params) do
          {:ok, interface} ->
            # Sync target associations
            sync_target_associations(
              interface,
              socket.assigns.selected_targets,
              socket.assigns.available_targets
            )

            notify_parent({:saved, interface})

            {:noreply,
             socket
             |> put_flash(:info, "Interface updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to update interfaces in this mission")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp save_interface(socket, :new_interface, interface_params) do
    # Check authorization
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        # Add mission_id
        params_with_mission = Map.put(interface_params, "mission_id", mission.id)

        case Interfaces.create_interface(params_with_mission) do
          {:ok, interface} ->
            # Add target associations for new interface
            sync_target_associations(
              interface,
              socket.assigns.selected_targets,
              socket.assigns.available_targets
            )

            notify_parent({:saved, interface})

            {:noreply,
             socket
             |> put_flash(:info, "Interface created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to create interfaces in this mission")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  # Syncs target associations: removes old ones, adds/updates new ones
  defp sync_target_associations(interface, selected_targets, available_targets) do
    # Get current associations
    current_targets = Interfaces.list_targets_for_interface(interface)
    current_target_ids = MapSet.new(Enum.map(current_targets, & &1.id))
    selected_target_ids = MapSet.new(Map.keys(selected_targets))

    # Remove targets that are no longer selected
    targets_to_remove = MapSet.difference(current_target_ids, selected_target_ids)

    for target_id <- targets_to_remove do
      target = Enum.find(current_targets, &(&1.id == target_id))
      if target, do: Interfaces.remove_target_from_interface(target, interface)
    end

    # Add or update targets that are selected
    for {target_id, direction} <- selected_targets do
      target = Enum.find(available_targets, &(&1.id == target_id))

      if target do
        if MapSet.member?(current_target_ids, target_id) do
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
