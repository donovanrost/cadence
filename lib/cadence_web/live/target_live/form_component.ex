defmodule CadenceWeb.TargetLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.{Interfaces, MissionDatabase, Targets}
  alias Cadence.MissionDatabase.DefinitionSet
  alias Cadence.Targets.Target

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Configure target details. The identifier must be unique within this mission.
        </:subtitle>
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
        <p class="mt-2 text-sm text-base-content/60">
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

        <hr class="my-6 border-base-300" />

        <div>
          <label class="block text-sm font-semibold leading-6 text-base-content mb-2">
            Command & Telemetry Database
          </label>
          <p class="text-sm text-base-content/60 mb-3">
            Select which database version this target uses for commands and telemetry.
          </p>

          <div class="space-y-4 border border-base-300 rounded-sm p-4 bg-base-200/50">
            <%= if Enum.empty?(@available_databases) do %>
              <p class="text-sm text-base-content/50 italic">
                No databases available for this mission. Create a database first to configure targets.
              </p>
            <% else %>
              <div>
                <label class="hud-label block mb-1">Database</label>
                <select
                  name="selected_database_id"
                  phx-change="select_database"
                  phx-target={@myself}
                  class="w-full select select-sm"
                >
                  <option value="">Choose a database...</option>
                  <%= for db <- @available_databases do %>
                    <option value={db.id} selected={@selected_database_id == db.id}>
                      {db.name}
                    </option>
                  <% end %>
                </select>
              </div>

              <%= if @selected_database_id && length(@available_versions) > 0 do %>
                <div>
                  <label class="hud-label block mb-1">Version</label>
                  <select
                    name="definition_set_id"
                    phx-change="select_version"
                    phx-target={@myself}
                    class="w-full select select-sm"
                  >
                    <option value="">Choose a version...</option>
                    <%= for ds <- @available_versions do %>
                      <option value={ds.id} selected={@selected_definition_set_id == ds.id}>
                        v{ds.version} {version_status_label(ds)}
                      </option>
                    <% end %>
                  </select>
                </div>
              <% end %>

              <%= if @selected_database_id && length(@available_versions) == 0 do %>
                <p class="text-sm text-base-content/50 italic">
                  No versions available for this database yet.
                </p>
              <% end %>

              <%= if is_nil(@selected_definition_set_id) do %>
                <p class="text-xs text-warning">
                  A database version is required to save the target.
                </p>
              <% end %>
            <% end %>
          </div>
        </div>

        <hr class="my-6 border-base-300" />

        <div>
          <label class="block text-sm font-semibold leading-6 text-base-content mb-2">
            Associated Interfaces
          </label>
          <p class="text-sm text-base-content/60 mb-3">
            Select interfaces that communicate with this target.
          </p>

          <%= if Enum.empty?(@available_interfaces) do %>
            <p class="text-sm text-base-content/50 italic">
              No interfaces defined for this mission. Create interfaces first.
            </p>
          <% else %>
            <div class="space-y-2 max-h-48 overflow-y-auto border border-base-300 rounded-sm p-3 bg-base-200/50">
              <%= for interface <- @available_interfaces do %>
                <% is_selected = Map.has_key?(@selected_interfaces, interface.id) %>
                <% current_direction = Map.get(@selected_interfaces, interface.id, "read_write") %>
                <div class="flex items-center justify-between py-2 px-3 rounded-sm hover:bg-base-300/50">
                  <label class="flex items-center gap-3 cursor-pointer flex-1">
                    <input
                      type="checkbox"
                      name="interface_associations[]"
                      value={interface.id}
                      checked={is_selected}
                      phx-click="toggle_interface"
                      phx-value-interface-id={interface.id}
                      phx-target={@myself}
                      class="checkbox checkbox-sm"
                    />
                    <span class="text-sm font-medium text-base-content">
                      {interface.name}
                      <span class="text-base-content/50">
                        ({String.replace(interface.connection_type || "none", "_", " ")})
                      </span>
                    </span>
                  </label>
                  <%= if is_selected do %>
                    <select
                      name={"interface_direction[#{interface.id}]"}
                      phx-change="update_interface_direction"
                      phx-value-interface-id={interface.id}
                      phx-target={@myself}
                      class="select select-sm"
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

        <%= if @action == :edit and (@target.config != %{} or @target.metadata != %{}) do %>
          <hr class="my-6 border-base-300" />
          <div class="space-y-4">
            <%= if @target.config != %{} do %>
              <div>
                <label class="block text-sm font-semibold leading-6 text-base-content">
                  Configuration (Read-only)
                </label>
                <pre class="mt-2 block w-full rounded-sm text-base-content bg-base-200 border border-base-300 py-2 px-3 text-sm font-mono overflow-x-auto"><%= Jason.encode!(@target.config, pretty: true) %></pre>
              </div>
            <% end %>

            <%= if @target.metadata != %{} do %>
              <div>
                <label class="block text-sm font-semibold leading-6 text-base-content">
                  Metadata (Read-only)
                </label>
                <pre class="mt-2 block w-full rounded-sm text-base-content bg-base-200 border border-base-300 py-2 px-3 text-sm font-mono overflow-x-auto"><%= Jason.encode!(@target.metadata, pretty: true) %></pre>
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
  def update(%{target: target, mission: mission} = assigns, socket) do
    changeset = Target.changeset(target, %{})

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

    # Load available databases for the mission
    available_databases = MissionDatabase.list_databases(mission.id)

    # Determine current database and version selection
    {selected_database_id, selected_definition_set_id} =
      if target.definition_set_id do
        # Target has a specific definition set - find its database
        ds = MissionDatabase.get_definition_set(target.definition_set_id)

        if ds do
          {ds.database_id, ds.id}
        else
          {nil, nil}
        end
      else
        {nil, nil}
      end

    # Load available versions for the selected database
    available_versions =
      if selected_database_id do
        MissionDatabase.list_definition_sets(selected_database_id)
      else
        []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:available_interfaces, available_interfaces)
     |> assign(:selected_interfaces, selected_interfaces)
     |> assign(:available_databases, available_databases)
     |> assign(:selected_database_id, selected_database_id)
     |> assign(:selected_definition_set_id, selected_definition_set_id)
     |> assign(:available_versions, available_versions)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"target" => target_params}, socket) do
    changeset =
      socket.assigns.target
      |> Target.changeset(target_params)
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

  def handle_event(
        "update_interface_direction",
        %{"interface-id" => interface_id, "value" => direction},
        socket
      ) do
    selected_interfaces = socket.assigns.selected_interfaces
    updated_interfaces = Map.put(selected_interfaces, interface_id, direction)
    {:noreply, assign(socket, :selected_interfaces, updated_interfaces)}
  end

  def handle_event("select_database", %{"selected_database_id" => ""}, socket) do
    {:noreply,
     socket
     |> assign(:selected_database_id, nil)
     |> assign(:selected_definition_set_id, nil)
     |> assign(:available_versions, [])}
  end

  def handle_event("select_database", %{"selected_database_id" => database_id}, socket) do
    available_versions = MissionDatabase.list_definition_sets(database_id)

    {:noreply,
     socket
     |> assign(:selected_database_id, database_id)
     |> assign(:selected_definition_set_id, nil)
     |> assign(:available_versions, available_versions)}
  end

  def handle_event("select_version", %{"definition_set_id" => ""}, socket) do
    {:noreply, assign(socket, :selected_definition_set_id, nil)}
  end

  def handle_event("select_version", %{"definition_set_id" => definition_set_id}, socket) do
    {:noreply, assign(socket, :selected_definition_set_id, definition_set_id)}
  end

  def handle_event("save", %{"target" => target_params}, socket) do
    save_target(socket, socket.assigns.action, target_params)
  end

  defp save_target(socket, :edit, target_params) do
    # Check authorization
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission

    # Add definition_set_id from selection
    target_params =
      Map.put(target_params, "definition_set_id", socket.assigns.selected_definition_set_id)

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case Targets.update_target(socket.assigns.target, target_params) do
          {:ok, target} ->
            # Sync interface associations
            sync_interface_associations(
              target,
              socket.assigns.selected_interfaces,
              socket.assigns.available_interfaces
            )

            notify_parent({:saved, target})

            {:noreply,
             socket
             |> put_flash(:info, "Target updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, reason} ->
            # Handle domain entity errors
            {:noreply,
             socket
             |> put_flash(:error, format_domain_error(reason))}
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

    # Add definition_set_id from selection
    target_params =
      Map.put(target_params, "definition_set_id", socket.assigns.selected_definition_set_id)

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        # Add mission_id to params
        params_with_mission = Map.put(target_params, "mission_id", mission.id)

        case Targets.create_target(params_with_mission) do
          {:ok, target} ->
            # Add interface associations for new target
            sync_interface_associations(
              target,
              socket.assigns.selected_interfaces,
              socket.assigns.available_interfaces
            )

            notify_parent({:saved, target})

            {:noreply,
             socket
             |> put_flash(:info, "Target created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, reason} ->
            # Handle domain entity errors
            {:noreply,
             socket
             |> put_flash(:error, format_domain_error(reason))}
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

  # Formats domain entity errors for display
  defp format_domain_error({:required, field}) do
    "#{humanize_field(field)} is required"
  end

  defp format_domain_error({:invalid, field}) do
    "#{humanize_field(field)} is invalid"
  end

  defp format_domain_error({:invalid_identifier, _}) do
    "Identifier must be uppercase alphanumeric with hyphens/underscores"
  end

  defp format_domain_error({:invalid_type, _}) do
    "Invalid target type"
  end

  defp format_domain_error({:invalid_status, _}) do
    "Invalid status"
  end

  defp format_domain_error(%{} = errors) when is_map(errors) do
    # Handle validation error maps from Ecto
    Enum.map_join(errors, "; ", fn {field, messages} ->
      "#{humanize_field(field)}: #{Enum.join(messages, ", ")}"
    end)
  end

  defp format_domain_error(error) when is_binary(error), do: error
  defp format_domain_error(error), do: "An error occurred: #{inspect(error)}"

  defp humanize_field(field) when is_atom(field) do
    field
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_field(field), do: to_string(field)

  # Returns a status label for a DefinitionSet based on its lifecycle fields
  defp version_status_label(%DefinitionSet{published_at: nil}), do: "(draft)"

  defp version_status_label(%DefinitionSet{superseded_at: ts}) when not is_nil(ts),
    do: "(deprecated)"

  defp version_status_label(%DefinitionSet{published_at: _}), do: "(published)"
end
