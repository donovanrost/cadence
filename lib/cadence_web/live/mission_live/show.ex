defmodule CadenceWeb.MissionLive.Show do
  @moduledoc """
  Mission overview page - provides a dashboard view of mission status and quick access to sub-pages.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Alarms, Interfaces, MissionDatabase, Missions, Targets}
  alias Cadence.Interfaces.Events.InterfaceConnectionEvent
  alias Cadence.Telemetry.Database.DerivedItem

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _, socket) do
    # Mission is already loaded by the on_mount hook
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

  defp apply_action(socket, :show, _params) do
    mission = socket.assigns.mission

    # Subscribe to real-time updates for dashboard
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "targets:#{mission.id}")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:events")
    end

    # Load summary counts for the overview cards
    targets = Targets.list_targets(mission)
    interfaces = Interfaces.list_interfaces(mission)
    databases = MissionDatabase.list_databases(mission.id)
    derived_items = DerivedItem.list_all(mission.id)
    alarm_rules = Alarms.list_rules(mission.organization_id, mission_id: mission.id)

    # Calculate summary stats
    targets_online = Enum.count(targets, &(&1.status == :online))
    interfaces_connected = Enum.count(interfaces, &(&1.status == "connected"))

    # Get active definition set from first database with one
    active_definition_set =
      databases
      |> Enum.find_value(fn db ->
        MissionDatabase.get_latest_definition_set(db.id)
      end)

    enabled_alarms = Enum.count(alarm_rules, & &1.enabled)

    # Build interface connection status map
    interface_connection_status =
      Enum.reduce(interfaces, %{}, fn interface, acc ->
        Map.put(acc, interface.id, %{state: :unknown, client_count: 0})
      end)

    socket
    |> assign(:page_title, mission.name)
    |> assign(:targets, targets)
    |> assign(:targets_online, targets_online)
    |> assign(:interfaces, interfaces)
    |> assign(:interfaces_connected, interfaces_connected)
    |> assign(:interface_connection_status, interface_connection_status)
    |> assign(:databases, databases)
    |> assign(:active_definition_set, active_definition_set)
    |> assign(:derived_items_count, length(derived_items))
    |> assign(:alarm_rules, alarm_rules)
    |> assign(:enabled_alarms, enabled_alarms)
  end

  defp apply_action(socket, :edit, _params) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission) do
      :ok ->
        # Load the same data as :show plus set up for editing
        socket = apply_action(socket, :show, %{})

        socket
        |> assign(:page_title, "Edit #{mission.name}")

      {:error, _} ->
        socket
        |> put_flash(:error, "You don't have permission to edit this mission")
        |> push_patch(to: ~p"/missions/#{mission}")
    end
  end

  @impl true
  def handle_event("start_mission", _params, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage, scope, mission) do
      :ok ->
        case Missions.request_start(mission.id, mission.organization_id) do
          {:ok, _mission} ->
            {:noreply,
             socket
             |> put_flash(:info, "Mission start requested successfully")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to request mission start: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to start this mission")}
    end
  end

  @impl true
  def handle_event("stop_mission", _params, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage, scope, mission) do
      :ok ->
        case Missions.request_stop(mission.id, mission.organization_id) do
          {:ok, _mission} ->
            {:noreply,
             socket
             |> put_flash(:info, "Mission stop requested successfully")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to request mission stop: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to stop this mission")}
    end
  end

  # Real-time target status updates
  @impl true
  def handle_info({:target_changed, _event_type, updated_target}, socket) do
    # Update the target in the list and recalculate online count
    targets =
      Enum.map(socket.assigns.targets, fn target ->
        if target.id == updated_target.id do
          %{target | status: updated_target.status}
        else
          target
        end
      end)

    targets_online = Enum.count(targets, &(&1.status == :online))

    {:noreply,
     socket
     |> assign(:targets, targets)
     |> assign(:targets_online, targets_online)}
  end

  # Real-time interface connection status updates
  def handle_info({:interface_connection_event, %InterfaceConnectionEvent{} = event}, socket) do
    interface_connection_status =
      Map.put(
        socket.assigns[:interface_connection_status] || %{},
        event.interface_id,
        %{state: event.new_state, client_count: event.client_count}
      )

    # Recalculate connected count based on real-time status
    interfaces_connected =
      Enum.count(socket.assigns.interfaces, fn interface ->
        conn_status = Map.get(interface_connection_status, interface.id, %{state: :disconnected})
        conn_status.state == :connected
      end)

    {:noreply,
     socket
     |> assign(:interface_connection_status, interface_connection_status)
     |> assign(:interfaces_connected, interfaces_connected)}
  end

  # Catch-all for other PubSub events
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <!-- Mission Header -->
    <div class="mb-8">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-base-content">{@mission.name}</h1>
          <p class="mt-1 text-sm text-base-content/60">{@mission.description || "No description"}</p>
        </div>
        <div class="flex items-center gap-3">
          <span class={[
            "inline-flex items-center rounded-full px-3 py-1 text-sm font-medium",
            @mission.status == "active" && "bg-success/20 text-success",
            @mission.status == "inactive" && "bg-base-300 text-base-content/60",
            @mission.status == "suspended" && "bg-error/20 text-error"
          ]}>
            {@mission.status}
          </span>
          <.button
            :if={@mission.status == "active"}
            phx-click="start_mission"
            class="btn-success btn-sm"
          >
            <.icon name="hero-play" class="h-4 w-4 mr-1" /> Start
          </.button>
          <.button phx-click="stop_mission" class="btn-ghost btn-sm">
            <.icon name="hero-stop" class="h-4 w-4 mr-1" /> Stop
          </.button>
          <.link patch={~p"/missions/#{@mission}/show/edit"}>
            <.button class="btn-ghost btn-sm">
              <.icon name="hero-pencil" class="h-4 w-4 mr-1" /> Edit
            </.button>
          </.link>
        </div>
      </div>
    </div>

    <!-- Status Cards Grid -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
      <!-- Targets Card -->
      <.link navigate={~p"/missions/#{@mission}/targets"} class="block">
        <div class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer">
          <div class="card-body p-4">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-base-content/60">Targets</p>
                <p class="text-2xl font-bold">
                  <span class="text-success">{@targets_online}</span>
                  <span class="text-base-content/40">/</span>
                  <span>{length(@targets)}</span>
                </p>
                <p class="text-xs text-base-content/50">online</p>
              </div>
              <div class="rounded-full bg-primary/10 p-3">
                <.icon name="hero-cpu-chip" class="h-6 w-6 text-primary" />
              </div>
            </div>
          </div>
        </div>
      </.link>
      
    <!-- Interfaces Card -->
      <.link navigate={~p"/missions/#{@mission}/interfaces"} class="block">
        <div class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer">
          <div class="card-body p-4">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-base-content/60">Interfaces</p>
                <p class="text-2xl font-bold">
                  <span class="text-success">{@interfaces_connected}</span>
                  <span class="text-base-content/40">/</span>
                  <span>{length(@interfaces)}</span>
                </p>
                <p class="text-xs text-base-content/50">connected</p>
              </div>
              <div class="rounded-full bg-secondary/10 p-3">
                <.icon name="hero-signal" class="h-6 w-6 text-secondary" />
              </div>
            </div>
          </div>
        </div>
      </.link>
      
    <!-- Database Card -->
      <.link navigate={~p"/missions/#{@mission}/database"} class="block">
        <div class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer">
          <div class="card-body p-4">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-base-content/60">Database</p>
                <%= if @active_definition_set do %>
                  <p class="text-2xl font-bold">v{@active_definition_set.version}</p>
                  <p class="text-xs text-base-content/50">
                    {length(@databases)} {ngettext("database", "databases", length(@databases))}, {@derived_items_count} derived
                  </p>
                <% else %>
                  <p class="text-2xl font-bold text-base-content/40">-</p>
                  <p class="text-xs text-base-content/50">no active database</p>
                <% end %>
              </div>
              <div class="rounded-full bg-accent/10 p-3">
                <.icon name="hero-chart-bar" class="h-6 w-6 text-accent" />
              </div>
            </div>
          </div>
        </div>
      </.link>
      
    <!-- Alarms Card -->
      <.link navigate={~p"/missions/#{@mission}/alarms"} class="block">
        <div class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer">
          <div class="card-body p-4">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-base-content/60">Alarm Rules</p>
                <p class="text-2xl font-bold">
                  <span class="text-success">{@enabled_alarms}</span>
                  <span class="text-base-content/40">/</span>
                  <span>{length(@alarm_rules)}</span>
                </p>
                <p class="text-xs text-base-content/50">enabled</p>
              </div>
              <div class="rounded-full bg-warning/10 p-3">
                <.icon name="hero-bell-alert" class="h-6 w-6 text-warning" />
              </div>
            </div>
          </div>
        </div>
      </.link>
    </div>

    <!-- Quick Info Section -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Mission Details -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">Mission Details</h2>
          <div class="divide-y divide-base-300">
            <div class="py-3 flex justify-between">
              <span class="text-base-content/60">Slug</span>
              <span class="font-mono text-sm">{@mission.slug}</span>
            </div>
            <div class="py-3 flex justify-between">
              <span class="text-base-content/60">Phase</span>
              <span>{@mission.phase || "Not set"}</span>
            </div>
            <div class="py-3 flex justify-between">
              <span class="text-base-content/60">Start Date</span>
              <span>
                {if @mission.start_date,
                  do: Calendar.strftime(@mission.start_date, "%Y-%m-%d %H:%M"),
                  else: "Not set"}
              </span>
            </div>
            <div class="py-3 flex justify-between">
              <span class="text-base-content/60">End Date</span>
              <span>
                {if @mission.end_date,
                  do: Calendar.strftime(@mission.end_date, "%Y-%m-%d %H:%M"),
                  else: "Not set"}
              </span>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Recent Targets -->
      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex items-center justify-between mb-2">
            <h2 class="card-title text-lg">Targets</h2>
            <.link
              navigate={~p"/missions/#{@mission}/targets"}
              class="text-sm text-primary hover:underline"
            >
              View all
            </.link>
          </div>
          <%= if Enum.empty?(@targets) do %>
            <p class="text-base-content/50 text-sm py-4">No targets configured</p>
          <% else %>
            <div class="space-y-2">
              <%= for target <- Enum.take(@targets, 5) do %>
                <div class="flex items-center justify-between py-2">
                  <div class="flex items-center gap-3">
                    <span class={[
                      "w-2 h-2 rounded-full",
                      target.status == "online" && "bg-success",
                      target.status == "offline" && "bg-base-content/30",
                      target.status == "standby" && "bg-warning",
                      target.status == "fault" && "bg-error"
                    ]}>
                    </span>
                    <div>
                      <p class="font-medium text-sm">{target.name}</p>
                      <p class="text-xs text-base-content/50">{target.identifier}</p>
                    </div>
                  </div>
                  <span class="text-xs text-base-content/50">{target.type}</span>
                </div>
              <% end %>
              <%= if length(@targets) > 5 do %>
                <p class="text-xs text-base-content/50 pt-2">
                  + {length(@targets) - 5} more targets
                </p>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    </div>

    <!-- Edit Mission Modal -->
    <.modal
      :if={@live_action == :edit}
      id="mission-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}")}
    >
      <.live_component
        module={CadenceWeb.MissionLive.FormComponent}
        id={@mission.id}
        title="Edit Mission"
        action={:edit}
        mission={@mission}
        patch={~p"/missions/#{@mission}"}
        current_user={@current_scope.user}
        current_scope={@current_scope}
      />
    </.modal>
    """
  end
end
