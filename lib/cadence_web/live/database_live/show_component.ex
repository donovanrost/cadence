defmodule CadenceWeb.DatabaseLive.ShowComponent do
  use CadenceWeb, :live_component

  alias Cadence.Databases

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Database: <%= @definition_set.version %>
        <:subtitle>
          <%= if @is_active do %>
            <span class="inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20">
              Active
            </span>
          <% else %>
            <%= if @definition_set.published_at do %>
              <span class="inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10">
                Superseded
              </span>
            <% else %>
              <span class="inline-flex items-center rounded-md bg-yellow-50 px-2 py-1 text-xs font-medium text-yellow-700 ring-1 ring-inset ring-yellow-600/20">
                Draft
              </span>
            <% end %>
          <% end %>
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
              class="bg-red-600 hover:bg-red-700"
            >
              Delete
            </.button>
          <% end %>
        </:actions>
      </.header>

      <.list class="mt-6">
        <:item title="Version"><%= @definition_set.version %></:item>
        <:item title="Description"><%= @definition_set.description || "N/A" %></:item>
        <:item title="Source Format"><%= @definition_set.source_format %></:item>
        <:item title="Packets"><%= @stats.packet_count %></:item>
        <:item title="Total Items"><%= @stats.item_count %></:item>
        <:item title="Created">
          <%= Calendar.strftime(@definition_set.inserted_at, "%Y-%m-%d %H:%M:%S UTC") %>
        </:item>
        <:item title="Published">
          <%= if @definition_set.published_at do %>
            <%= Calendar.strftime(@definition_set.published_at, "%Y-%m-%d %H:%M:%S UTC") %>
          <% else %>
            Not published
          <% end %>
        </:item>
        <:item title="Superseded">
          <%= if @definition_set.superseded_at do %>
            <%= Calendar.strftime(@definition_set.superseded_at, "%Y-%m-%d %H:%M:%S UTC") %>
          <% else %>
            N/A
          <% end %>
        </:item>
      </.list>

      <.header class="mt-8">
        Packet Definitions
      </.header>

      <div class="mt-4 space-y-4">
        <%= for packet <- @definition_set.packet_definitions do %>
          <details class="group border border-zinc-200 rounded-lg">
            <summary class="flex items-center justify-between p-4 cursor-pointer hover:bg-zinc-50">
              <div class="flex items-center gap-4">
                <span class="font-medium text-zinc-900"><%= packet.name %></span>
                <%= if packet.apid do %>
                  <span class="text-sm text-zinc-500">APID: <%= packet.apid %></span>
                <% end %>
                <%= if packet.packet_id do %>
                  <span class="text-sm text-zinc-500">ID: <%= packet.packet_id %></span>
                <% end %>
              </div>
              <div class="flex items-center gap-4">
                <span class="text-sm text-zinc-500">
                  <%= length(packet.packet_items) %> items
                </span>
                <svg
                  class="h-5 w-5 text-zinc-400 transition-transform group-open:rotate-180"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 9l-7 7-7-7"
                  />
                </svg>
              </div>
            </summary>
            <div class="border-t border-zinc-200 p-4">
              <%= if packet.description do %>
                <p class="text-sm text-zinc-600 mb-4"><%= packet.description %></p>
              <% end %>
              <table class="min-w-full divide-y divide-zinc-200">
                <thead>
                  <tr>
                    <th class="py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Name
                    </th>
                    <th class="py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Offset
                    </th>
                    <th class="py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Size
                    </th>
                    <th class="py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Type
                    </th>
                    <th class="py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Units
                    </th>
                    <th class="py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Description
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-zinc-100">
                  <%= for item <- Enum.sort_by(packet.packet_items, & &1.bit_offset) do %>
                    <tr>
                      <td class="py-2 text-sm font-mono text-zinc-900"><%= item.name %></td>
                      <td class="py-2 text-sm text-zinc-600"><%= item.bit_offset %></td>
                      <td class="py-2 text-sm text-zinc-600"><%= item.bit_size %></td>
                      <td class="py-2 text-sm text-zinc-600"><%= item.data_type %></td>
                      <td class="py-2 text-sm text-zinc-600"><%= item.units || "-" %></td>
                      <td class="py-2 text-sm text-zinc-500"><%= item.description || "-" %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </details>
        <% end %>
      </div>

      <div class="mt-8">
        <.link
          patch={@patch}
          class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
        >
          &larr; Back to mission
        </.link>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    definition_set = assigns.definition_set
    stats = Databases.definition_set_stats(definition_set)
    is_active = Databases.is_active?(definition_set)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:stats, stats)
     |> assign(:is_active, is_active)}
  end

  @impl true
  def handle_event("publish_database", _params, socket) do
    definition_set = socket.assigns.definition_set
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case Databases.publish_definition_set(definition_set) do
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
        case Databases.delete_definition_set(definition_set) do
          {:ok, _} ->
            notify_parent({:deleted, definition_set})

            {:noreply,
             socket
             |> put_flash(:info, "Database deleted successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, :cannot_delete_published} ->
            {:noreply,
             put_flash(socket, :error, "Cannot delete a published database version")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to delete: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete databases")}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
