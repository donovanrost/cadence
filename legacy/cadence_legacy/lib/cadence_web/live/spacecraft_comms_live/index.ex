defmodule CadenceWeb.SpacecraftCommsLive.Index do
  @moduledoc """
  LiveView for spacecraft-centric communications configuration.

  This page provides a target-centric view of communications, showing:
  - Protocol defaults for the link
  - All channels for this spacecraft (SCID)
  - Primary channel mappings for uplink/downlink
  """
  use CadenceWeb, :live_view

  alias Cadence.{Links, Targets, Transports}
  alias Cadence.Links.Channel

  import CadenceWeb.SpacecraftCommsComponents

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

  defp apply_action(socket, :index, params) do
    load_data(socket, params)
    |> assign(:channel, nil)
  end

  defp apply_action(socket, :edit_protocol, params) do
    load_data(socket, params)
    |> assign(:channel, nil)
  end

  defp apply_action(socket, :new_channel, params) do
    socket = load_data(socket, params)
    link = socket.assigns.link

    if link do
      assign(socket, :channel, %Channel{link_id: link.id, scid: link.scid})
    else
      socket
    end
  end

  defp apply_action(socket, :edit_primary, params) do
    load_data(socket, params)
    |> assign(:channel, nil)
  end

  defp load_data(socket, %{"target_id" => target_id}) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    case Targets.get_target(target_id, mission.id) do
      {:ok, target} ->
        load_link_for_target(socket, org_id, mission.id, target)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Target not found")
        |> push_navigate(to: ~p"/missions/#{mission}/targets")
    end
  end

  defp load_link_for_target(socket, org_id, mission_id, target) do
    if target.scid do
      case Links.get_link_by_scid(org_id, mission_id, target.scid) do
        {:ok, link} ->
          channels = Links.list_channels_for_link(org_id, mission_id, link.id)
          channel_targets = Links.list_channel_targets(org_id, mission_id, target.id)
          interfaces = Transports.list_interfaces(org_id, mission_id)

          primary_uplink = find_primary(channel_targets, "primary_uplink")
          primary_downlink = find_primary(channel_targets, "primary_downlink")

          socket
          |> assign(:page_title, "Communications - #{target.name}")
          |> assign(:target, target)
          |> assign(:link, link)
          |> assign(:channels, channels)
          |> assign(:channel_targets, channel_targets)
          |> assign(:interfaces, interfaces)
          |> assign(:protocol_config, link.protocol_config)
          |> assign(:primary_uplink, primary_uplink)
          |> assign(:primary_downlink, primary_downlink)

        {:error, :not_found} ->
          # No link exists for this SCID
          socket
          |> assign(:page_title, "Communications - #{target.name}")
          |> assign(:target, target)
          |> assign(:link, nil)
          |> assign(:channels, [])
          |> assign(:channel_targets, [])
          |> assign(:interfaces, [])
          |> assign(:protocol_config, nil)
          |> assign(:primary_uplink, nil)
          |> assign(:primary_downlink, nil)
      end
    else
      # Target has no SCID
      socket
      |> assign(:page_title, "Communications - #{target.name}")
      |> assign(:target, target)
      |> assign(:link, nil)
      |> assign(:channels, [])
      |> assign(:channel_targets, [])
      |> assign(:interfaces, [])
      |> assign(:protocol_config, nil)
      |> assign(:primary_uplink, nil)
      |> assign(:primary_downlink, nil)
    end
  end

  defp find_primary(channel_targets, purpose) do
    Enum.find(channel_targets, &(&1.purpose == purpose))
  end

  @impl true
  def handle_info({CadenceWeb.ChannelLive.FormComponent, {:saved, _channel}}, socket) do
    socket = reload_channels(socket)
    {:noreply, socket}
  end

  def handle_info({CadenceWeb.LinkLive.ProtocolConfigComponent, {:config_saved, _config}}, socket) do
    socket = reload_protocol_config(socket)
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_primary_uplink", %{"primary_uplink_channel" => channel_id}, socket) do
    handle_set_primary(socket, "primary_uplink", channel_id)
  end

  def handle_event("set_primary_downlink", %{"primary_downlink_channel" => channel_id}, socket) do
    handle_set_primary(socket, "primary_downlink", channel_id)
  end

  def handle_event("delete_channel", %{"id" => channel_id}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    with :ok <- authorize_manage(socket),
         {:ok, channel} <- Links.get_channel(org_id, mission.id, channel_id),
         {:ok, _} <- Links.delete_channel(org_id, mission.id, channel) do
      {:noreply,
       socket
       |> put_flash(:info, "Channel deleted successfully")
       |> reload_channels()}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Channel not found")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete channels")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete channel")}
    end
  end

  defp handle_set_primary(socket, purpose, "") do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    target = socket.assigns.target

    with :ok <- authorize_manage(socket),
         :ok <- Links.delete_primary_channel(org_id, mission.id, target.id, purpose) do
      {:noreply, reload_channel_targets(socket)}
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to change settings")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update primary channel")}
    end
  end

  defp handle_set_primary(socket, purpose, channel_id) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    target = socket.assigns.target

    with :ok <- authorize_manage(socket),
         {:ok, _} <-
           Links.upsert_primary_channel(org_id, mission.id, target.id, purpose, channel_id) do
      {:noreply, reload_channel_targets(socket)}
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to change settings")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update primary channel")}
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

  defp reload_channels(socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    link = socket.assigns.link

    if link do
      channels = Links.list_channels_for_link(org_id, mission.id, link.id)
      assign(socket, :channels, channels)
    else
      socket
    end
  end

  defp reload_protocol_config(socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    link = socket.assigns.link

    if link do
      case Links.get_protocol_config_for_link(org_id, mission.id, link.id) do
        {:ok, config} -> assign(socket, :protocol_config, config)
        {:error, :not_found} -> assign(socket, :protocol_config, nil)
      end
    else
      socket
    end
  end

  defp reload_channel_targets(socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    target = socket.assigns.target

    channel_targets = Links.list_channel_targets(org_id, mission.id, target.id)
    primary_uplink = find_primary(channel_targets, "primary_uplink")
    primary_downlink = find_primary(channel_targets, "primary_downlink")

    socket
    |> assign(:channel_targets, channel_targets)
    |> assign(:primary_uplink, primary_uplink)
    |> assign(:primary_downlink, primary_downlink)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <.header>
        Communications
        <:subtitle>
          Configure spacecraft communications for {@target.name}
          <%= if @link do %>
            <span class="text-base-content/60">(SCID: {@link.scid})</span>
          <% end %>
        </:subtitle>
        <:actions>
          <.link navigate={~p"/missions/#{@mission}/targets"}>
            <.button variant="ghost">Back to Targets</.button>
          </.link>
        </:actions>
      </.header>

      <%= if @link do %>
        <div class="mt-6 space-y-6">
          <!-- Protocol Configuration Section -->
          <%= if @live_action == :edit_protocol do %>
            <div>
              <div class="flex items-center justify-between mb-3">
                <h2 class="text-lg font-semibold">Protocol Configuration</h2>
                <.link patch={~p"/missions/#{@mission}/targets/#{@target}/comms"}>
                  <.button variant="ghost" class="btn-sm">
                    <.icon name="hero-x-mark" class="h-4 w-4 mr-1" /> Cancel
                  </.button>
                </.link>
              </div>
              <.live_component
                module={CadenceWeb.LinkLive.ProtocolConfigComponent}
                id={:protocol_config}
                link={@link}
                mission={@mission}
                current_scope={@current_scope}
              />
            </div>
          <% else %>
            <div>
              <div class="flex items-center justify-between mb-3">
                <h2 class="text-lg font-semibold">Protocol Configuration</h2>
                <.link patch={~p"/missions/#{@mission}/targets/#{@target}/comms/protocol"}>
                  <.button variant="ghost" class="btn-sm">
                    <.icon name="hero-pencil-square" class="h-4 w-4 mr-1" /> Edit Protocol
                  </.button>
                </.link>
              </div>
              <.protocol_summary_card protocol_config={@protocol_config} />
            </div>
          <% end %>
          
    <!-- Channels Section -->
          <div>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Virtual Channels</h2>
              <.link patch={~p"/missions/#{@mission}/targets/#{@target}/comms/channels/new"}>
                <.button>
                  <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add Channel
                </.button>
              </.link>
            </div>
            <.channels_table
              channels={@channels}
              mission={@mission}
              target={@target}
              on_delete="delete_channel"
            />
          </div>
          
    <!-- Primary Channel Mappings -->
          <div>
            <h2 class="text-lg font-semibold mb-3">Primary Channels</h2>
            <.primary_channel_selector
              channels={@channels}
              primary_uplink={@primary_uplink}
              primary_downlink={@primary_downlink}
            />
          </div>
        </div>
      <% else %>
        <div class="mt-6">
          <.no_comms_configured target={@target} mission={@mission} />
        </div>
      <% end %>
    </div>

    <!-- New Channel Modal -->
    <.modal
      :if={@live_action == :new_channel && @link}
      id="new-channel-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/targets/#{@target}/comms")}
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
        patch={~p"/missions/#{@mission}/targets/#{@target}/comms"}
      />
    </.modal>
    """
  end
end
