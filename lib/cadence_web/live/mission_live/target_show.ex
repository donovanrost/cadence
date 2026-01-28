defmodule CadenceWeb.MissionLive.TargetShow do
  @moduledoc """
  LiveView for displaying and managing a single target.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Interfaces, Links}

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

  defp apply_action(socket, :show, %{"target_id" => target_id}) do
    load_target(socket, target_id)
  end

  defp apply_action(socket, :edit, %{"target_id" => target_id}) do
    load_target(socket, target_id)
  end

  defp load_target(socket, target_id) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    # Get target with definition_set preloaded for display
    case get_target_with_preloads(target_id, mission.id) do
      {:ok, target} ->
        interfaces = Interfaces.list_interfaces(mission)

        socket
        |> assign(:page_title, "Target: #{target.name}")
        |> assign(:target, target)
        |> assign(:interfaces, interfaces)
        |> load_comms_data(org_id, mission, target)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Target not found")
        |> push_navigate(to: ~p"/missions/#{mission}/targets")
    end
  end

  # Loads communications data for spacecraft targets with SCID
  defp load_comms_data(socket, org_id, mission, target) do
    if target.type == "spacecraft" && target.scid do
      case Links.get_link_by_scid(org_id, mission.id, target.scid) do
        {:ok, link} ->
          channels = link.channels || []
          channel_targets = Links.list_channel_targets(org_id, mission.id, target.id)

          primary_uplink = Enum.find(channel_targets, &(&1.purpose == "primary_uplink"))
          primary_downlink = Enum.find(channel_targets, &(&1.purpose == "primary_downlink"))

          socket
          |> assign(:link, link)
          |> assign(:channels, channels)
          |> assign(:channel_targets, channel_targets)
          |> assign(:primary_uplink, primary_uplink)
          |> assign(:primary_downlink, primary_downlink)

        {:error, :not_found} ->
          socket
          |> assign(:link, nil)
          |> assign(:channels, [])
          |> assign(:channel_targets, [])
          |> assign(:primary_uplink, nil)
          |> assign(:primary_downlink, nil)
      end
    else
      socket
      |> assign(:link, nil)
      |> assign(:channels, [])
      |> assign(:channel_targets, [])
      |> assign(:primary_uplink, nil)
      |> assign(:primary_downlink, nil)
    end
  end

  # Gets target with definition_set preloaded, returns error tuple if not found
  defp get_target_with_preloads(target_id, mission_id) do
    import Ecto.Query

    alias Cadence.Repo
    alias Cadence.Targets.Target, as: TargetSchema

    query =
      from(t in TargetSchema,
        where: t.id == ^target_id and t.mission_id == ^mission_id,
        preload: [definition_set: :database]
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      target -> {:ok, target}
    end
  end

  @impl true
  def handle_info({CadenceWeb.TargetLive.FormComponent, {:saved, target}}, socket) do
    mission = socket.assigns.mission

    case get_target_with_preloads(target.id, mission.id) do
      {:ok, updated_target} ->
        {:noreply,
         socket
         |> assign(:target, updated_target)
         |> assign(:page_title, "Target: #{updated_target.name}")}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  # Real-time target status updates via PubSub
  def handle_info({:target_changed, _event_type, updated_target}, socket) do
    if updated_target.id == socket.assigns.target.id do
      # Merge status fields from the domain entity
      target = %{
        socket.assigns.target
        | status: updated_target.status,
          circuit_breaker_status: updated_target.circuit_breaker_status
      }

      {:noreply, assign(socket, :target, target)}
    else
      {:noreply, socket}
    end
  end

  # Catch-all for other PubSub events we don't handle
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <.header>
        <div class="flex items-center gap-3">
          <span class="text-2xl font-bold">{@target.name}</span>
          <.target_type_badge type={@target.type} />
        </div>
        <:actions>
          <.link patch={~p"/missions/#{@mission}/targets/#{@target}/edit"}>
            <.button>Edit Target</.button>
          </.link>
          <%= if @target.type == "spacecraft" && @target.scid do %>
            <.link navigate={~p"/missions/#{@mission}/targets/#{@target}/comms"}>
              <.button variant="secondary">
                <.icon name="hero-signal" class="h-4 w-4 mr-1" /> Communications
              </.button>
            </.link>
          <% end %>
          <.link navigate={~p"/missions/#{@mission}/targets"}>
            <.button variant="ghost">Back to Targets</.button>
          </.link>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
        <!-- Target Details Card -->
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title text-sm">
              <.icon name="hero-identification" class="h-4 w-4" /> Details
            </h3>

            <dl class="grid grid-cols-2 gap-4 mt-4 text-sm">
              <div>
                <dt class="text-base-content/60">Identifier</dt>
                <dd class="font-mono font-medium">{@target.identifier}</dd>
              </div>

              <div>
                <dt class="text-base-content/60">Type</dt>
                <dd>{humanize_type(@target.type)}</dd>
              </div>

              <%= if @target.scid do %>
                <div>
                  <dt class="text-base-content/60">SCID</dt>
                  <dd class="font-mono font-medium">{@target.scid}</dd>
                </div>
              <% end %>

              <div>
                <dt class="text-base-content/60">Status</dt>
                <dd><.status_badge status={@target.status} /></dd>
              </div>

              <div>
                <dt class="text-base-content/60">Circuit Breaker</dt>
                <dd><.circuit_breaker_badge status={@target.circuit_breaker_status} /></dd>
              </div>
            </dl>
          </div>
        </div>
        
    <!-- Definition Set Card -->
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title text-sm">
              <.icon name="hero-document-text" class="h-4 w-4" /> Command & Telemetry Database
            </h3>

            <%= if @target.definition_set do %>
              <dl class="grid grid-cols-2 gap-4 mt-4 text-sm">
                <div>
                  <dt class="text-base-content/60">Database</dt>
                  <dd class="font-medium">{@target.definition_set.database.name}</dd>
                </div>

                <div>
                  <dt class="text-base-content/60">Version</dt>
                  <dd class="font-mono">v{@target.definition_set.version}</dd>
                </div>
              </dl>
            <% else %>
              <p class="text-sm text-base-content/50 mt-4 italic">
                No database assigned to this target.
              </p>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Communications Overview Card (spacecraft with SCID only) -->
      <%= if @target.type == "spacecraft" && @target.scid do %>
        <.comms_overview_card
          target={@target}
          mission={@mission}
          link={@link}
          channels={@channels}
          primary_uplink={@primary_uplink}
          primary_downlink={@primary_downlink}
        />
      <% end %>
    </div>

    <!-- Edit Target Modal -->
    <.modal
      :if={@live_action == :edit}
      id="edit-target-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/targets/#{@target}")}
    >
      <.live_component
        module={CadenceWeb.TargetLive.FormComponent}
        id={@target.id}
        title="Edit Target"
        action={:edit}
        target={@target}
        mission={@mission}
        interfaces={@interfaces}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/targets/#{@target}"}
      />
    </.modal>
    """
  end

  defp humanize_type("spacecraft"), do: "Spacecraft"
  defp humanize_type("ground_station"), do: "Ground Station"
  defp humanize_type("simulator"), do: "Simulator"
  defp humanize_type("relay"), do: "Relay"
  defp humanize_type(type), do: type

  # Component for target type badge
  defp target_type_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      type_badge_class(@type)
    ]}>
      {@type}
    </span>
    """
  end

  defp type_badge_class("spacecraft"), do: "badge-primary"
  defp type_badge_class("ground_station"), do: "badge-secondary"
  defp type_badge_class("simulator"), do: "badge-accent"
  defp type_badge_class("relay"), do: "badge-ghost"
  defp type_badge_class(_), do: "badge-ghost"

  # Component for circuit breaker status badge
  defp circuit_breaker_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      circuit_breaker_badge_class(@status)
    ]}>
      {circuit_breaker_label(@status)}
    </span>
    """
  end

  defp circuit_breaker_badge_class(:closed), do: "badge-success"
  defp circuit_breaker_badge_class("closed"), do: "badge-success"
  defp circuit_breaker_badge_class(:open), do: "badge-error"
  defp circuit_breaker_badge_class("open"), do: "badge-error"
  defp circuit_breaker_badge_class(:half_open), do: "badge-warning"
  defp circuit_breaker_badge_class("half_open"), do: "badge-warning"
  defp circuit_breaker_badge_class(_), do: "badge-ghost"

  defp circuit_breaker_label(:closed), do: "Closed"
  defp circuit_breaker_label("closed"), do: "Closed"
  defp circuit_breaker_label(:open), do: "Open"
  defp circuit_breaker_label("open"), do: "Open"
  defp circuit_breaker_label(:half_open), do: "Half Open"
  defp circuit_breaker_label("half_open"), do: "Half Open"
  defp circuit_breaker_label(nil), do: "Unknown"
  defp circuit_breaker_label(status), do: to_string(status)

  # Communications Overview card for spacecraft targets
  attr :target, :map, required: true
  attr :mission, :map, required: true
  attr :link, :map, default: nil
  attr :channels, :list, default: []
  attr :primary_uplink, :map, default: nil
  attr :primary_downlink, :map, default: nil

  defp comms_overview_card(assigns) do
    protocol_config = if assigns.link, do: assigns.link.protocol_config, else: nil
    config = if protocol_config, do: protocol_config.config || %{}, else: %{}

    assigns =
      assigns
      |> assign(:protocol_config, protocol_config)
      |> assign(:downlink_profile, Map.get(config, "profile", "tm"))
      |> assign(:uplink_profile, Map.get(config, "uplink_profile", "tc"))
      |> assign(:frame_size, Map.get(config, "frame_size"))
      |> assign(:cop1_enabled, cop1_enabled?(config))
      |> assign(:channel_count, length(assigns.channels))

    ~H"""
    <div class="mt-6">
      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex items-center justify-between">
            <h3 class="card-title text-sm">
              <.icon name="hero-signal" class="h-4 w-4" /> Communications Overview
            </h3>
            <.link
              navigate={~p"/missions/#{@mission}/targets/#{@target}/comms"}
              class="btn btn-sm btn-ghost"
            >
              View Communications <.icon name="hero-arrow-right" class="h-4 w-4 ml-1" />
            </.link>
          </div>

          <%= if @link do %>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mt-4 text-sm">
              <div>
                <dt class="text-base-content/60 text-xs">Downlink Profile</dt>
                <dd class="font-medium uppercase">{@downlink_profile}</dd>
              </div>

              <div>
                <dt class="text-base-content/60 text-xs">Uplink Profile</dt>
                <dd class="font-medium uppercase">{@uplink_profile}</dd>
              </div>

              <div>
                <dt class="text-base-content/60 text-xs">Frame Size</dt>
                <dd class="font-mono font-medium">{@frame_size || "Not set"}</dd>
              </div>

              <div>
                <dt class="text-base-content/60 text-xs">COP-1</dt>
                <dd class={[
                  "font-medium",
                  @cop1_enabled && "text-success",
                  !@cop1_enabled && "text-base-content/50"
                ]}>
                  {if @cop1_enabled, do: "Enabled", else: "Disabled"}
                </dd>
              </div>

              <div>
                <dt class="text-base-content/60 text-xs">Channels</dt>
                <dd class="font-medium">{@channel_count}</dd>
              </div>

              <div>
                <dt class="text-base-content/60 text-xs">Primary Channels</dt>
                <dd class="font-mono text-xs">
                  <span :if={@primary_uplink} class="mr-2">
                    <.icon name="hero-arrow-up" class="h-3 w-3 inline" /> VCID {@primary_uplink.vcid}
                  </span>
                  <span :if={@primary_downlink}>
                    <.icon name="hero-arrow-down" class="h-3 w-3 inline" />
                    VCID {@primary_downlink.vcid}
                  </span>
                  <span :if={!@primary_uplink && !@primary_downlink} class="text-base-content/50">
                    Not set
                  </span>
                </dd>
              </div>
            </div>
          <% else %>
            <p class="text-sm text-base-content/50 mt-4 italic">
              Communications link not yet configured for SCID {@target.scid}.
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp cop1_enabled?(config) do
    window_size = Map.get(config, "cop1_window_size")
    is_integer(window_size) and window_size > 0
  end
end
