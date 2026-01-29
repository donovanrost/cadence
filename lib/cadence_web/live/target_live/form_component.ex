defmodule CadenceWeb.TargetLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.{MissionDatabase, Targets}
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
          field={@form[:scid]}
          type="number"
          label="SCID (Spacecraft ID)"
          placeholder="0"
        />
        <p class="mt-2 text-sm text-base-content/60">
          Required for spacecraft targets. Valid range: 0-1023.
        </p>

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

    # Load available databases for the mission
    available_databases = MissionDatabase.list_databases(mission.id)

    # Determine current database and version selection
    {selected_database_id, selected_definition_set_id} =
      load_selected_definition_set(target)

    # Load available versions for the selected database
    available_versions = load_available_versions(selected_database_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:available_databases, available_databases)
     |> assign(:selected_database_id, selected_database_id)
     |> assign(:selected_definition_set_id, selected_definition_set_id)
     |> assign(:available_versions, available_versions)
     |> assign_form(changeset)}
  end

  defp load_selected_definition_set(%{definition_set_id: nil}), do: {nil, nil}

  defp load_selected_definition_set(target) do
    ds = MissionDatabase.get_definition_set(target.definition_set_id)
    if ds, do: {ds.database_id, ds.id}, else: {nil, nil}
  end

  defp load_available_versions(nil), do: []

  defp load_available_versions(selected_database_id) do
    MissionDatabase.list_definition_sets(selected_database_id)
  end

  @impl true
  def handle_event("validate", %{"target" => target_params}, socket) do
    changeset =
      socket.assigns.target
      |> Target.changeset(target_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
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
