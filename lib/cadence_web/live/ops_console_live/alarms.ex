defmodule CadenceWeb.OpsConsoleLive.Alarms do
  @moduledoc """
  Alarms mode for OPS Console.

  Provides:
  - Active alarms grouped by severity
  - Annunciator panel view
  - Historical alarm search
  - Alarm rules management
  - Analytics dashboard
  """

  use CadenceWeb, :live_view

  alias Cadence.{Alarms, Commands, Targets}

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.mission
    mission_id = mission.id

    # Load targets
    targets = Targets.list_targets(mission)

    # Load active alarms
    active_alarms = Alarms.list_active_alarms(mission_id)

    # Group alarms by severity
    grouped_alarms = group_alarms_by_severity(active_alarms)

    # Calculate counts
    alarm_counts = calculate_alarm_counts(active_alarms)

    # Load data for layout (status bar and context panel)
    queue_entries = build_context_queue_entries(mission_id, targets)

    fleet_health = calculate_fleet_health(targets)

    # Subscribe to alarm and queue updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:queue")
      :timer.send_interval(1000, self(), :tick)
    end

    socket =
      socket
      |> assign(:page_title, "Alarms - #{mission.name}")
      |> assign(:targets, targets)
      |> assign(:active_alarms, active_alarms)
      |> assign(:alarms, active_alarms)
      |> assign(:grouped_alarms, grouped_alarms)
      |> assign(:alarm_counts, alarm_counts)
      |> assign(:selected_targets, MapSet.new())
      |> assign(:selected_alarm, nil)
      |> assign(:filter_status, MapSet.new(["active"]))
      |> assign(:filter_severity, MapSet.new(["critical", "warning", "info"]))
      |> assign(:collapsed_groups, MapSet.new())
      |> assign(:target_search, "")
      |> assign(:target_view_mode, "compact")
      |> assign(:show_shelve_modal, nil)
      # Layout data
      |> assign(:queue_entries, queue_entries)
      |> assign(:fleet_health, fleet_health)
      |> assign(:running_procedures, [])
      |> assign(:current_time, DateTime.utc_now())
      |> assign(:dashboards, [])
      |> assign(:current_mode, :alarms)

    {:ok, socket, layout: {CadenceWeb.Layouts, :ops_console_mode}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="alarms-mode-container">
      <div class="alarms-mode-layout">
        <!-- View Tabs -->
        <div class="alarms-view-tabs">
          <.link
            patch={~p"/missions/#{@mission.id}/ops/alarms"}
            class={["alarms-view-tab", @live_action == :active && "active"]}
          >
            ACTIVE
          </.link>
          <.link
            patch={~p"/missions/#{@mission.id}/ops/alarms/panel"}
            class={["alarms-view-tab", @live_action == :panel && "active"]}
          >
            PANEL
          </.link>
          <.link
            patch={~p"/missions/#{@mission.id}/ops/alarms/history"}
            class={["alarms-view-tab", @live_action == :historical && "active"]}
          >
            HISTORICAL
          </.link>
          <.link
            patch={~p"/missions/#{@mission.id}/ops/alarms/rules"}
            class={["alarms-view-tab", @live_action == :rules && "active"]}
          >
            RULES
          </.link>
          <.link
            patch={~p"/missions/#{@mission.id}/ops/alarms/analytics"}
            class={["alarms-view-tab", @live_action == :analytics && "active"]}
          >
            ANALYTICS
          </.link>
        </div>
        
    <!-- View Content -->
        <%= case @live_action do %>
          <% :active -> %>
            <.active_view
              targets={@targets}
              grouped_alarms={@grouped_alarms}
              selected_targets={@selected_targets}
              selected_alarm={@selected_alarm}
              filter_status={@filter_status}
              filter_severity={@filter_severity}
              collapsed_groups={@collapsed_groups}
              target_search={@target_search}
              target_view_mode={@target_view_mode}
              active_alarms={@active_alarms}
            />
          <% :panel -> %>
            <.panel_view targets={@targets} active_alarms={@active_alarms} />
          <% :historical -> %>
            <.historical_view />
          <% :rules -> %>
            <.rules_view />
          <% :analytics -> %>
            <.analytics_view />
          <% _ -> %>
            <.active_view
              targets={@targets}
              grouped_alarms={@grouped_alarms}
              selected_targets={@selected_targets}
              selected_alarm={@selected_alarm}
              filter_status={@filter_status}
              filter_severity={@filter_severity}
              collapsed_groups={@collapsed_groups}
              target_search={@target_search}
              target_view_mode={@target_view_mode}
              active_alarms={@active_alarms}
            />
        <% end %>
      </div>
    </div>

    <!-- Shelve Modal -->
    <.modal
      :if={@show_shelve_modal}
      id="shelve-modal"
      show={true}
      on_cancel={JS.push("close_shelve_modal")}
    >
      <.header>Shelve Alarm</.header>
      <.simple_form for={%{}} phx-submit="confirm_shelve">
        <.input
          name="duration"
          type="select"
          label="Shelve Duration"
          options={[
            {"15 minutes", "15"},
            {"30 minutes", "30"},
            {"1 hour", "60"},
            {"4 hours", "240"},
            {"8 hours", "480"},
            {"24 hours", "1440"}
          ]}
          value="60"
        />
        <.input name="reason" type="text" label="Reason (optional)" />
        <:actions>
          <.button type="submit" phx-disable-with="Shelving...">Shelve Alarm</.button>
        </:actions>
      </.simple_form>
    </.modal>
    """
  end

  # Active View - Three panel layout
  attr :targets, :list, required: true
  attr :grouped_alarms, :map, required: true
  attr :selected_targets, :any, required: true
  attr :selected_alarm, :map, default: nil
  attr :filter_status, :any, required: true
  attr :filter_severity, :any, required: true
  attr :collapsed_groups, :any, required: true
  attr :target_search, :string, required: true
  attr :target_view_mode, :string, required: true
  attr :active_alarms, :list, required: true

  defp active_view(assigns) do
    selected_count = MapSet.size(assigns.selected_targets)
    total_targets = length(assigns.targets)

    filtered_alarms =
      filter_alarms(
        assigns.active_alarms,
        assigns.filter_status,
        assigns.filter_severity,
        assigns.selected_targets
      )

    assigns =
      assigns
      |> assign(:selected_count, selected_count)
      |> assign(:total_targets, total_targets)
      |> assign(:filtered_alarms, filtered_alarms)
      |> assign(:filtered_count, length(filtered_alarms))
      |> assign(:active_count, Enum.count(filtered_alarms, &(&1.status == :active)))

    ~H"""
    <div class="alarms-panels-row" id="alarms-panels-row">
      <!-- Left Panel: Target Selection -->
      <div class="alarms-target-panel" id="alarms-target-panel" phx-hook=".AlarmsTargetPanel">
        <div class="alarms-panel-header">
          <div class="alarms-panel-title">
            <span class="mc-label-subsystem">TARGETS</span>
            <span class="alarms-selection-count">
              {if @selected_count == 0, do: "All", else: @selected_count} of {@total_targets}
            </span>
          </div>
          <div class="alarms-view-toggle">
            <button
              type="button"
              class={["alarms-view-btn", @target_view_mode == "compact" && "active"]}
              phx-click="set_target_view_mode"
              phx-value-mode="compact"
              title="Compact view"
            >
              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 6h16M4 10h16M4 14h16M4 18h16"
                />
              </svg>
            </button>
            <button
              type="button"
              class={["alarms-view-btn", @target_view_mode == "detailed" && "active"]}
              phx-click="set_target_view_mode"
              phx-value-mode="detailed"
              title="Detailed view"
            >
              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 6h16M4 12h16m-7 6h7"
                />
              </svg>
            </button>
          </div>
        </div>
        <div class="alarms-target-filters">
          <input
            type="text"
            class="alarms-target-search"
            id="alarms-target-search"
            placeholder="Filter targets..."
            value={@target_search}
            phx-keyup="filter_targets"
            phx-debounce="150"
          />
        </div>
        <div class={["alarms-target-grid", @target_view_mode == "detailed" && "detailed-view"]}>
          <.target_cell
            :for={target <- filter_targets(@targets, @target_search)}
            target={target}
            selected={MapSet.member?(@selected_targets, target.id)}
            alarm_counts={count_alarms_for_target(@active_alarms, target.id)}
            view_mode={@target_view_mode}
          />
        </div>
        <div class="alarms-selection-actions">
          <button type="button" class="btn btn-ghost btn-xs" phx-click="select_all_targets">
            Select All
          </button>
          <button type="button" class="btn btn-ghost btn-xs" phx-click="clear_target_selection">
            Clear
          </button>
        </div>
      </div>
      
    <!-- Resize Handle -->
      <div
        class="alarms-resize-handle"
        id="alarms-target-resize-handle"
        phx-hook=".AlarmsTargetResize"
      >
        <div class="alarms-resize-grip"></div>
      </div>
      
    <!-- Middle Panel: Alarm List -->
      <div class="alarms-list-panel" id="alarms-list-panel" phx-hook=".AlarmsListPanel">
        <div class="alarms-panel-header">
          <div class="alarms-panel-title">
            <span class="mc-label-subsystem">ALARMS</span>
            <span class="alarms-count">{@filtered_count} total</span>
          </div>
        </div>
        
    <!-- Filter Controls -->
        <div class="alarms-filters">
          <div class="alarms-filter-row">
            <div class="alarms-status-filters">
              <button
                type="button"
                class={["alarms-filter-btn", MapSet.member?(@filter_status, "active") && "active"]}
                phx-click="toggle_status_filter"
                phx-value-status="active"
              >
                ACTIVE
              </button>
              <button
                type="button"
                class={[
                  "alarms-filter-btn",
                  MapSet.member?(@filter_status, "acknowledged") && "active"
                ]}
                phx-click="toggle_status_filter"
                phx-value-status="acknowledged"
              >
                ACK
              </button>
              <button
                type="button"
                class={["alarms-filter-btn", MapSet.member?(@filter_status, "shelved") && "active"]}
                phx-click="toggle_status_filter"
                phx-value-status="shelved"
              >
                SHELVED
              </button>
            </div>
            <div class="alarms-severity-filters">
              <button
                type="button"
                class={[
                  "alarms-severity-btn severity-critical",
                  MapSet.member?(@filter_severity, "critical") && "active"
                ]}
                phx-click="toggle_severity_filter"
                phx-value-severity="critical"
                title="Critical"
              >
                C
              </button>
              <button
                type="button"
                class={[
                  "alarms-severity-btn severity-warning",
                  MapSet.member?(@filter_severity, "warning") && "active"
                ]}
                phx-click="toggle_severity_filter"
                phx-value-severity="warning"
                title="Warning"
              >
                W
              </button>
              <button
                type="button"
                class={[
                  "alarms-severity-btn severity-info",
                  MapSet.member?(@filter_severity, "info") && "active"
                ]}
                phx-click="toggle_severity_filter"
                phx-value-severity="info"
                title="Info"
              >
                I
              </button>
            </div>
          </div>
        </div>
        
    <!-- Alarm Groups -->
        <div class="alarms-list">
          <.alarm_group
            :for={severity <- [:critical, :warning, :info]}
            :if={length(Map.get(@grouped_alarms, severity, [])) > 0}
            severity={severity}
            alarms={filter_alarms_by_status(Map.get(@grouped_alarms, severity, []), @filter_status)}
            collapsed={MapSet.member?(@collapsed_groups, severity)}
            selected_alarm_id={@selected_alarm && @selected_alarm.id}
            targets={@targets}
          />
        </div>
        
    <!-- Bulk Actions -->
        <div class="alarms-bulk-actions">
          <button
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="acknowledge_all_visible"
            disabled={@active_count == 0}
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
            ACK ALL VISIBLE ({@active_count})
          </button>
        </div>
      </div>
      
    <!-- Resize Handle -->
      <div
        class="alarms-resize-handle"
        id="alarms-detail-resize-handle"
        phx-hook=".AlarmsDetailResize"
      >
        <div class="alarms-resize-grip"></div>
      </div>
      
    <!-- Right Panel: Alarm Detail -->
      <div class="alarms-detail-panel" id="alarms-detail-panel" phx-hook=".AlarmsDetailPanel">
        <.alarm_detail :if={@selected_alarm} alarm={@selected_alarm} targets={@targets} />
        <div :if={!@selected_alarm} class="alarms-detail-empty">
          <svg class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1.5"
              d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
            />
          </svg>
          <span>Select an alarm to view details</span>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".AlarmsTargetPanel">
        export default {
          mounted() {
            this.applySavedWidth()
          },

          updated() {
            this.applySavedWidth()
          },

          applySavedWidth() {
            const savedWidth = localStorage.getItem('alarms-target-panel-width')
            if (savedWidth) {
              this.el.style.flex = `0 0 ${savedWidth}`
            }
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".AlarmsTargetResize">
        export default {
          mounted() {
            this.isDragging = false
            this.startX = 0
            this.startWidth = 0
            this.targetPanel = document.getElementById('alarms-target-panel')
            this._startDrag = (event) => this.startDrag(event)
            this._onDrag = (event) => this.onDrag(event)
            this._endDrag = () => this.endDrag()
            this.el.addEventListener('mousedown', this._startDrag)
            document.addEventListener('mousemove', this._onDrag)
            document.addEventListener('mouseup', this._endDrag)
          },

          updated() {
            this.targetPanel = document.getElementById('alarms-target-panel')
            const savedWidth = localStorage.getItem('alarms-target-panel-width')
            if (savedWidth && this.targetPanel) {
              this.targetPanel.style.flex = `0 0 ${savedWidth}`
            }
          },

          startDrag(event) {
            if (!this.targetPanel) {
              this.targetPanel = document.getElementById('alarms-target-panel')
            }
            if (!this.targetPanel) return
            this.isDragging = true
            this.startX = event.clientX
            this.startWidth = this.targetPanel.offsetWidth
            document.body.style.cursor = 'col-resize'
            document.body.style.userSelect = 'none'
            this.el.classList.add('dragging')
          },

          onDrag(event) {
            if (!this.isDragging || !this.targetPanel) return
            const diff = event.clientX - this.startX
            const newWidth = Math.max(150, Math.min(500, this.startWidth + diff))
            this.targetPanel.style.flex = `0 0 ${newWidth}px`
            localStorage.setItem('alarms-target-panel-width', `${newWidth}px`)
          },

          endDrag() {
            if (!this.isDragging) return
            this.isDragging = false
            document.body.style.cursor = ''
            document.body.style.userSelect = ''
            this.el.classList.remove('dragging')
          },

          destroyed() {
            this.el.removeEventListener('mousedown', this._startDrag)
            document.removeEventListener('mousemove', this._onDrag)
            document.removeEventListener('mouseup', this._endDrag)
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".AlarmsListPanel">
        export default {
          mounted() {
            this.applySavedWidth()
          },

          updated() {
            this.applySavedWidth()
          },

          applySavedWidth() {
            const savedWidth = localStorage.getItem('alarms-list-panel-width')
            if (savedWidth) {
              this.el.style.flex = `0 0 ${savedWidth}`
            }
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".AlarmsDetailResize">
        export default {
          mounted() {
            this.isDragging = false
            this.startX = 0
            this.startWidth = 0
            this.listPanel = document.getElementById('alarms-list-panel')
            this._startDrag = (event) => this.startDrag(event)
            this._onDrag = (event) => this.onDrag(event)
            this._endDrag = () => this.endDrag()
            this.el.addEventListener('mousedown', this._startDrag)
            document.addEventListener('mousemove', this._onDrag)
            document.addEventListener('mouseup', this._endDrag)
          },

          updated() {
            this.listPanel = document.getElementById('alarms-list-panel')
            const savedWidth = localStorage.getItem('alarms-list-panel-width')
            if (savedWidth && this.listPanel) {
              this.listPanel.style.flex = `0 0 ${savedWidth}`
            }
          },

          startDrag(event) {
            if (!this.listPanel) {
              this.listPanel = document.getElementById('alarms-list-panel')
            }
            if (!this.listPanel) return
            this.isDragging = true
            this.startX = event.clientX
            this.startWidth = this.listPanel.offsetWidth
            document.body.style.cursor = 'col-resize'
            document.body.style.userSelect = 'none'
            this.el.classList.add('dragging')
          },

          onDrag(event) {
            if (!this.isDragging || !this.listPanel) return
            const diff = event.clientX - this.startX
            const newWidth = Math.max(200, Math.min(800, this.startWidth + diff))
            this.listPanel.style.flex = `0 0 ${newWidth}px`
            localStorage.setItem('alarms-list-panel-width', `${newWidth}px`)
          },

          endDrag() {
            if (!this.isDragging) return
            this.isDragging = false
            document.body.style.cursor = ''
            document.body.style.userSelect = ''
            this.el.classList.remove('dragging')
          },

          destroyed() {
            this.el.removeEventListener('mousedown', this._startDrag)
            document.removeEventListener('mousemove', this._onDrag)
            document.removeEventListener('mouseup', this._endDrag)
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".AlarmsDetailPanel">
        export default {
          mounted() {
            this.applySavedWidth()
          },

          updated() {
            this.applySavedWidth()
          },

          applySavedWidth() {
            const savedWidth = localStorage.getItem('alarms-detail-panel-width')
            if (savedWidth) {
              this.el.style.flex = `0 0 ${savedWidth}`
            }
          }
        }
      </script>
    </div>
    """
  end

  # Target cell component
  attr :target, :map, required: true
  attr :selected, :boolean, required: true
  attr :alarm_counts, :map, required: true
  attr :view_mode, :string, required: true

  defp target_cell(assigns) do
    status_class = assigns.target.status || :online
    has_alarms = assigns.alarm_counts.active > 0

    assigns =
      assigns
      |> assign(:status_class, status_class)
      |> assign(:has_alarms, has_alarms)

    ~H"""
    <div
      class={[
        "alarms-target-cell",
        @selected && "selected",
        "status-#{@status_class}",
        @has_alarms && "has-alarms"
      ]}
      phx-click="toggle_target"
      phx-value-id={@target.id}
    >
      <%= if @view_mode == "detailed" do %>
        <div class="alarms-target-main">
          <span class="alarms-target-name">{@target.name}</span>
          <span class="alarms-target-mode">{@target.mode || "NOMINAL"}</span>
        </div>
        <div class="alarms-target-meta">
          <span class="alarms-target-type">{@target.target_type || "Unknown"}</span>
          <span :if={@alarm_counts.total > 0} class="alarms-target-alarm-count">
            <span :if={@alarm_counts.active > 0} class="active">{@alarm_counts.active}</span>
            <span :if={@alarm_counts.ack > 0} class="ack">{@alarm_counts.ack}</span>
          </span>
        </div>
      <% else %>
        <span class="alarms-target-name">{@target.name}</span>
        <span :if={@alarm_counts.total > 0} class="alarms-target-count">{@alarm_counts.total}</span>
      <% end %>
    </div>
    """
  end

  # Alarm group component
  attr :severity, :atom, required: true
  attr :alarms, :list, required: true
  attr :collapsed, :boolean, required: true
  attr :selected_alarm_id, :string, default: nil
  attr :targets, :list, required: true

  defp alarm_group(assigns) do
    severity_label = %{critical: "CRITICAL", warning: "WARNING", info: "INFO"}

    assigns =
      assign(assigns, :severity_label, Map.get(severity_label, assigns.severity, "UNKNOWN"))

    ~H"""
    <div class={"alarms-group severity-#{@severity}"}>
      <div class="alarms-group-header" phx-click="toggle_group" phx-value-severity={@severity}>
        <svg
          class={["alarms-group-chevron", @collapsed && "collapsed"]}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
        <span class={"alarms-group-dot severity-#{@severity}"}></span>
        <span class="alarms-group-label">{@severity_label}</span>
        <span class="alarms-group-count">{length(@alarms)}</span>
      </div>
      <div class={["alarms-group-items", @collapsed && "collapsed"]}>
        <.alarm_row
          :for={alarm <- @alarms}
          alarm={alarm}
          selected={@selected_alarm_id == alarm.id}
          targets={@targets}
        />
      </div>
    </div>
    """
  end

  # Alarm row component
  attr :alarm, :map, required: true
  attr :selected, :boolean, required: true
  attr :targets, :list, required: true

  defp alarm_row(assigns) do
    target_name = find_target_name(assigns.targets, assigns.alarm.target_id)
    triggered_time = format_alarm_time(assigns.alarm.triggered_at)

    assigns =
      assigns
      |> assign(:target_name, target_name)
      |> assign(:triggered_time, triggered_time)

    ~H"""
    <div
      class={["alarms-row", @selected && "selected", "status-#{@alarm.status}"]}
      phx-click="select_alarm"
      phx-value-id={@alarm.id}
    >
      <div class="alarms-row-main">
        <span class={"alarms-row-status status-#{@alarm.status}"}></span>
        <div class="alarms-row-content">
          <div class="alarms-row-source">{@alarm.source_id || "Unknown"}</div>
          <div class="alarms-row-message">{@alarm.message || "No message"}</div>
        </div>
        <div class="alarms-row-meta">
          <span class="alarms-row-target">{@target_name}</span>
          <span class="alarms-row-time">{@triggered_time}</span>
        </div>
      </div>
      <div class="alarms-row-actions">
        <button
          :if={@alarm.status == :active}
          type="button"
          class="alarms-action-btn"
          phx-click="acknowledge_alarm"
          phx-value-id={@alarm.id}
          title="Acknowledge"
        >
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
        </button>
        <button
          :if={@alarm.status != :shelved}
          type="button"
          class="alarms-action-btn"
          phx-click="open_shelve_modal"
          phx-value-id={@alarm.id}
          title="Shelve"
        >
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </button>
        <button
          :if={@alarm.status == :shelved}
          type="button"
          class="alarms-action-btn"
          phx-click="unshelve_alarm"
          phx-value-id={@alarm.id}
          title="Unshelve"
        >
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  # Alarm detail component
  attr :alarm, :map, required: true
  attr :targets, :list, required: true

  defp alarm_detail(assigns) do
    target_name = find_target_name(assigns.targets, assigns.alarm.target_id)
    triggered_time = format_alarm_datetime(assigns.alarm.triggered_at)

    assigns =
      assigns
      |> assign(:target_name, target_name)
      |> assign(:triggered_time, triggered_time)

    ~H"""
    <div class="alarms-detail-content">
      <!-- Header -->
      <div class="alarms-detail-header">
        <div class="alarms-detail-title">
          <span class={"alarms-detail-severity severity-#{@alarm.severity}"}>
            {String.upcase(to_string(@alarm.severity))}
          </span>
          <span class="alarms-detail-source">{@alarm.source_id || "Unknown"}</span>
        </div>
        <span class={"alarms-detail-status status-#{@alarm.status}"}>
          {String.upcase(to_string(@alarm.status))}
        </span>
      </div>
      
    <!-- Message -->
      <div class="alarms-detail-section">
        <span class="alarms-detail-label">MESSAGE</span>
        <p class="alarms-detail-message">{@alarm.message || "No message provided"}</p>
      </div>
      
    <!-- Details Grid -->
      <div class="alarms-detail-grid">
        <div class="alarms-detail-item">
          <span class="alarms-detail-label">TARGET</span>
          <span class="alarms-detail-value">{@target_name}</span>
        </div>
        <div class="alarms-detail-item">
          <span class="alarms-detail-label">TRIGGERED</span>
          <span class="alarms-detail-value">{@triggered_time}</span>
        </div>
        <div :if={@alarm.current_value} class="alarms-detail-item">
          <span class="alarms-detail-label">VALUE</span>
          <span class="alarms-detail-value">{@alarm.current_value}</span>
        </div>
        <div :if={@alarm.limit_value} class="alarms-detail-item">
          <span class="alarms-detail-label">LIMIT</span>
          <span class="alarms-detail-value">{@alarm.limit_value}</span>
        </div>
      </div>
      
    <!-- Actions -->
      <div class="alarms-detail-actions">
        <button
          :if={@alarm.status == :active}
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="acknowledge_alarm"
          phx-value-id={@alarm.id}
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
          Acknowledge
        </button>
        <button
          :if={@alarm.status != :shelved}
          type="button"
          class="btn btn-ghost btn-sm"
          phx-click="open_shelve_modal"
          phx-value-id={@alarm.id}
        >
          Shelve
        </button>
        <button
          :if={@alarm.status == :shelved}
          type="button"
          class="btn btn-ghost btn-sm"
          phx-click="unshelve_alarm"
          phx-value-id={@alarm.id}
        >
          Unshelve
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          phx-click="clear_alarm"
          phx-value-id={@alarm.id}
        >
          Clear
        </button>
      </div>
    </div>
    """
  end

  # Panel view - Annunciator panel
  attr :targets, :list, required: true
  attr :active_alarms, :list, required: true

  defp panel_view(assigns) do
    ~H"""
    <div class="alarms-panel-view">
      <p class="text-base-content/50 p-4">Annunciator panel view coming soon...</p>
    </div>
    """
  end

  # Historical view
  defp historical_view(assigns) do
    ~H"""
    <div class="alarms-historical-view">
      <p class="text-base-content/50 p-4">Historical alarms view coming soon...</p>
    </div>
    """
  end

  # Rules view
  defp rules_view(assigns) do
    ~H"""
    <div class="alarms-rules-view">
      <p class="text-base-content/50 p-4">Alarm rules configuration coming soon...</p>
    </div>
    """
  end

  # Analytics view
  defp analytics_view(assigns) do
    ~H"""
    <div class="alarms-analytics-view">
      <p class="text-base-content/50 p-4">Alarm analytics dashboard coming soon...</p>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("toggle_target", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_targets, id) do
        MapSet.delete(socket.assigns.selected_targets, id)
      else
        MapSet.put(socket.assigns.selected_targets, id)
      end

    {:noreply, assign(socket, :selected_targets, selected)}
  end

  def handle_event("select_all_targets", _, socket) do
    all_ids = socket.assigns.targets |> Enum.map(& &1.id) |> MapSet.new()
    {:noreply, assign(socket, :selected_targets, all_ids)}
  end

  def handle_event("clear_target_selection", _, socket) do
    {:noreply, assign(socket, :selected_targets, MapSet.new())}
  end

  def handle_event("filter_targets", %{"value" => value}, socket) do
    {:noreply, assign(socket, :target_search, value)}
  end

  def handle_event("set_target_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :target_view_mode, mode)}
  end

  def handle_event("toggle_status_filter", %{"status" => status}, socket) do
    filter =
      if MapSet.member?(socket.assigns.filter_status, status) do
        MapSet.delete(socket.assigns.filter_status, status)
      else
        MapSet.put(socket.assigns.filter_status, status)
      end

    {:noreply, assign(socket, :filter_status, filter)}
  end

  def handle_event("toggle_severity_filter", %{"severity" => severity}, socket) do
    filter =
      if MapSet.member?(socket.assigns.filter_severity, severity) do
        MapSet.delete(socket.assigns.filter_severity, severity)
      else
        MapSet.put(socket.assigns.filter_severity, severity)
      end

    {:noreply, assign(socket, :filter_severity, filter)}
  end

  def handle_event("toggle_group", %{"severity" => severity}, socket) do
    severity_atom = String.to_existing_atom(severity)

    collapsed =
      if MapSet.member?(socket.assigns.collapsed_groups, severity_atom) do
        MapSet.delete(socket.assigns.collapsed_groups, severity_atom)
      else
        MapSet.put(socket.assigns.collapsed_groups, severity_atom)
      end

    {:noreply, assign(socket, :collapsed_groups, collapsed)}
  end

  def handle_event("select_alarm", %{"id" => id}, socket) do
    alarm = Enum.find(socket.assigns.active_alarms, &(&1.id == id))
    {:noreply, assign(socket, :selected_alarm, alarm)}
  end

  def handle_event("acknowledge_alarm", %{"id" => id}, socket) do
    alarm = Alarms.get_alarm!(id)
    user = socket.assigns.current_scope.user

    case Alarms.acknowledge_alarm(alarm, user.id) do
      {:ok, updated_alarm} ->
        active_alarms = update_alarm_in_list(socket.assigns.active_alarms, updated_alarm)
        grouped_alarms = group_alarms_by_severity(active_alarms)

        {:noreply,
         socket
         |> assign(:active_alarms, active_alarms)
         |> assign(:grouped_alarms, grouped_alarms)
         |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to acknowledge alarm")}
    end
  end

  def handle_event("acknowledge_all_visible", _, socket) do
    user = socket.assigns.current_scope.user

    filtered =
      filter_alarms(
        socket.assigns.active_alarms,
        socket.assigns.filter_status,
        socket.assigns.filter_severity,
        socket.assigns.selected_targets
      )

    active_alarms =
      Enum.reduce(filtered, socket.assigns.active_alarms, fn alarm, acc ->
        if alarm.status == :active do
          case Alarms.acknowledge_alarm(alarm, user.id) do
            {:ok, updated} -> update_alarm_in_list(acc, updated)
            _ -> acc
          end
        else
          acc
        end
      end)

    grouped_alarms = group_alarms_by_severity(active_alarms)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> assign(:grouped_alarms, grouped_alarms)
     |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}
  end

  def handle_event("open_shelve_modal", %{"id" => id}, socket) do
    {:noreply, assign(socket, :show_shelve_modal, id)}
  end

  def handle_event("close_shelve_modal", _, socket) do
    {:noreply, assign(socket, :show_shelve_modal, nil)}
  end

  def handle_event("confirm_shelve", %{"duration" => duration, "reason" => reason}, socket) do
    alarm_id = socket.assigns.show_shelve_modal
    duration_minutes = String.to_integer(duration)

    case Alarms.shelve_alarm(
           alarm_id,
           socket.assigns.current_scope.user,
           duration_minutes,
           reason
         ) do
      {:ok, updated_alarm} ->
        active_alarms = update_alarm_in_list(socket.assigns.active_alarms, updated_alarm)
        grouped_alarms = group_alarms_by_severity(active_alarms)

        {:noreply,
         socket
         |> assign(:active_alarms, active_alarms)
         |> assign(:grouped_alarms, grouped_alarms)
         |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))
         |> assign(:show_shelve_modal, nil)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to shelve alarm")
         |> assign(:show_shelve_modal, nil)}
    end
  end

  def handle_event("unshelve_alarm", %{"id" => id}, socket) do
    case Alarms.unshelve_alarm(id) do
      {:ok, updated_alarm} ->
        active_alarms = update_alarm_in_list(socket.assigns.active_alarms, updated_alarm)
        grouped_alarms = group_alarms_by_severity(active_alarms)

        {:noreply,
         socket
         |> assign(:active_alarms, active_alarms)
         |> assign(:grouped_alarms, grouped_alarms)
         |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unshelve alarm")}
    end
  end

  def handle_event("clear_alarm", %{"id" => id}, socket) do
    alarm = Alarms.get_alarm!(id)
    user = socket.assigns.current_scope.user

    case Alarms.clear_alarm(alarm, user.id) do
      {:ok, _cleared_alarm} ->
        active_alarms = Enum.reject(socket.assigns.active_alarms, &(&1.id == id))
        grouped_alarms = group_alarms_by_severity(active_alarms)

        selected_alarm =
          if socket.assigns.selected_alarm && socket.assigns.selected_alarm.id == id do
            nil
          else
            socket.assigns.selected_alarm
          end

        {:noreply,
         socket
         |> assign(:active_alarms, active_alarms)
         |> assign(:grouped_alarms, grouped_alarms)
         |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))
         |> assign(:selected_alarm, selected_alarm)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to clear alarm")}
    end
  end

  # PubSub handlers
  @impl true
  def handle_info({:alarm_triggered, alarm}, socket) do
    active_alarms = [alarm | socket.assigns.active_alarms]
    grouped_alarms = group_alarms_by_severity(active_alarms)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> assign(:alarms, active_alarms)
     |> assign(:grouped_alarms, grouped_alarms)
     |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}
  end

  def handle_info({:alarm_updated, alarm}, socket) do
    active_alarms = update_alarm_in_list(socket.assigns.active_alarms, alarm)
    grouped_alarms = group_alarms_by_severity(active_alarms)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> assign(:alarms, active_alarms)
     |> assign(:grouped_alarms, grouped_alarms)
     |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}
  end

  def handle_info({:alarm_cleared, alarm}, socket) do
    active_alarms = Enum.reject(socket.assigns.active_alarms, &(&1.id == alarm.id))
    grouped_alarms = group_alarms_by_severity(active_alarms)

    {:noreply,
     socket
     |> assign(:active_alarms, active_alarms)
     |> assign(:alarms, active_alarms)
     |> assign(:grouped_alarms, grouped_alarms)
     |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}
  end

  def handle_info({:queue_updated, _entry}, socket) do
    {:noreply, refresh_queue_entries(socket)}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :current_time, DateTime.utc_now())}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # Private helpers

  defp group_alarms_by_severity(alarms) do
    %{
      critical: Enum.filter(alarms, &(&1.severity == :critical)),
      warning: Enum.filter(alarms, &(&1.severity == :warning)),
      info: Enum.filter(alarms, &(&1.severity == :info))
    }
  end

  defp calculate_alarm_counts(alarms) do
    %{
      critical: Enum.count(alarms, &(&1.severity == :critical)),
      warning: Enum.count(alarms, &(&1.severity == :warning)),
      info: Enum.count(alarms, &(&1.severity == :info))
    }
  end

  defp calculate_fleet_health(targets) do
    total = length(targets)

    if total == 0 do
      %{healthy: 0, degraded: 0, offline: 0, total: 0, percentage: 100}
    else
      healthy = Enum.count(targets, &(&1.status in [:nominal, :active, :online]))
      degraded = Enum.count(targets, &(&1.status in [:degraded, :warning, :standby]))
      offline = total - healthy - degraded

      %{
        healthy: healthy,
        degraded: degraded,
        offline: offline,
        total: total,
        percentage: round(healthy / total * 100)
      }
    end
  end

  defp refresh_queue_entries(socket) do
    mission_id = socket.assigns.mission.id
    targets = socket.assigns.targets

    queue_entries = build_context_queue_entries(mission_id, targets)
    assign(socket, :queue_entries, queue_entries)
  end

  defp build_context_queue_entries(mission_id, targets) do
    entries =
      Commands.list_queue_entries(mission_id,
        status: [:pending, :executing],
        limit: 50
      )

    attach_targets_to_queue_entries(entries, targets)
  end

  defp attach_targets_to_queue_entries(queue_entries, targets) do
    targets_by_id = Map.new(targets, &{&1.id, &1})

    Enum.map(queue_entries, fn entry ->
      target = Map.get(targets_by_id, entry.target_id)

      entry
      |> Map.from_struct()
      |> Map.put(:target, target)
    end)
  end

  defp filter_targets(targets, search) do
    if search == "" do
      targets
    else
      search_lower = String.downcase(search)
      Enum.filter(targets, fn t -> String.contains?(String.downcase(t.name), search_lower) end)
    end
  end

  defp count_alarms_for_target(alarms, target_id) do
    target_alarms = Enum.filter(alarms, &(&1.target_id == target_id))

    %{
      total: length(target_alarms),
      active: Enum.count(target_alarms, &(&1.status == :active)),
      ack: Enum.count(target_alarms, &(&1.status == :acknowledged))
    }
  end

  defp filter_alarms(alarms, filter_status, filter_severity, selected_targets) do
    alarms
    |> Enum.filter(fn alarm ->
      status_match = MapSet.member?(filter_status, to_string(alarm.status))
      severity_match = MapSet.member?(filter_severity, to_string(alarm.severity))

      target_match =
        MapSet.size(selected_targets) == 0 or MapSet.member?(selected_targets, alarm.target_id)

      status_match and severity_match and target_match
    end)
  end

  defp filter_alarms_by_status(alarms, filter_status) do
    Enum.filter(alarms, fn alarm ->
      MapSet.member?(filter_status, to_string(alarm.status))
    end)
  end

  defp find_target_name(_targets, nil), do: "System"

  defp find_target_name(targets, target_id) do
    case Enum.find(targets, &(&1.id == target_id)) do
      nil -> "Unknown"
      target -> target.name
    end
  end

  defp format_alarm_time(nil), do: "—"

  defp format_alarm_time(time) do
    diff = DateTime.diff(DateTime.utc_now(), time, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> Calendar.strftime(time, "%m/%d %H:%M")
    end
  end

  defp format_alarm_datetime(nil), do: "—"

  defp format_alarm_datetime(time) do
    Calendar.strftime(time, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp update_alarm_in_list(alarms, updated_alarm) do
    Enum.map(alarms, fn alarm ->
      if alarm.id == updated_alarm.id, do: updated_alarm, else: alarm
    end)
  end
end
