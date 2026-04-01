defmodule CadenceWeb.MissionLive.LinkShow do
  @moduledoc """
  LiveView for displaying and managing a single link with its channels.
  """
  use CadenceWeb, :live_view

  alias Cadence.Links
  alias Cadence.Links.Channel

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

  defp apply_action(socket, :show, %{"link_id" => link_id}) do
    load_link(socket, link_id)
    |> assign(:channel, nil)
  end

  defp apply_action(socket, :edit, %{"link_id" => link_id}) do
    load_link(socket, link_id)
    |> assign(:channel, nil)
  end

  defp apply_action(socket, :new_channel, %{"link_id" => link_id}) do
    socket = load_link(socket, link_id)

    socket
    |> assign(:channel, %Channel{link_id: socket.assigns.link.id, scid: socket.assigns.link.scid})
  end

  defp load_link(socket, link_id) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    case Links.get_link(org_id, mission.id, link_id) do
      {:ok, link} ->
        channels = Links.list_channels_for_link(org_id, mission.id, link.id)

        socket
        |> assign(:page_title, "Link: SCID #{link.scid}")
        |> assign(:link, link)
        |> assign(:channels, channels)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Link not found")
        |> push_navigate(to: ~p"/missions/#{mission}/links")
    end
  end

  @impl true
  def handle_info({CadenceWeb.LinkLive.FormComponent, {:saved, link}}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    channels = Links.list_channels_for_link(org_id, mission.id, link.id)

    {:noreply,
     socket
     |> assign(:link, link)
     |> assign(:channels, channels)}
  end

  def handle_info({CadenceWeb.ChannelLive.FormComponent, {:saved, _channel}}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    link = socket.assigns.link

    channels = Links.list_channels_for_link(org_id, mission.id, link.id)
    {:noreply, assign(socket, :channels, channels)}
  end

  @impl true
  def handle_event("delete_channel", %{"id" => channel_id}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    with :ok <- authorize_manage(socket),
         {:ok, channel} <- Links.get_channel(org_id, mission.id, channel_id),
         {:ok, _} <- Links.delete_channel(org_id, mission.id, channel) do
      channels = Links.list_channels_for_link(org_id, mission.id, socket.assigns.link.id)

      {:noreply,
       socket
       |> put_flash(:info, "Channel deleted successfully")
       |> assign(:channels, channels)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Channel not found")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete channels")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete channel")}
    end
  end

  defp authorize_manage(socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok -> :ok
      {:error, _} -> {:error, :unauthorized}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <.header>
        <div class="flex items-center gap-3">
          <span class="font-mono text-2xl font-bold">SCID {@link.scid}</span>
          <%= if @link.name do %>
            <span class="text-base-content/60">- {@link.name}</span>
          <% end %>
        </div>
        <:actions>
          <.link patch={~p"/missions/#{@mission}/links/#{@link}/edit"}>
            <.button>Edit Link</.button>
          </.link>
          <.link navigate={~p"/missions/#{@mission}/links/#{@link}/protocol"}>
            <.button variant="secondary">Protocol Config</.button>
          </.link>
          <.link navigate={~p"/missions/#{@mission}/links"}>
            <.button variant="ghost">Back to Links</.button>
          </.link>
        </:actions>
      </.header>
      
    <!-- Protocol Config Summary -->
      <div class="mt-6">
        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h3 class="card-title text-sm">
                <.icon name="hero-cog-6-tooth" class="h-4 w-4" /> Protocol Configuration
              </h3>
              <.link
                navigate={~p"/missions/#{@mission}/links/#{@link}/protocol"}
                class="link link-primary text-sm"
              >
                Configure
              </.link>
            </div>

            <%= if @link.protocol_config && @link.protocol_config.config != %{} do %>
              <dl class="grid grid-cols-2 md:grid-cols-4 gap-4 mt-4 text-sm">
                <%= for {key, value} <- @link.protocol_config.config do %>
                  <div>
                    <dt class="text-base-content/60">{humanize_key(key)}</dt>
                    <dd class="font-mono font-medium">{inspect(value)}</dd>
                  </div>
                <% end %>
              </dl>
            <% else %>
              <p class="text-sm text-base-content/50 mt-2">
                No protocol configuration. Click "Configure" to set up CCSDS/COP-1 parameters.
              </p>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Channels Section -->
      <div class="mt-8">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Channels</h3>
          <.link patch={~p"/missions/#{@mission}/links/#{@link}/channels/new"}>
            <.button>
              <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add Channel
            </.button>
          </.link>
        </div>

        <%= if @channels == [] do %>
          <div class="card bg-base-200">
            <div class="card-body text-center py-8">
              <.icon name="hero-signal" class="h-8 w-8 mx-auto text-base-content/40 mb-2" />
              <p class="text-sm text-base-content/50">No channels configured for this link.</p>
              <p class="text-xs text-base-content/40 mt-1">
                Channels define virtual channels (VCIDs) for data routing.
              </p>
            </div>
          </div>
        <% else %>
          <div class="overflow-x-auto bg-base-200 rounded-lg">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>VCID</th>
                  <th>MAP ID</th>
                  <th>Direction</th>
                  <th>Status</th>
                  <th>Bindings</th>
                  <th class="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for channel <- @channels do %>
                  <tr class="hover:bg-base-300/50">
                    <td class="font-mono font-bold">{channel.vcid}</td>
                    <td class="font-mono">
                      <%= if channel.map_id do %>
                        {channel.map_id}
                      <% else %>
                        <span class="text-base-content/40">-</span>
                      <% end %>
                    </td>
                    <td>
                      <.direction_badge direction={channel.direction} />
                    </td>
                    <td>
                      <.enabled_indicator enabled={channel.enabled} />
                    </td>
                    <td>
                      <.bindings_summary bindings={channel.bindings || []} />
                    </td>
                    <td class="text-right">
                      <.link
                        navigate={~p"/missions/#{@mission}/links/#{@link}/channels/#{channel}"}
                        class="link link-primary text-sm"
                      >
                        View
                      </.link>
                      <button
                        type="button"
                        phx-click="delete_channel"
                        phx-value-id={channel.id}
                        data-confirm="Are you sure you want to delete this channel?"
                        class="link link-error text-sm ml-2"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>

    <!-- Edit Link Modal -->
    <.modal
      :if={@live_action == :edit}
      id="edit-link-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/links/#{@link}")}
    >
      <.live_component
        module={CadenceWeb.LinkLive.FormComponent}
        id={@link.id}
        title="Edit Link"
        action={:edit}
        link={@link}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/links/#{@link}"}
      />
    </.modal>

    <!-- New Channel Modal -->
    <.modal
      :if={@live_action == :new_channel}
      id="new-channel-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/links/#{@link}")}
    >
      <.live_component
        module={CadenceWeb.ChannelLive.FormComponent}
        id={:new}
        title="New Channel"
        action={:new}
        channel={@channel}
        link={@link}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/links/#{@link}"}
      />
    </.modal>
    """
  end

  defp humanize_key(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_key(key) when is_atom(key), do: humanize_key(Atom.to_string(key))
end
