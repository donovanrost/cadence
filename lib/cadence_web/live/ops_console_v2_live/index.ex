defmodule CadenceWeb.OpsConsoleV2Live.Index do
  @moduledoc """
  OPS Console V2 - Next generation mission control interface.

  A clean slate redesign featuring:
  - Global status bar with fleet health and alarm counts
  - Enhanced mission-control grade visual design
  - Full commanding integration
  - New widget types (Command, Procedure, Alarm Summary, Fleet Health)
  - Fullscreen widget capability
  """

  use CadenceWeb, :live_view

  alias Cadence.{Alarms, MissionDatabase, Targets, DashboardLayouts, Procedures, Commands, Outbox, Timeline}
  alias Cadence.DashboardLayouts.DashboardLayout
  alias Cadence.MissionDatabase.{Database, MetaCommand}

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.mission
    targets = Targets.list_targets(mission)
    mission_id = mission.id

    # Get user from scope
    user = socket.assigns.current_scope.user

    # Load all user dashboards for this mission
    dashboards = DashboardLayouts.list_user_layouts(user, mission_id)

    # Get current dashboard (default or first, or create new)
    current_layout =
      case dashboards do
        [] ->
          %DashboardLayout{
            user_id: user.id,
            mission_id: mission_id,
            name: "Default"
          }

        layouts ->
          Enum.find(layouts, List.first(layouts), & &1.is_default)
      end

    # Generate authentication token for channel
    token = generate_socket_token(user)

    # Load telemetry catalog for widget configuration
    telemetry_catalog =
      case MissionDatabase.get_telemetry_catalog(mission_id) do
        {:ok, catalog} -> catalog
        {:error, _} -> %{packets: [], derived_items: []}
      end

    # Load active alarms
    active_alarms = Alarms.list_active_alarms(mission_id)

    # Calculate alarm counts by severity
    alarm_counts = calculate_alarm_counts(active_alarms)

    # Calculate fleet health
    fleet_health = calculate_fleet_health(targets)

    # Load running procedures for the mission
    running_procedures = Procedures.list_executions(mission_id: mission_id, status: :running)

    # Load command queue entries (pending and executing) for context panel
    queue_entries =
      Commands.list_queue_entries(mission_id,
        status: [:pending, :executing],
        preload: [:target],
        limit: 50
      )

    # Load all queue entries for Queue mode dashboard (includes completed, failed, etc.)
    all_queue_entries =
      Commands.list_queue_entries(mission_id,
        status: [:pending, :executing, :completed, :failed, :cancelled, :expired],
        preload: [:target],
        limit: 200
      )

    # Load command definitions for Commands mode
    # Commands (MetaCommands) belong to MDB DefinitionSets, which belong to Databases
    command_definitions = load_command_definitions(mission_id)

    # Load staged commands for the mission
    staged_commands = Commands.list_staged(mission_id)

    # Load recent timeline events (last 2 hours + 24h future)
    timeline_events = Timeline.list_recent_events(mission_id, 120)

    # Subscribe to updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:procedures")
      # Subscribe to command queue events via Outbox
      Outbox.subscribe_mission(mission_id)
      # Subscribe to staging changes
      Commands.subscribe_staging(mission_id)
      # Start clock ticker
      :timer.send_interval(1000, self(), :tick)
    end

    socket =
      socket
      |> assign(:mission, mission)
      |> assign(:targets, targets)
      |> assign(:dashboards, dashboards)
      |> assign(:current_layout, current_layout)
      |> assign(:token, token)
      |> assign(:telemetry_catalog, telemetry_catalog)
      |> assign(:active_alarms, active_alarms)
      |> assign(:alarm_counts, alarm_counts)
      |> assign(:fleet_health, fleet_health)
      |> assign(:running_procedures, running_procedures)
      |> assign(:queue_entries, queue_entries)
      |> assign(:all_queue_entries, all_queue_entries)
      |> assign(:command_definitions, command_definitions)
      |> assign(:target_groups, [])
      |> assign(:staged_commands, staged_commands)
      |> assign(:timeline_events, timeline_events)
      |> assign(:current_time, DateTime.utc_now())
      |> assign(:page_title, "Ops Console V2 - #{mission.name}")
      |> assign(:show_widget_palette, false)
      # Commands mode state
      |> assign(:cmd_selected_targets, MapSet.new())
      |> assign(:cmd_selected_command, nil)
      |> assign(:cmd_param_form, nil)
      |> assign(:cmd_dispatch_mode, :queue)
      |> assign(:cmd_priority, 3)
      |> assign(:cmd_scheduled_at, nil)
      |> assign(:cmd_batch_confirm, nil)
      |> assign(:configuring_widget, nil)
      |> assign(:show_create_dashboard, false)
      |> assign(:show_rename_dashboard, nil)
      |> assign(:show_delete_confirm, nil)
      |> assign(:show_shelve_modal, nil)
      |> assign(:fullscreen_widget, nil)

    {:ok, socket, layout: {CadenceWeb.Layouts, :ops_console}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="ops-console-v2-wrapper"
      phx-hook="OpsConsoleV2"
      data-mission-id={@mission.id}
      data-mission-name={@mission.name}
      data-layout={
        Jason.encode!(@current_layout.frame_layout || DashboardLayouts.default_frame_layout())
      }
      data-widgets={Jason.encode!(@current_layout.widgets || [])}
      data-targets={Jason.encode!(Enum.map(@targets, &target_json/1))}
      data-dashboards={Jason.encode!(Enum.map(@dashboards, &dashboard_json/1))}
      data-alarms={Jason.encode!(Enum.map(@active_alarms, &alarm_json/1))}
      data-commands={Jason.encode!(Enum.map(@queue_entries, &queue_entry_json/1))}
      data-queue-entries={Jason.encode!(Enum.map(@all_queue_entries, &queue_entry_json/1))}
      data-command-definitions={Jason.encode!(Enum.map(@command_definitions, &command_definition_json/1))}
      data-target-groups={Jason.encode!([])}
      data-staged-commands={Jason.encode!(Enum.map(@staged_commands, &staged_command_json/1))}
      data-timeline-events={Jason.encode!(Enum.map(@timeline_events, &timeline_event_json/1))}
      data-current-dashboard-id={@current_layout.id}
      data-token={@token}
      class="h-screen w-screen overflow-hidden bg-base-100 flex flex-col"
    >
      <!-- Global Status Bar -->
      <.live_component
        module={CadenceWeb.OpsConsoleV2Live.StatusBarComponent}
        id="status-bar"
        mission={@mission}
        alarm_counts={@alarm_counts}
        fleet_health={@fleet_health}
        running_procedures={@running_procedures}
        current_time={@current_time}
      />

      <!-- Main Content Area -->
      <div id="ops-console-v2" phx-update="ignore" class="flex-1 min-h-0">
        <!-- Custom panel layout renders here -->
      </div>
    </div>

    <!-- Widget Palette Modal -->
    <.modal
      :if={@show_widget_palette}
      id="widget-palette-modal-v2"
      show={@show_widget_palette}
      on_cancel={JS.push("close_widget_palette")}
    >
      <.live_component
        module={CadenceWeb.OpsConsoleLive.WidgetPaletteComponent}
        id="widget-palette-v2"
        targets={@targets}
        telemetry_catalog={@telemetry_catalog}
      />
    </.modal>

    <!-- Widget Configuration Modal -->
    <.modal
      :if={@configuring_widget}
      id="widget-config-modal-v2"
      show={@configuring_widget != nil}
      on_cancel={JS.push("close_widget_config")}
    >
      <.live_component
        module={CadenceWeb.OpsConsoleLive.WidgetConfigComponent}
        id="widget-config-v2"
        widget={@configuring_widget}
        targets={@targets}
        telemetry_catalog={@telemetry_catalog}
      />
    </.modal>

    <!-- Create Dashboard Modal -->
    <.modal
      :if={@show_create_dashboard}
      id="create-dashboard-modal-v2"
      show={@show_create_dashboard}
      on_cancel={JS.push("close_create_dashboard")}
    >
      <.header>Create New Dashboard</.header>
      <.simple_form for={%{}} phx-submit="create_dashboard">
        <.input name="name" label="Dashboard Name" value="" required />
        <div class="flex gap-4 mt-4">
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="radio" name="clone" value="true" class="radio radio-sm" checked />
            <span>Clone current dashboard</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="radio" name="clone" value="false" class="radio radio-sm" />
            <span>Start empty</span>
          </label>
        </div>
        <:actions>
          <.button type="submit" phx-disable-with="Creating...">Create Dashboard</.button>
        </:actions>
      </.simple_form>
    </.modal>

    <!-- Rename Dashboard Modal -->
    <.modal
      :if={@show_rename_dashboard}
      id="rename-dashboard-modal-v2"
      show={@show_rename_dashboard != nil}
      on_cancel={JS.push("close_rename_dashboard")}
    >
      <.header>Rename Dashboard</.header>
      <.simple_form for={%{}} phx-submit="rename_dashboard">
        <input
          type="hidden"
          name="dashboard_id"
          value={@show_rename_dashboard && @show_rename_dashboard.id}
        />
        <.input
          name="name"
          label="Dashboard Name"
          value={@show_rename_dashboard && @show_rename_dashboard.name}
          required
        />
        <:actions>
          <.button type="submit" phx-disable-with="Renaming...">Rename</.button>
        </:actions>
      </.simple_form>
    </.modal>

    <!-- Delete Confirmation Modal -->
    <.modal
      :if={@show_delete_confirm}
      id="delete-dashboard-modal-v2"
      show={@show_delete_confirm != nil}
      on_cancel={JS.push("close_delete_confirm")}
    >
      <.header>Delete Dashboard</.header>
      <p class="text-base-content/70 mb-4">
        Are you sure you want to delete "{@show_delete_confirm && @show_delete_confirm.name}"?
        This action cannot be undone.
      </p>
      <div class="flex gap-2 justify-end">
        <.button type="button" phx-click="close_delete_confirm" class="btn-ghost">
          Cancel
        </.button>
        <.button
          type="button"
          phx-click="confirm_delete_dashboard"
          phx-value-id={@show_delete_confirm && @show_delete_confirm.id}
          class="btn-error"
          phx-disable-with="Deleting..."
        >
          Delete
        </.button>
      </div>
    </.modal>

    <!-- Shelve Alarm Modal -->
    <.modal
      :if={@show_shelve_modal}
      id="shelve-alarm-modal-v2"
      show={@show_shelve_modal != nil}
      on_cancel={JS.push("close_shelve_modal")}
    >
      <.header>Shelve Alarm</.header>
      <p class="text-base-content/70 mb-4">
        Shelving will temporarily suppress this alarm for the specified duration.
      </p>
      <.simple_form for={%{}} phx-submit="confirm_shelve_alarm">
        <input type="hidden" name="alarm_id" value={@show_shelve_modal && @show_shelve_modal.id} />
        <.input
          name="duration"
          type="select"
          label="Shelve Duration"
          options={[
            {"5 minutes", "5"},
            {"15 minutes", "15"},
            {"30 minutes", "30"},
            {"1 hour", "60"},
            {"4 hours", "240"},
            {"8 hours", "480"},
            {"24 hours", "1440"}
          ]}
          value="30"
        />
        <.input
          name="reason"
          type="text"
          label="Reason (optional)"
          placeholder="e.g., Known issue, waiting for fix"
        />
        <:actions>
          <.button type="submit" phx-disable-with="Shelving...">Shelve Alarm</.button>
        </:actions>
      </.simple_form>
    </.modal>
    """
  end

  # Clock tick handler
  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :current_time, DateTime.utc_now())}
  end

  # Delegate to existing OpsConsoleLive event handlers
  # Layout events
  @impl true
  def handle_event("layout_changed", %{"frame_layout" => frame_layout}, socket) do
    current_layout = socket.assigns.current_layout

    case DashboardLayouts.update_frame_layout(current_layout, frame_layout) do
      {:ok, updated_layout} ->
        {:noreply,
         socket
         |> assign(:current_layout, updated_layout)
         |> update_dashboards_list(updated_layout)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save layout")}
    end
  end

  def handle_event("widgets_changed", %{"widgets" => widgets}, socket) do
    current_layout = socket.assigns.current_layout

    case DashboardLayouts.update_widgets(current_layout, widgets) do
      {:ok, updated_layout} ->
        {:noreply,
         socket
         |> assign(:current_layout, updated_layout)
         |> update_dashboards_list(updated_layout)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save widgets")}
    end
  end

  def handle_event("open_widget_palette", _params, socket) do
    {:noreply, assign(socket, :show_widget_palette, true)}
  end

  def handle_event("close_widget_palette", _params, socket) do
    {:noreply, assign(socket, :show_widget_palette, false)}
  end

  def handle_event("add_widget", params, socket) do
    {:noreply,
     socket
     |> assign(:show_widget_palette, false)
     |> push_event("add_widget", params)}
  end

  def handle_event(
        "open_widget_config",
        %{"widget_id" => id, "widget_type" => type, "config" => config},
        socket
      ) do
    {:noreply, assign(socket, :configuring_widget, %{id: id, type: type, config: config})}
  end

  def handle_event("close_widget_config", _params, socket) do
    {:noreply, assign(socket, :configuring_widget, nil)}
  end

  def handle_event("save_layout", params, socket) do
    current_layout = socket.assigns.current_layout

    attrs = %{
      frame_layout: params["frame_layout"],
      widgets: params["widgets"]
    }

    case DashboardLayouts.save_layout(current_layout, attrs) do
      {:ok, updated_layout} ->
        {:noreply,
         socket
         |> assign(:current_layout, updated_layout)
         |> update_dashboards_list(updated_layout)
         |> put_flash(:info, "Layout saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save layout")}
    end
  end

  def handle_event("reset_layout", _params, socket) do
    default_layout = %{
      frame_layout: DashboardLayouts.default_frame_layout(),
      widgets: []
    }

    {:noreply,
     socket
     |> push_event("load_layout", default_layout)
     |> put_flash(:info, "Layout reset to default")}
  end

  # Dashboard CRUD
  def handle_event("open_create_dashboard", _params, socket) do
    {:noreply, assign(socket, :show_create_dashboard, true)}
  end

  def handle_event("close_create_dashboard", _params, socket) do
    {:noreply, assign(socket, :show_create_dashboard, false)}
  end

  def handle_event("create_dashboard", %{"name" => name, "clone" => clone}, socket) do
    user = socket.assigns.current_scope.user
    mission = socket.assigns.mission
    current_layout = socket.assigns.current_layout

    attrs =
      if clone == "true" do
        %{
          name: name,
          frame_layout: current_layout.frame_layout || DashboardLayouts.default_frame_layout(),
          widgets: current_layout.widgets || [],
          user_id: user.id,
          mission_id: mission.id
        }
      else
        %{
          name: name,
          frame_layout: DashboardLayouts.default_frame_layout(),
          widgets: [],
          user_id: user.id,
          mission_id: mission.id
        }
      end

    case DashboardLayouts.create_layout(attrs) do
      {:ok, new_layout} ->
        dashboards = [new_layout | socket.assigns.dashboards]

        {:noreply,
         socket
         |> assign(:dashboards, dashboards)
         |> assign(:current_layout, new_layout)
         |> assign(:show_create_dashboard, false)
         |> push_event("load_layout", %{
           frame_layout: new_layout.frame_layout,
           widgets: new_layout.widgets
         })
         |> push_event("update_dashboards", %{
           dashboards: Enum.map(dashboards, &dashboard_json/1),
           currentId: new_layout.id
         })
         |> put_flash(:info, "Dashboard \"#{name}\" created")}

      {:error, changeset} ->
        error_msg =
          case changeset.errors[:name] do
            {_, [constraint: :unique, constraint_name: _]} ->
              "A dashboard named \"#{name}\" already exists"

            _ ->
              "Failed to create dashboard"
          end

        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  def handle_event("switch_dashboard", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case DashboardLayouts.get_layout(id, user.id) do
      {:ok, layout} ->
        {:noreply,
         socket
         |> assign(:current_layout, layout)
         |> push_event("load_layout", %{
           frame_layout: layout.frame_layout,
           widgets: layout.widgets
         })
         |> push_event("update_dashboards", %{
           dashboards: Enum.map(socket.assigns.dashboards, &dashboard_json/1),
           currentId: layout.id
         })}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Dashboard not found")}
    end
  end

  def handle_event("open_rename_dashboard", %{"id" => id, "name" => name}, socket) do
    {:noreply, assign(socket, :show_rename_dashboard, %{id: id, name: name})}
  end

  def handle_event("close_rename_dashboard", _params, socket) do
    {:noreply, assign(socket, :show_rename_dashboard, nil)}
  end

  def handle_event("rename_dashboard", %{"dashboard_id" => id, "name" => name}, socket) do
    user = socket.assigns.current_scope.user

    case DashboardLayouts.get_layout(id, user.id) do
      {:ok, layout} ->
        case DashboardLayouts.save_layout(layout, %{name: name}) do
          {:ok, updated_layout} ->
            dashboards = update_layout_in_list(socket.assigns.dashboards, updated_layout)

            current_layout =
              if socket.assigns.current_layout.id == updated_layout.id do
                updated_layout
              else
                socket.assigns.current_layout
              end

            {:noreply,
             socket
             |> assign(:dashboards, dashboards)
             |> assign(:current_layout, current_layout)
             |> assign(:show_rename_dashboard, nil)
             |> push_event("update_dashboards", %{
               dashboards: Enum.map(dashboards, &dashboard_json/1),
               currentId: current_layout.id
             })
             |> put_flash(:info, "Dashboard renamed")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to rename dashboard")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Dashboard not found")}
    end
  end

  def handle_event("duplicate_dashboard", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case DashboardLayouts.get_layout(id, user.id) do
      {:ok, layout} ->
        case DashboardLayouts.duplicate_layout(layout, "#{layout.name} (copy)") do
          {:ok, new_layout} ->
            dashboards = [new_layout | socket.assigns.dashboards]

            {:noreply,
             socket
             |> assign(:dashboards, dashboards)
             |> push_event("update_dashboards", %{
               dashboards: Enum.map(dashboards, &dashboard_json/1),
               currentId: socket.assigns.current_layout.id
             })
             |> put_flash(:info, "Dashboard duplicated")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to duplicate dashboard")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Dashboard not found")}
    end
  end

  def handle_event("open_delete_confirm", %{"id" => id, "name" => name}, socket) do
    {:noreply, assign(socket, :show_delete_confirm, %{id: id, name: name})}
  end

  def handle_event("close_delete_confirm", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, nil)}
  end

  def handle_event("confirm_delete_dashboard", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case DashboardLayouts.get_layout(id, user.id) do
      {:ok, layout} ->
        case DashboardLayouts.delete_layout(layout) do
          {:ok, _} ->
            dashboards = Enum.reject(socket.assigns.dashboards, &(&1.id == layout.id))

            {current_layout, should_load} =
              if socket.assigns.current_layout.id == layout.id do
                new_current = List.first(dashboards) || create_default_layout(socket)
                {new_current, true}
              else
                {socket.assigns.current_layout, false}
              end

            socket =
              socket
              |> assign(:dashboards, dashboards)
              |> assign(:current_layout, current_layout)
              |> assign(:show_delete_confirm, nil)
              |> push_event("update_dashboards", %{
                dashboards: Enum.map(dashboards, &dashboard_json/1),
                currentId: current_layout.id
              })
              |> put_flash(:info, "Dashboard deleted")

            socket =
              if should_load do
                push_event(socket, "load_layout", %{
                  frame_layout:
                    current_layout.frame_layout || DashboardLayouts.default_frame_layout(),
                  widgets: current_layout.widgets || []
                })
              else
                socket
              end

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete dashboard")}
        end

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:show_delete_confirm, nil)
         |> put_flash(:error, "Dashboard not found")}
    end
  end

  # Alarm action handlers
  def handle_event("acknowledge_alarm", %{"id" => alarm_id}, socket) do
    user = socket.assigns.current_scope.user
    alarm = Alarms.get_alarm!(alarm_id)

    case Alarms.acknowledge_alarm(alarm, user.id) do
      {:ok, updated_alarm} ->
        broadcast_alarm_update(socket.assigns.mission.id, updated_alarm)
        {:noreply, put_flash(socket, :info, "Alarm acknowledged")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to acknowledge alarm")}
    end
  end

  def handle_event("open_shelve_modal", %{"id" => alarm_id}, socket) do
    alarm = Alarms.get_alarm!(alarm_id)
    {:noreply, assign(socket, :show_shelve_modal, alarm)}
  end

  def handle_event("close_shelve_modal", _params, socket) do
    {:noreply, assign(socket, :show_shelve_modal, nil)}
  end

  def handle_event(
        "confirm_shelve_alarm",
        %{"alarm_id" => alarm_id, "duration" => duration, "reason" => reason},
        socket
      ) do
    user = socket.assigns.current_scope.user
    alarm = Alarms.get_alarm!(alarm_id)
    duration_minutes = String.to_integer(duration)

    case Alarms.shelve_alarm(alarm, user.id, duration_minutes, reason) do
      {:ok, updated_alarm} ->
        broadcast_alarm_update(socket.assigns.mission.id, updated_alarm)

        {:noreply,
         socket
         |> assign(:show_shelve_modal, nil)
         |> put_flash(:info, "Alarm shelved for #{duration} minutes")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to shelve alarm")}
    end
  end

  def handle_event("unshelve_alarm", %{"id" => alarm_id}, socket) do
    user = socket.assigns.current_scope.user
    alarm = Alarms.get_alarm!(alarm_id)

    case Alarms.unshelve_alarm(alarm, user.id) do
      {:ok, updated_alarm} ->
        broadcast_alarm_update(socket.assigns.mission.id, updated_alarm)
        {:noreply, put_flash(socket, :info, "Alarm unshelved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unshelve alarm")}
    end
  end

  def handle_event("clear_alarm", %{"id" => alarm_id}, socket) do
    user = socket.assigns.current_scope.user
    alarm = Alarms.get_alarm!(alarm_id)

    case Alarms.clear_alarm(alarm, user.id) do
      {:ok, updated_alarm} ->
        broadcast_alarm_update(socket.assigns.mission.id, updated_alarm)
        {:noreply, put_flash(socket, :info, "Alarm cleared")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to clear alarm")}
    end
  end

  # Command queue action handlers
  def handle_event("cancel_command", %{"id" => entry_id}, socket) do
    mission_id = socket.assigns.mission.id

    # Get the entry to find its target_id
    case Commands.get_queue_entry(entry_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Command not found")}

      entry ->
        case Commands.cancel_queued(mission_id, entry.target_id, entry_id) do
          {:ok, _cancelled_entry} ->
            # Refresh queue entries
            queue_entries =
              Commands.list_queue_entries(mission_id,
                status: [:pending, :executing],
                preload: [:target],
                limit: 50
              )

            {:noreply,
             socket
             |> assign(:queue_entries, queue_entries)
             |> push_event("update_commands", %{commands: Enum.map(queue_entries, &queue_entry_json/1)})
             |> put_flash(:info, "Command cancelled")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to cancel command: #{inspect(reason)}")}
        end
    end
  end

  # Command dispatch from Commands mode
  def handle_event(
        "cmd_dispatch",
        %{"command_id" => command_id, "target_ids" => target_ids, "params" => params} = payload,
        socket
      ) do
    mission_id = socket.assigns.mission.id
    mode = Map.get(payload, "mode", "queue")
    priority = Map.get(payload, "priority", 3)

    # Get command definition
    command = Enum.find(socket.assigns.command_definitions, &(&1.id == command_id))

    if command do
      results =
        Enum.map(target_ids, fn target_id ->
          opts = [target_id: target_id, priority: priority]

          if mode == "immediate" do
            Commands.dispatch(mission_id, command.name, params, opts)
          else
            Commands.enqueue(mission_id, command.name, params, opts)
          end
        end)

      # Check results
      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      # Refresh queue
      queue_entries =
        Commands.list_queue_entries(mission_id,
          status: [:pending, :executing],
          preload: [:target],
          limit: 50
        )

      socket =
        socket
        |> assign(:queue_entries, queue_entries)
        |> push_event("update_commands", %{commands: Enum.map(queue_entries, &queue_entry_json/1)})

      cond do
        failures == 0 ->
          {:noreply,
           put_flash(
             socket,
             :info,
             "#{successes} command(s) #{if mode == "immediate", do: "sent", else: "queued"}"
           )}

        successes == 0 ->
          {:noreply, put_flash(socket, :error, "Failed to dispatch commands")}

        true ->
          {:noreply,
           put_flash(socket, :warning, "#{successes} succeeded, #{failures} failed")}
      end
    else
      {:noreply, put_flash(socket, :error, "Command not found")}
    end
  end

  # Command dispatch with per-target parameters
  def handle_event(
        "cmd_dispatch_parameterized",
        %{"command_id" => command_id, "target_params" => target_params} = payload,
        socket
      ) do
    mission_id = socket.assigns.mission.id
    mode = Map.get(payload, "mode", "queue")
    priority = Map.get(payload, "priority", 3)

    # Get command definition
    command = Enum.find(socket.assigns.command_definitions, &(&1.id == command_id))

    if command do
      # Build the target_params list in the format expected by fleet_*_parameterized
      # Each entry is {target_id, params_map}
      formatted_params =
        Enum.map(target_params, fn entry ->
          target_id = entry["target_id"]
          params = entry["params"] || %{}
          {target_id, params}
        end)

      results =
        if mode == "immediate" do
          Commands.fleet_dispatch_parameterized(
            mission_id,
            command.name,
            formatted_params,
            priority: priority
          )
        else
          Commands.fleet_enqueue_parameterized(
            mission_id,
            command.name,
            formatted_params,
            priority: priority
          )
        end

      # Count successes/failures from results
      successes = Enum.count(results, fn {_target_id, result} -> match?({:ok, _}, result) end)
      failures = Enum.count(results, fn {_target_id, result} -> match?({:error, _}, result) end)

      # Refresh queue
      queue_entries =
        Commands.list_queue_entries(mission_id,
          status: [:pending, :executing],
          preload: [:target],
          limit: 50
        )

      socket =
        socket
        |> assign(:queue_entries, queue_entries)
        |> push_event("update_commands", %{commands: Enum.map(queue_entries, &queue_entry_json/1)})

      cond do
        failures == 0 ->
          {:noreply,
           put_flash(
             socket,
             :info,
             "#{successes} command(s) #{if mode == "immediate", do: "sent", else: "queued"} with per-target params"
           )}

        successes == 0 ->
          {:noreply, put_flash(socket, :error, "Failed to dispatch parameterized commands")}

        true ->
          {:noreply,
           put_flash(socket, :warning, "#{successes} succeeded, #{failures} failed")}
      end
    else
      {:noreply, put_flash(socket, :error, "Command not found")}
    end
  end

  def handle_event("cmd_pause_queue", _, socket) do
    mission_id = socket.assigns.mission.id
    Commands.pause_all_targets(mission_id)
    {:noreply, put_flash(socket, :info, "Command queue paused for all targets")}
  end

  def handle_event("cmd_resume_queue", _, socket) do
    mission_id = socket.assigns.mission.id
    Commands.resume_all_targets(mission_id)
    {:noreply, put_flash(socket, :info, "Command queue resumed for all targets")}
  end

  # ============================================================================
  # Queue Mode Event Handlers
  # ============================================================================

  # Cancel command from Queue mode (with target_id provided)
  def handle_event(
        "queue_cancel_command",
        %{"entry_id" => entry_id, "target_id" => target_id},
        socket
      ) do
    mission_id = socket.assigns.mission.id

    case Commands.cancel_queued(mission_id, target_id, entry_id) do
      {:ok, _cancelled_entry} ->
        {:noreply,
         socket
         |> refresh_all_queue_entries()
         |> put_flash(:info, "Command cancelled")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel command: #{inspect(reason)}")}
    end
  end

  # Pause all queues from Queue mode
  def handle_event("queue_pause_all", _, socket) do
    mission_id = socket.assigns.mission.id
    Commands.pause_all_targets(mission_id)
    {:noreply, put_flash(socket, :info, "All command queues paused")}
  end

  # Resume all queues from Queue mode
  def handle_event("queue_resume_all", _, socket) do
    mission_id = socket.assigns.mission.id
    Commands.resume_all_targets(mission_id)
    {:noreply, put_flash(socket, :info, "All command queues resumed")}
  end

  # Pause a specific target's queue
  def handle_event("queue_pause_target", %{"target_id" => target_id}, socket) do
    mission_id = socket.assigns.mission.id

    case Commands.pause_target(mission_id, target_id) do
      :ok ->
        {:noreply, push_event(socket, "queue_target_paused", %{target_id: target_id})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to pause queue: #{inspect(reason)}")}
    end
  end

  # Resume a specific target's queue
  def handle_event("queue_resume_target", %{"target_id" => target_id}, socket) do
    mission_id = socket.assigns.mission.id

    case Commands.resume_target(mission_id, target_id) do
      :ok ->
        {:noreply, push_event(socket, "queue_target_resumed", %{target_id: target_id})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to resume queue: #{inspect(reason)}")}
    end
  end

  # Cancel a single queued command
  def handle_event("queue_cancel_entry", %{"entry_id" => entry_id, "target_id" => target_id}, socket) do
    mission_id = socket.assigns.mission.id

    case Commands.cancel_queued(mission_id, target_id, entry_id) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> refresh_all_queue_entries()
         |> put_flash(:info, "Command cancelled")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel command: #{inspect(reason)}")}
    end
  end

  # Cancel all queued commands for a target
  def handle_event("queue_cancel_all_target", %{"target_id" => target_id}, socket) do
    mission_id = socket.assigns.mission.id

    case Commands.cancel_all_queued_for_target(mission_id, target_id) do
      {:ok, count} ->
        {:noreply,
         socket
         |> refresh_all_queue_entries()
         |> put_flash(:info, "Cancelled #{count} command(s)")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel commands: #{inspect(reason)}")}
    end
  end

  # Change priority of a queued command
  def handle_event(
        "queue_change_priority",
        %{"entry_id" => entry_id, "target_id" => target_id, "priority" => priority},
        socket
      ) do
    mission_id = socket.assigns.mission.id
    priority = if is_binary(priority), do: String.to_integer(priority), else: priority

    case Commands.reorder_queued(mission_id, target_id, entry_id, priority) do
      {:ok, _updated_entry} ->
        {:noreply,
         socket
         |> refresh_all_queue_entries()
         |> put_flash(:info, "Command priority updated")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to change priority: #{inspect(reason)}")}
    end
  end

  # Refresh queue entries for Queue mode
  def handle_event("queue_refresh", _, socket) do
    {:noreply, refresh_all_queue_entries(socket)}
  end

  # Helper to refresh all queue entries and push to frontend
  defp refresh_all_queue_entries(socket) do
    mission_id = socket.assigns.mission.id

    # Refresh both queue entry sets
    queue_entries =
      Commands.list_queue_entries(mission_id,
        status: [:pending, :executing],
        preload: [:target],
        limit: 50
      )

    all_queue_entries =
      Commands.list_queue_entries(mission_id,
        status: [:pending, :executing, :completed, :failed, :cancelled, :expired],
        preload: [:target],
        limit: 200
      )

    # Get server-side aggregated metrics (accurate counts regardless of limit)
    metrics = Commands.get_mission_queue_metrics(mission_id)

    socket
    |> assign(:queue_entries, queue_entries)
    |> assign(:all_queue_entries, all_queue_entries)
    |> push_event("update_commands", %{commands: Enum.map(queue_entries, &queue_entry_json/1)})
    |> push_event("update_queue_entries", %{
      entries: Enum.map(all_queue_entries, &queue_entry_json/1)
    })
    |> push_event("queue_metrics", %{metrics: metrics})
  end

  # ============================================================================
  # Command Staging Event Handlers
  # ============================================================================

  # Add a command to the staging area
  def handle_event(
        "stage_command",
        %{"command_id" => command_id, "targets" => targets} = payload,
        socket
      ) do
    user = socket.assigns.current_scope.user
    mission_id = socket.assigns.mission.id
    priority = Map.get(payload, "priority", 3)
    client_id = Map.get(payload, "client_id")

    command = Enum.find(socket.assigns.command_definitions, &(&1.id == command_id))

    if command do
      target_entries =
        Enum.map(targets, fn t ->
          %{
            target_id: t["target_id"],
            target_name: t["target_name"],
            params: t["params"] || %{}
          }
        end)

      case Commands.add_to_stage(user, mission_id, command, target_entries,
             priority: priority,
             client_id: client_id
           ) do
        {:ok, staged} ->
          {:noreply,
           socket
           |> update_staged_commands()
           |> push_event("staging_updated", %{action: "added", id: staged.id})}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to stage command")}
      end
    else
      {:noreply, put_flash(socket, :error, "Command not found")}
    end
  end

  # Update a target's parameters in staging
  def handle_event(
        "update_staged_params",
        %{"target_entry_id" => entry_id, "params" => params},
        socket
      ) do
    case Commands.update_staged_target_params(entry_id, params) do
      {:ok, _} ->
        {:noreply, update_staged_commands(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update parameters")}
    end
  end

  # Update a staged command's priority
  def handle_event(
        "update_staged_priority",
        %{"staged_command_id" => id, "priority" => priority},
        socket
      ) do
    case Commands.update_staged_priority(id, priority) do
      {:ok, _} ->
        {:noreply, update_staged_commands(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update priority")}
    end
  end

  # Remove a target from staging
  def handle_event("remove_staged_target", %{"target_entry_id" => entry_id}, socket) do
    case Commands.remove_staged_target(entry_id) do
      {:ok, _} ->
        {:noreply, update_staged_commands(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove target")}
    end
  end

  # Remove an entire staged command
  def handle_event("remove_staged_command", %{"staged_command_id" => id}, socket) do
    case Commands.remove_staged_command(id) do
      {:ok, _} ->
        {:noreply, update_staged_commands(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove staged command")}
    end
  end

  # Queue a single target from staging
  def handle_event("queue_staged_target", %{"target_entry_id" => entry_id}, socket) do
    case Commands.queue_staged_target(entry_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> update_staged_commands()
         |> refresh_all_queue_entries()
         |> put_flash(:info, "Command queued")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue: #{inspect(reason)}")}
    end
  end

  # Queue an entire staged command (all targets)
  def handle_event("queue_staged_command", %{"staged_command_id" => id}, socket) do
    case Commands.queue_staged_command(id) do
      {:ok, count} ->
        {:noreply,
         socket
         |> update_staged_commands()
         |> refresh_all_queue_entries()
         |> put_flash(:info, "#{count} command(s) queued")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue: #{inspect(reason)}")}
    end
  end

  # Queue all staged commands
  def handle_event("queue_all_staged", _params, socket) do
    mission_id = socket.assigns.mission.id

    case Commands.queue_all_staged(mission_id) do
      {:ok, count} ->
        {:noreply,
         socket
         |> update_staged_commands()
         |> refresh_all_queue_entries()
         |> put_flash(:info, "#{count} command(s) queued")}
    end
  end

  # Clear all staged commands
  def handle_event("clear_staging", _params, socket) do
    mission_id = socket.assigns.mission.id

    {:ok, _count} = Commands.clear_stage(mission_id)

    {:noreply,
     socket
     |> assign(:staged_commands, [])
     |> push_event("staging_updated", %{action: "cleared"})}
  end

  # ============================================================================
  # Timeline Event Handlers
  # ============================================================================

  @doc """
  Load more timeline events for infinite scroll.

  Receives a cursor (oldest timestamp currently loaded) and returns
  events before that timestamp. Optionally filters by target_ids.
  """
  def handle_event("load_more_timeline_events", params, socket) do
    cursor_string = params["cursor"]
    target_ids = params["target_ids"] || []
    # include_system is handled client-side by filtering events without target_id

    mission_id = socket.assigns.mission.id

    case DateTime.from_iso8601(cursor_string) do
      {:ok, cursor, _offset} ->
        # Build options for query
        opts = [limit: 50]

        opts =
          if target_ids != [] do
            Keyword.put(opts, :target_ids, target_ids)
          else
            opts
          end

        # Fetch older events
        older_events = Timeline.list_events_before(mission_id, cursor, opts)

        # Convert to JSON format
        events_json = Enum.map(older_events, &timeline_event_json/1)

        {:noreply,
         push_event(socket, "more_timeline_events", %{
           events: events_json,
           has_more: length(older_events) >= 50
         })}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # PubSub handlers for alarms
  def handle_info({:alarm_triggered, alarm}, socket) do
    active_alarms = [alarm | socket.assigns.active_alarms]
    alarm_counts = calculate_alarm_counts(active_alarms)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> assign(:alarm_counts, alarm_counts)
     |> push_event("alarm_update", %{type: "triggered", alarm: alarm_json(alarm)})
     |> push_timeline_alarm_event(alarm, :triggered)}
  end

  def handle_info({:alarm_created, alarm}, socket) do
    active_alarms = [alarm | socket.assigns.active_alarms]
    alarm_counts = calculate_alarm_counts(active_alarms)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> assign(:alarm_counts, alarm_counts)
     |> push_event("alarm_update", %{type: "created", alarm: alarm_json(alarm)})
     |> push_timeline_alarm_event(alarm, :created)}
  end

  def handle_info({:alarm_updated, alarm}, socket) do
    active_alarms =
      if Cadence.Alarms.Alarm.active?(alarm) do
        case Enum.find_index(socket.assigns.active_alarms, &(&1.id == alarm.id)) do
          nil -> [alarm | socket.assigns.active_alarms]
          idx -> List.replace_at(socket.assigns.active_alarms, idx, alarm)
        end
      else
        Enum.reject(socket.assigns.active_alarms, &(&1.id == alarm.id))
      end

    alarm_counts = calculate_alarm_counts(active_alarms)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> assign(:alarm_counts, alarm_counts)
     |> push_event("alarm_update", %{type: "updated", alarm: alarm_json(alarm)})}
  end

  def handle_info({:alarm_cleared, alarm}, socket) do
    active_alarms = Enum.reject(socket.assigns.active_alarms, &(&1.id == alarm.id))
    alarm_counts = calculate_alarm_counts(active_alarms)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> assign(:alarm_counts, alarm_counts)
     |> push_event("alarm_update", %{type: "cleared", alarm: alarm_json(alarm)})
     |> push_timeline_alarm_event(alarm, :cleared)}
  end

  def handle_info({:alarm_acknowledged, alarm}, socket) do
    active_alarms = update_alarm_in_list(socket.assigns.active_alarms, alarm)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> push_event("alarm_update", %{type: "acknowledged", alarm: alarm_json(alarm)})
     |> push_timeline_alarm_event(alarm, :acknowledged)}
  end

  def handle_info({:alarm_shelved, alarm}, socket) do
    active_alarms = update_alarm_in_list(socket.assigns.active_alarms, alarm)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> push_event("alarm_update", %{type: "shelved", alarm: alarm_json(alarm)})}
  end

  def handle_info({:alarm_unshelved, alarm}, socket) do
    active_alarms = update_alarm_in_list(socket.assigns.active_alarms, alarm)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> push_event("alarm_update", %{type: "unshelved", alarm: alarm_json(alarm)})}
  end

  # Outbox event handlers for command queue updates
  def handle_info({:outbox_event, %{event_type: event_type} = event}, socket)
      when event_type in ["command_enqueued", "command_status_changed", "command_cancelled"] do
    # Refresh all queue entries (context panel + Queue mode) and push timeline event
    socket =
      socket
      |> refresh_all_queue_entries()
      |> maybe_push_timeline_command_event(event)

    {:noreply, socket}
  end

  # Catch-all for other outbox events we're not interested in
  def handle_info({:outbox_event, _event}, socket) do
    {:noreply, socket}
  end

  # Handle procedure execution events for timeline
  def handle_info({:procedure_event, %Cadence.Procedures.Events.ProcedureExecutionEvent{} = event}, socket) do
    # Convert to timeline event and push to frontend
    {:noreply, push_timeline_procedure_event(socket, event)}
  end

  # Handle staging changes (for multi-tab/multi-operator sync)
  def handle_info({:staging_changed, action, _staged_command_id}, socket) do
    {:noreply,
     socket
     |> update_staged_commands()
     |> push_event("staging_updated", %{action: action})}
  end

  # Widget message handlers
  def handle_info({:widget_configure, widget_id, config}, socket) do
    {:noreply, assign(socket, :configuring_widget, %{id: widget_id, config: config})}
  end

  def handle_info({:close_widget_palette}, socket) do
    {:noreply, assign(socket, :show_widget_palette, false)}
  end

  def handle_info({:add_widget, widget}, socket) do
    {:noreply,
     socket
     |> assign(:show_widget_palette, false)
     |> push_event("add_widget", widget)}
  end

  def handle_info({:close_widget_config}, socket) do
    {:noreply, assign(socket, :configuring_widget, nil)}
  end

  def handle_info({:update_widget_config, widget_id, config}, socket) do
    {:noreply,
     socket
     |> assign(:configuring_widget, nil)
     |> push_event("update_widget", %{id: widget_id, config: config})}
  end

  def handle_info({:delete_widget, widget_id}, socket) do
    {:noreply,
     socket
     |> assign(:configuring_widget, nil)
     |> push_event("remove_widget", %{id: widget_id})}
  end

  def handle_info({:duplicate_widget, widget_type, config}, socket) do
    widget = %{
      id: "widget-#{System.unique_integer([:positive])}",
      type: widget_type,
      position: %{
        x: 0,
        y: 0,
        w: default_widget_size(widget_type, :w),
        h: default_widget_size(widget_type, :h)
      },
      config: Map.put(config, "title", "#{config["title"]} (Copy)")
    }

    {:noreply,
     socket
     |> assign(:configuring_widget, nil)
     |> push_event("add_widget", widget)}
  end

  # Private functions

  defp calculate_alarm_counts(alarms) do
    alarms
    |> Enum.reject(& &1.shelved_at)
    |> Enum.reduce(%{critical: 0, warning: 0, info: 0}, fn alarm, acc ->
      case alarm.severity do
        :critical -> Map.update!(acc, :critical, &(&1 + 1))
        :warning -> Map.update!(acc, :warning, &(&1 + 1))
        _ -> Map.update!(acc, :info, &(&1 + 1))
      end
    end)
  end

  defp calculate_fleet_health(targets) do
    total = length(targets)

    if total == 0 do
      %{percentage: 100, total: 0, healthy: 0}
    else
      # For now, assume all targets are healthy
      # This would be enhanced with actual health status from telemetry
      healthy = total
      %{percentage: round(healthy / total * 100), total: total, healthy: healthy}
    end
  end

  defp update_alarm_in_list(alarms, updated_alarm) do
    case Enum.find_index(alarms, &(&1.id == updated_alarm.id)) do
      nil -> alarms
      idx -> List.replace_at(alarms, idx, updated_alarm)
    end
  end

  defp broadcast_alarm_update(mission_id, alarm) do
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "mission:#{mission_id}:alarms",
      {:alarm_updated, alarm}
    )
  end

  defp default_widget_size("line_chart", :w), do: 6
  defp default_widget_size("line_chart", :h), do: 3
  defp default_widget_size("value_display", :w), do: 3
  defp default_widget_size("value_display", :h), do: 2
  defp default_widget_size("gauge", :w), do: 3
  defp default_widget_size("gauge", :h), do: 3
  defp default_widget_size("table", :w), do: 6
  defp default_widget_size("table", :h), do: 4
  defp default_widget_size("command", :w), do: 3
  defp default_widget_size("command", :h), do: 2
  defp default_widget_size("procedure", :w), do: 4
  defp default_widget_size("procedure", :h), do: 4
  defp default_widget_size("alarm_summary", :w), do: 4
  defp default_widget_size("alarm_summary", :h), do: 3
  defp default_widget_size("fleet_health", :w), do: 4
  defp default_widget_size("fleet_health", :h), do: 3
  defp default_widget_size(_type, :w), do: 4
  defp default_widget_size(_type, :h), do: 2

  defp generate_socket_token(user) do
    Phoenix.Token.sign(CadenceWeb.Endpoint, "user socket", user.id)
  end

  defp target_json(target) do
    %{
      id: target.id,
      identifier: target.identifier,
      name: target.name,
      status: target.status,
      type: target.type
    }
  end

  defp dashboard_json(dashboard) do
    %{
      id: dashboard.id,
      name: dashboard.name,
      is_default: dashboard.is_default
    }
  end

  defp alarm_json(alarm) do
    %{
      id: alarm.id,
      severity: alarm.severity,
      status: alarm.status,
      source_type: alarm.source_type,
      source_id: alarm.source_id,
      message: alarm.message,
      triggered_at: alarm.triggered_at && DateTime.to_iso8601(alarm.triggered_at),
      acknowledged_at: alarm.acknowledged_at && DateTime.to_iso8601(alarm.acknowledged_at),
      shelved_at: alarm.shelved_at && DateTime.to_iso8601(alarm.shelved_at),
      shelved_until: alarm.shelved_until && DateTime.to_iso8601(alarm.shelved_until),
      target_id: alarm.target_id,
      current_value: alarm.current_value,
      limit_state: alarm.limit_state
    }
  end

  defp queue_entry_json(entry) do
    %{
      id: entry.id,
      command_name: entry.command_name,
      status: to_string(entry.status),
      priority: entry.priority,
      sequence_number: entry.sequence_number,
      target_id: entry.target_id,
      target_name: entry.target && entry.target.name,
      parameters: entry.parameters,
      scheduled_at: entry.scheduled_at && DateTime.to_iso8601(entry.scheduled_at),
      created_at: entry.inserted_at && DateTime.to_iso8601(entry.inserted_at),
      attempts: entry.attempts,
      max_attempts: entry.max_attempts,
      last_error: entry.last_error
    }
  end

  defp staged_command_json(staged) do
    %{
      id: staged.id,
      command_id: staged.meta_command_id,
      command_name: staged.command_name,
      priority: staged.priority,
      created_at: staged.inserted_at && DateTime.to_iso8601(staged.inserted_at),
      targets:
        Enum.map(staged.targets || [], fn t ->
          %{
            id: t.id,
            target_id: t.target_id,
            target_name: t.target_name,
            params: t.params
          }
        end)
    }
  end

  defp timeline_event_json(%Cadence.Timeline.Event{} = event) do
    %{
      id: event.id,
      type: event.type,
      timestamp: event.timestamp && DateTime.to_iso8601(event.timestamp),
      target_id: event.target_id,
      target_name: event.target_name,
      target_group: event.target_group,
      title: event.title,
      description: event.description,
      status: event.status,
      status_label: event.status_label,
      user_id: event.user_id,
      user_name: event.user_name,
      is_future: event.is_future,
      metadata: event.metadata,
      source_id: event.source_id,
      source_table: event.source_table
    }
  end

  defp update_staged_commands(socket) do
    mission_id = socket.assigns.mission.id
    staged = Commands.list_staged(mission_id)

    socket
    |> assign(:staged_commands, staged)
    |> push_event("load_staged_commands", %{staged: Enum.map(staged, &staged_command_json/1)})
  end

  # Push timeline command event from outbox (pipeable)
  # Construct the event directly from the outbox data (like alarms) to avoid database queries
  defp maybe_push_timeline_command_event(socket, %{event_type: event_type, payload: payload} = event) do
    command_name = Map.get(payload, "command_name") || Map.get(payload, :command_name) || "Command"
    target_id = Map.get(payload, "target_id") || Map.get(payload, :target_id)
    status = Map.get(payload, "status") || Map.get(payload, :status)

    # Use recording_id if available, otherwise use aggregate_id for uniqueness
    event_id = if event.recording_id do
      "rec-#{event.recording_id}"
    else
      "cmd-#{event.aggregate_id}-#{System.unique_integer([:positive])}"
    end

    timeline_event = %Cadence.Timeline.Event{
      id: event_id,
      type: :command,
      timestamp: event.inserted_at || DateTime.utc_now(),
      target_id: target_id,
      target_name: nil,
      target_group: nil,
      title: command_name,
      description: format_command_event_description(event_type, status),
      status: map_command_event_status(event_type, status),
      status_label: format_command_status_label(event_type, status),
      user_id: event.actor_id,
      user_name: nil,
      is_future: false,
      metadata: %{
        event_type: event_type,
        priority: Map.get(payload, "priority") || Map.get(payload, :priority),
        scheduled_at: Map.get(payload, "scheduled_at") || Map.get(payload, :scheduled_at)
      },
      source_id: event.aggregate_id,
      source_table: :command_queue_entries
    }

    push_event(socket, "timeline_event", %{event: timeline_event_json(timeline_event)})
  end

  defp maybe_push_timeline_command_event(socket, _event), do: socket

  defp format_command_event_description("command_enqueued", _), do: "Command queued"
  defp format_command_event_description("command_status_changed", "completed"), do: "Command completed"
  defp format_command_event_description("command_status_changed", "failed"), do: "Command failed"
  defp format_command_event_description("command_status_changed", "executing"), do: "Command executing"
  defp format_command_event_description("command_status_changed", "pending"), do: "Command pending"
  defp format_command_event_description("command_cancelled", _), do: "Command cancelled"
  defp format_command_event_description(_, status) when is_binary(status), do: "Command #{status}"
  defp format_command_event_description(_, _), do: "Command"

  defp map_command_event_status("command_enqueued", _), do: :pending
  defp map_command_event_status("command_status_changed", "completed"), do: :success
  defp map_command_event_status("command_status_changed", "failed"), do: :error
  defp map_command_event_status("command_status_changed", "executing"), do: :running
  defp map_command_event_status("command_cancelled", _), do: :error
  defp map_command_event_status(_, _), do: :pending

  defp format_command_status_label("command_enqueued", _), do: "QUEUED"
  defp format_command_status_label("command_status_changed", status) when is_binary(status), do: String.upcase(status)
  defp format_command_status_label("command_cancelled", _), do: "CANCELLED"
  defp format_command_status_label(_, _), do: "PENDING"

  # Push timeline alarm event (pipeable)
  defp push_timeline_alarm_event(socket, alarm, event_type) do
    event = %Cadence.Timeline.Event{
      id: "alm-#{alarm.id}-#{System.unique_integer([:positive])}",
      type: :alarm,
      timestamp: DateTime.utc_now(),
      target_id: alarm.target_id,
      target_name: nil,
      target_group: nil,
      title: alarm.message || alarm.alarm_type,
      description: format_alarm_event_description(event_type),
      status: map_alarm_status(event_type),
      status_label: event_type |> to_string() |> String.upcase(),
      user_id: nil,
      user_name: nil,
      is_future: false,
      metadata: %{
        severity: alarm.severity,
        source_type: alarm.source_type
      },
      source_id: alarm.id,
      source_table: :alarms
    }

    push_event(socket, "timeline_event", %{event: timeline_event_json(event)})
  end

  defp format_alarm_event_description(:triggered), do: "Alarm triggered"
  defp format_alarm_event_description(:acknowledged), do: "Acknowledged"
  defp format_alarm_event_description(:cleared), do: "Cleared"
  defp format_alarm_event_description(:shelved), do: "Shelved"
  defp format_alarm_event_description(:created), do: "Alarm created"
  defp format_alarm_event_description(type), do: to_string(type)

  defp map_alarm_status(:triggered), do: :active
  defp map_alarm_status(:acknowledged), do: :active
  defp map_alarm_status(:cleared), do: :success
  defp map_alarm_status(:shelved), do: :pending
  defp map_alarm_status(:created), do: :active
  defp map_alarm_status(_), do: :active

  # Push timeline procedure event (pipeable)
  defp push_timeline_procedure_event(socket, %Cadence.Procedures.Events.ProcedureExecutionEvent{} = proc_event) do
    event = %Cadence.Timeline.Event{
      id: "proc-#{proc_event.execution_id}-#{proc_event.event_type}",
      type: :procedure,
      timestamp: proc_event.timestamp,
      target_id: proc_event.target_id,
      target_name: nil,
      target_group: nil,
      title: proc_event.procedure_name || "Procedure",
      description: format_procedure_event_description(proc_event),
      status: map_procedure_event_status(proc_event.event_type),
      status_label: proc_event.event_type |> to_string() |> String.upcase(),
      user_id: proc_event.triggered_by_user_id,
      user_name: nil,
      is_future: false,
      metadata: %{
        execution_id: proc_event.execution_id,
        procedure_id: proc_event.procedure_id,
        event_type: proc_event.event_type,
        step_index: proc_event.step_index,
        error_message: proc_event.error_message,
        triggered_by: proc_event.triggered_by
      },
      source_id: proc_event.execution_id,
      source_table: :procedure_executions
    }

    push_event(socket, "timeline_event", %{event: timeline_event_json(event)})
  end

  defp format_procedure_event_description(%{event_type: :started}), do: "Execution started"
  defp format_procedure_event_description(%{event_type: :completed}), do: "Completed successfully"
  defp format_procedure_event_description(%{event_type: :failed, error_message: msg}) when is_binary(msg), do: "Failed: #{msg}"
  defp format_procedure_event_description(%{event_type: :failed}), do: "Execution failed"
  defp format_procedure_event_description(%{event_type: :paused, step_index: idx}) when is_integer(idx), do: "Paused at step #{idx + 1}"
  defp format_procedure_event_description(%{event_type: :paused}), do: "Paused"
  defp format_procedure_event_description(%{event_type: :pausing}), do: "Pausing..."
  defp format_procedure_event_description(%{event_type: :resumed}), do: "Resumed"
  defp format_procedure_event_description(%{event_type: :cancelled}), do: "Cancelled"
  defp format_procedure_event_description(%{event_type: :step_started, step_index: idx}), do: "Step #{idx + 1} started"
  defp format_procedure_event_description(%{event_type: :step_completed, step_index: idx}), do: "Step #{idx + 1} completed"
  defp format_procedure_event_description(_), do: nil

  defp map_procedure_event_status(:started), do: :running
  defp map_procedure_event_status(:completed), do: :success
  defp map_procedure_event_status(:failed), do: :error
  defp map_procedure_event_status(:paused), do: :pending
  defp map_procedure_event_status(:pausing), do: :pending
  defp map_procedure_event_status(:resumed), do: :running
  defp map_procedure_event_status(:cancelled), do: :error
  defp map_procedure_event_status(:step_started), do: :running
  defp map_procedure_event_status(:step_completed), do: :running
  defp map_procedure_event_status(_), do: :running

  # Load command definitions (MetaCommands) for the mission
  # Gets the first published definition set from any database
  defp load_command_definitions(mission_id) do
    import Ecto.Query

    # Find first published definition set for this mission
    definition_set =
      from(ds in Cadence.MissionDatabase.DefinitionSet,
        join: db in Database, on: ds.database_id == db.id,
        where: db.mission_id == ^mission_id,
        where: not is_nil(ds.published_at),
        where: is_nil(ds.superseded_at),
        order_by: [desc: ds.published_at],
        limit: 1
      )
      |> Cadence.Repo.one()

    case definition_set do
      nil ->
        []

      ds ->
        from(c in MetaCommand,
          where: c.definition_set_id == ^ds.id,
          where: c.abstract == false or is_nil(c.abstract),
          order_by: [asc: c.name],
          preload: [:arguments]
        )
        |> Cadence.Repo.all()
    end
  end

  defp command_definition_json(cmd) do
    %{
      id: cmd.id,
      name: cmd.name,
      opcode: cmd.opcode,
      description: cmd.description || cmd.short_description,
      is_hazardous: cmd.is_hazardous || false,
      hazard_description: cmd.hazard_description,
      parameters:
        Enum.map(cmd.arguments || [], fn arg ->
          %{
            id: arg.id,
            name: arg.name,
            data_type: arg.data_type_ref || arg.data_type,
            description: arg.description,
            required: arg.required || false,
            default_value: arg.default_value,
            min_value: arg.min_value,
            max_value: arg.max_value,
            valid_values: arg.valid_values,
            units: nil
          }
        end)
    }
  end

  defp update_dashboards_list(socket, updated_layout) do
    dashboards = update_layout_in_list(socket.assigns.dashboards, updated_layout)
    assign(socket, :dashboards, dashboards)
  end

  defp update_layout_in_list(dashboards, updated_layout) do
    Enum.map(dashboards, fn layout ->
      if layout.id == updated_layout.id, do: updated_layout, else: layout
    end)
  end

  defp create_default_layout(socket) do
    user = socket.assigns.current_scope.user
    mission = socket.assigns.mission

    %DashboardLayout{
      user_id: user.id,
      mission_id: mission.id,
      name: "Default"
    }
  end
end
