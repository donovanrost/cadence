defmodule CadenceWeb.OpsConsoleLive.Index do
  @moduledoc """
  LiveView for the Ops Console - the main C2 operator interface.

  Provides a configurable dashboard with:
  - Golden Layout docking panels (navigation, dashboard, context)
  - GridStack widget grid for telemetry visualization
  - Real-time telemetry via Phoenix Channels
  - User-customizable layouts persisted to database
  """

  use CadenceWeb, :live_view

  alias Cadence.{Alarms, MissionDatabase, Targets, DashboardLayouts}
  alias Cadence.Alarms.Alarm
  alias Cadence.DashboardLayouts.DashboardLayout

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
          # No dashboards yet, create a default one
          %DashboardLayout{
            user_id: user.id,
            mission_id: mission_id,
            name: "Default"
          }

        layouts ->
          # Find default or use first
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

    # Subscribe to alarm updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
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
      |> assign(:page_title, "Ops Console - #{mission.name}")
      |> assign(:show_widget_palette, false)
      |> assign(:configuring_widget, nil)
      |> assign(:show_create_dashboard, false)
      |> assign(:show_rename_dashboard, nil)
      |> assign(:show_delete_confirm, nil)
      |> assign(:show_shelve_modal, nil)

    {:ok, socket, layout: {CadenceWeb.Layouts, :ops_console}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="ops-console-wrapper"
      phx-hook="OpsConsole"
      data-mission-id={@mission.id}
      data-mission-name={@mission.name}
      data-layout={
        Jason.encode!(@current_layout.frame_layout || DashboardLayouts.default_frame_layout())
      }
      data-widgets={Jason.encode!(@current_layout.widgets || [])}
      data-targets={Jason.encode!(Enum.map(@targets, &target_json/1))}
      data-dashboards={Jason.encode!(Enum.map(@dashboards, &dashboard_json/1))}
      data-alarms={Jason.encode!(Enum.map(@active_alarms, &alarm_json/1))}
      data-current-dashboard-id={@current_layout.id}
      data-token={@token}
      class="h-screen w-screen overflow-hidden bg-base-100"
    >
      <div id="ops-console" phx-update="ignore" class="h-full w-full">
        <!-- Golden Layout renders here -->
      </div>
    </div>

    <!-- Widget Palette Modal -->
    <.modal
      :if={@show_widget_palette}
      id="widget-palette-modal"
      show={@show_widget_palette}
      on_cancel={JS.push("close_widget_palette")}
    >
      <.live_component
        module={CadenceWeb.OpsConsoleLive.WidgetPaletteComponent}
        id="widget-palette"
        targets={@targets}
        telemetry_catalog={@telemetry_catalog}
      />
    </.modal>

    <!-- Widget Configuration Modal -->
    <.modal
      :if={@configuring_widget}
      id="widget-config-modal"
      show={@configuring_widget != nil}
      on_cancel={JS.push("close_widget_config")}
    >
      <.live_component
        module={CadenceWeb.OpsConsoleLive.WidgetConfigComponent}
        id="widget-config"
        widget={@configuring_widget}
        targets={@targets}
        telemetry_catalog={@telemetry_catalog}
      />
    </.modal>

    <!-- Create Dashboard Modal -->
    <.modal
      :if={@show_create_dashboard}
      id="create-dashboard-modal"
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
      id="rename-dashboard-modal"
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
      id="delete-dashboard-modal"
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
      id="shelve-alarm-modal"
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

  @impl true
  def handle_event("layout_changed", %{"frame_layout" => frame_layout}, socket) do
    # Debounced save of frame layout
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
    # Debounced save of widgets
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
    # Send widget config to browser
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

  # Dashboard CRUD operations

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

            # If we deleted the current dashboard, switch to another
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

  # Handle widget configuration events from browser
  @impl true
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
    # Create a new widget with the same type and config but new ID
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

  # Handle alarm PubSub updates
  # :alarm_triggered is sent when a new alarm is created
  def handle_info({:alarm_triggered, alarm}, socket) do
    active_alarms = [alarm | socket.assigns.active_alarms]

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> push_event("alarm_update", %{type: "triggered", alarm: alarm_json(alarm)})}
  end

  # Legacy handler for :alarm_created (in case any code still uses it)
  def handle_info({:alarm_created, alarm}, socket) do
    active_alarms = [alarm | socket.assigns.active_alarms]

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> push_event("alarm_update", %{type: "created", alarm: alarm_json(alarm)})}
  end

  def handle_info({:alarm_updated, alarm}, socket) do
    active_alarms =
      if Alarm.active?(alarm) do
        # Update existing or add if not present
        case Enum.find_index(socket.assigns.active_alarms, &(&1.id == alarm.id)) do
          nil -> [alarm | socket.assigns.active_alarms]
          idx -> List.replace_at(socket.assigns.active_alarms, idx, alarm)
        end
      else
        # Remove from active list
        Enum.reject(socket.assigns.active_alarms, &(&1.id == alarm.id))
      end

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> push_event("alarm_update", %{type: "updated", alarm: alarm_json(alarm)})}
  end

  def handle_info({:alarm_cleared, alarm}, socket) do
    active_alarms = Enum.reject(socket.assigns.active_alarms, &(&1.id == alarm.id))

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> push_event("alarm_update", %{type: "cleared", alarm: alarm_json(alarm)})}
  end

  def handle_info({:alarm_acknowledged, alarm}, socket) do
    active_alarms = update_alarm_in_list(socket.assigns.active_alarms, alarm)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> push_event("alarm_update", %{type: "acknowledged", alarm: alarm_json(alarm)})}
  end

  def handle_info({:alarm_shelved, alarm}, socket) do
    # Shelved alarms are still active but hidden from normal view
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

  # Helper to update an alarm in the active alarms list
  defp update_alarm_in_list(alarms, updated_alarm) do
    case Enum.find_index(alarms, &(&1.id == updated_alarm.id)) do
      nil -> alarms
      idx -> List.replace_at(alarms, idx, updated_alarm)
    end
  end

  # Alarm action event handlers
  def handle_event("acknowledge_alarm", %{"id" => alarm_id}, socket) do
    user = socket.assigns.current_scope.user
    alarm = Alarms.get_alarm!(alarm_id)

    case Alarms.acknowledge_alarm(alarm, user.id) do
      {:ok, updated_alarm} ->
        broadcast_alarm_update(socket.assigns.mission.id, updated_alarm)

        {:noreply,
         socket
         |> put_flash(:info, "Alarm acknowledged")}

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

        {:noreply,
         socket
         |> put_flash(:info, "Alarm unshelved")}

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

        {:noreply,
         socket
         |> put_flash(:info, "Alarm cleared")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to clear alarm")}
    end
  end

  defp broadcast_alarm_update(mission_id, alarm) do
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "mission:#{mission_id}:alarms",
      {:alarm_updated, alarm}
    )
  end

  # Private functions

  defp default_widget_size("line_chart", :w), do: 6
  defp default_widget_size("line_chart", :h), do: 3
  defp default_widget_size("value_display", :w), do: 3
  defp default_widget_size("value_display", :h), do: 2
  defp default_widget_size("gauge", :w), do: 3
  defp default_widget_size("gauge", :h), do: 3
  defp default_widget_size("table", :w), do: 6
  defp default_widget_size("table", :h), do: 4
  defp default_widget_size(_type, :w), do: 4
  defp default_widget_size(_type, :h), do: 2

  defp generate_socket_token(user) do
    Phoenix.Token.sign(CadenceWeb.Endpoint, "user socket", user.id)
  end

  defp target_json(target) do
    %{
      id: target.id,
      identifier: target.identifier,
      name: target.name
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
