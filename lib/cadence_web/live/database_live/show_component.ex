defmodule CadenceWeb.DatabaseLive.ShowComponent do
  use CadenceWeb, :live_component

  alias Cadence.MissionDatabase
  alias Cadence.MissionDatabase.DefinitionSet

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Database Version <%= @definition_set.version %>
        <:subtitle>
          <.version_badge definition_set={@definition_set} is_active={@is_active} />
        </:subtitle>
        <:actions>
          <%= if !@is_active and is_nil(@definition_set.published_at) do %>
            <.button phx-click="publish_database" phx-target={@myself}>
              Publish
            </.button>
            <.button
              phx-click="delete_database"
              phx-target={@myself}
              data-confirm="Are you sure you want to delete this database version?"
              class="btn-error"
            >
              Delete
            </.button>
          <% end %>
        </:actions>
      </.header>

      <div class="mt-6 grid grid-cols-2 gap-4 text-sm">
        <div>
          <span class="text-base-content/60">Description</span>
          <p class="mt-1"><%= @definition_set.description || "No description" %></p>
        </div>
        <div>
          <span class="text-base-content/60">Source Format</span>
          <p class="mt-1"><%= @definition_set.source_format %></p>
        </div>
        <div>
          <span class="text-base-content/60">Created</span>
          <p class="mt-1"><%= format_datetime(@definition_set.inserted_at) %></p>
        </div>
        <div>
          <span class="text-base-content/60">Published</span>
          <p class="mt-1"><%= format_datetime(@definition_set.published_at) || "Not published" %></p>
        </div>
        <%= if @definition_set.superseded_at do %>
          <div>
            <span class="text-base-content/60">Superseded</span>
            <p class="mt-1"><%= format_datetime(@definition_set.superseded_at) %></p>
          </div>
        <% end %>
      </div>

      <div class="divider"></div>

      <!-- Stats -->
      <div class="stats stats-horizontal shadow w-full">
        <div class="stat">
          <div class="stat-title">Containers</div>
          <div class="stat-value text-2xl"><%= @stats.container_count %></div>
        </div>
        <div class="stat">
          <div class="stat-title">Parameters</div>
          <div class="stat-value text-2xl"><%= @stats.parameter_count %></div>
        </div>
        <div class="stat">
          <div class="stat-title">Commands</div>
          <div class="stat-value text-2xl"><%= @stats.command_count %></div>
        </div>
      </div>

      <!-- Containers (Packets) -->
      <%= if @containers != [] do %>
        <div class="mt-8">
          <h3 class="text-lg font-semibold mb-4">Packet Definitions</h3>
          <div class="space-y-2">
            <%= for container <- @containers do %>
              <details class="collapse collapse-arrow bg-base-200">
                <summary class="collapse-title">
                  <div class="flex items-center gap-4">
                    <span class="font-medium font-mono"><%= container.name %></span>
                    <%= if container.apid do %>
                      <span class="text-sm text-base-content/60">APID: <%= container.apid %></span>
                    <% end %>
                    <span class="text-sm text-base-content/50">
                      <%= length(container.container_entries) %> items
                    </span>
                  </div>
                </summary>
                <div class="collapse-content">
                  <%= if container.description do %>
                    <p class="text-sm text-base-content/70 mb-4"><%= container.description %></p>
                  <% end %>
                  <div class="overflow-x-auto">
                    <table class="table table-xs">
                      <thead>
                        <tr>
                          <th>Name</th>
                          <th>Offset</th>
                          <th>Size</th>
                          <th>Type</th>
                          <th>Units</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for entry <- Enum.sort_by(container.container_entries, & &1.bit_offset) do %>
                          <tr>
                            <td class="font-mono"><%= entry.parameter && entry.parameter.name %></td>
                            <td><%= entry.bit_offset %></td>
                            <td><%= get_size_in_bits(entry.parameter) %></td>
                            <td><%= get_data_type(entry.parameter) %></td>
                            <td><%= get_units(entry.parameter) || "—" %></td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                </div>
              </details>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Commands -->
      <%= if @commands != [] do %>
        <div class="mt-8">
          <h3 class="text-lg font-semibold mb-4">Command Definitions</h3>
          <div class="space-y-2">
            <%= for command <- @commands do %>
              <details class="collapse collapse-arrow bg-base-200">
                <summary class="collapse-title">
                  <div class="flex items-center gap-4">
                    <span class="font-medium font-mono"><%= command.name %></span>
                    <%= if command.opcode do %>
                      <span class="text-sm text-base-content/60">
                        Opcode: 0x<%= Integer.to_string(command.opcode, 16) %>
                      </span>
                    <% end %>
                    <%= if command.is_hazardous do %>
                      <span class="badge badge-error badge-sm">Hazardous</span>
                    <% end %>
                    <span class="text-sm text-base-content/50">
                      <%= length(command.arguments) %> args
                    </span>
                  </div>
                </summary>
                <div class="collapse-content">
                  <%= if command.description do %>
                    <p class="text-sm text-base-content/70 mb-4"><%= command.description %></p>
                  <% end %>
                  <%= if command.is_hazardous && command.hazard_description do %>
                    <div class="alert alert-warning mb-4">
                      <.icon name="hero-exclamation-triangle" class="h-4 w-4" />
                      <span><%= command.hazard_description %></span>
                    </div>
                  <% end %>
                  <%= if command.arguments != [] do %>
                    <div class="overflow-x-auto">
                      <table class="table table-xs">
                        <thead>
                          <tr>
                            <th>Argument</th>
                            <th>Type</th>
                            <th>Required</th>
                            <th>Default</th>
                          </tr>
                        </thead>
                        <tbody>
                          <%= for arg <- command.arguments do %>
                            <tr>
                              <td class="font-mono"><%= arg.name %></td>
                              <td><%= arg.data_type_ref %></td>
                              <td>
                                <%= if arg.required do %>
                                  <span class="badge badge-xs badge-primary">Yes</span>
                                <% else %>
                                  <span class="text-base-content/50">No</span>
                                <% end %>
                              </td>
                              <td class="font-mono text-base-content/60"><%= arg.default_value || "—" %></td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    </div>
                  <% else %>
                    <p class="text-sm text-base-content/50">No arguments</p>
                  <% end %>
                </div>
              </details>
            <% end %>
          </div>
        </div>
      <% end %>

      <div class="mt-8">
        <.link patch={@patch} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="h-4 w-4 mr-1" />
          Back
        </.link>
      </div>
    </div>
    """
  end

  attr :definition_set, :map, required: true
  attr :is_active, :boolean, required: true

  defp version_badge(assigns) do
    ~H"""
    <%= cond do %>
      <% @is_active -> %>
        <span class="badge badge-success">Active</span>
      <% @definition_set.published_at && @definition_set.superseded_at -> %>
        <span class="badge badge-ghost">Superseded</span>
      <% true -> %>
        <span class="badge badge-warning">Draft</span>
    <% end %>
    """
  end

  @impl true
  def update(assigns, socket) do
    definition_set_id = assigns[:id]

    # Load the definition set with associations
    case DefinitionSet.load_complete(definition_set_id) do
      {:ok, definition_set} ->
        is_active = DefinitionSet.active?(definition_set)

        # Calculate stats
        stats = %{
          container_count: length(definition_set.containers || []),
          parameter_count: length(definition_set.parameters || []),
          command_count: length(definition_set.meta_commands || [])
        }

        # Filter out abstract containers
        containers =
          (definition_set.containers || [])
          |> Enum.reject(& &1.abstract)
          |> Enum.sort_by(& &1.name)

        # Filter out abstract commands
        commands =
          (definition_set.meta_commands || [])
          |> Enum.reject(& &1.abstract)
          |> Enum.sort_by(& &1.name)

        {:ok,
         socket
         |> assign(assigns)
         |> assign(:definition_set, definition_set)
         |> assign(:is_active, is_active)
         |> assign(:stats, stats)
         |> assign(:containers, containers)
         |> assign(:commands, commands)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(assigns)
         |> assign(:definition_set, nil)
         |> assign(:is_active, false)
         |> assign(:stats, %{container_count: 0, parameter_count: 0, command_count: 0})
         |> assign(:containers, [])
         |> assign(:commands, [])}
    end
  end

  @impl true
  def handle_event("publish_database", _params, socket) do
    definition_set = socket.assigns.definition_set
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case DefinitionSet.publish(definition_set) do
          {:ok, published} ->
            notify_parent({:published, published})

            {:noreply,
             socket
             |> put_flash(:info, "Database v#{published.version} is now active")
             |> push_patch(to: socket.assigns.patch)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to publish: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to publish databases")}
    end
  end

  def handle_event("delete_database", _params, socket) do
    definition_set = socket.assigns.definition_set
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case Cadence.Repo.delete(definition_set) do
          {:ok, _} ->
            notify_parent({:deleted, definition_set})

            {:noreply,
             socket
             |> put_flash(:info, "Database deleted successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to delete: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete databases")}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp format_datetime(nil), do: nil

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp get_units(nil), do: nil

  defp get_units(parameter) do
    case parameter.data_type do
      nil -> nil
      data_type ->
        case data_type.unit do
          nil -> nil
          unit -> unit.symbol || unit.name
        end
    end
  end

  defp get_size_in_bits(nil), do: "—"

  defp get_size_in_bits(parameter) do
    case parameter.data_type do
      nil -> "—"
      %{encoding: %{size_in_bits: size}} when not is_nil(size) -> size
      _ -> "—"
    end
  end

  defp get_data_type(nil), do: "—"

  defp get_data_type(parameter) do
    case parameter.data_type do
      nil -> "—"
      %{base_type: base_type} when not is_nil(base_type) -> base_type
      %{name: name} -> name
      _ -> "—"
    end
  end
end
