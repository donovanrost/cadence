defmodule CadenceWeb.OpsConsoleLive.Timeline do
  @moduledoc """
  Timeline mode for OPS Console.

  Provides:
  - Stream view - chronological event stream
  - Matrix view - targets x time grid
  - Lanes view - horizontal timeline per target

  Uses CSS from assets/css/modes/timeline-mode.css
  """

  use CadenceWeb, :live_view

  alias Cadence.{Alarms, Commands, Targets, Timeline}
  import CadenceWeb.OpsConsoleLive.Components

  @event_types [:command, :alarm, :procedure, :automation]
  @events_page_size 100
  @lanes_fetch_limit 1000
  @max_cached_events 500

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.mission
    mission_id = mission.id

    # Load targets
    targets = Targets.list_targets(mission)

    # Load recent timeline events
    events = Timeline.list_recent_events(mission_id, 120, limit: @events_page_size)

    # Load data for layout (status bar and context panel)
    active_alarms = Alarms.list_active_alarms(mission_id)
    alarm_counts = calculate_alarm_counts(active_alarms)

    queue_entries = build_context_queue_entries(mission_id, targets)

    fleet_health = calculate_fleet_health(targets)

    # Subscribe to timeline, alarm, and queue updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:timeline")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:queue")
      :timer.send_interval(1000, self(), :tick)
    end

    # Default all event type filters to active
    event_type_filters =
      Enum.reduce(@event_types, %{}, fn type, acc -> Map.put(acc, type, true) end)

    socket =
      socket
      |> assign(:page_title, "Timeline - #{mission.name}")
      |> assign(:targets, targets)
      |> stream(:events, events)
      |> assign(:events_list, events)
      |> assign(:selected_targets, MapSet.new())
      |> assign(:event_type_filters, event_type_filters)
      |> assign(:target_search, "")
      |> assign(:expanded_events, MapSet.new())
      |> assign(:event_histories, %{})
      |> assign(:has_more_events, length(events) >= @events_page_size)
      |> assign(:follow_mode, true)
      |> assign(:time_range, "1h")
      # Layout data
      |> assign(:alarm_counts, alarm_counts)
      |> assign(:alarms, active_alarms)
      |> assign(:queue_entries, queue_entries)
      |> assign(:fleet_health, fleet_health)
      |> assign(:running_procedures, [])
      |> assign(:current_time, DateTime.utc_now())
      |> assign(:lanes_offset_minutes, 0)
      |> assign(:lanes_events, events)
      |> assign(:dashboards, [])
      |> assign(:current_mode, :timeline)
      |> assign(:lanes_scrubbing?, false)
      |> assign(:show_system_events, true)

    {:ok, socket, layout: {CadenceWeb.Layouts, :ops_console_mode}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="timeline-mode-container">
      <div class="timeline-mode-layout">
        <%= case @live_action do %>
          <% :stream -> %>
            <.timeline_stream_view
              targets={@targets}
              selected_targets={@selected_targets}
              target_search={@target_search}
              streams={@streams}
              event_type_filters={@event_type_filters}
              expanded_events={@expanded_events}
              event_histories={@event_histories}
              has_more={@has_more_events}
              current_time={@current_time}
            />
          <% :matrix -> %>
            <.timeline_matrix_view
              targets={@targets}
              selected_targets={@selected_targets}
              target_search={@target_search}
              streams={@streams}
              time_range={@time_range}
            />
          <% :lanes -> %>
            <.timeline_lanes_view
              targets={@targets}
              selected_targets={@selected_targets}
              target_search={@target_search}
              events={@lanes_events}
              time_range={@time_range}
              current_time={@current_time}
              lanes_offset_minutes={@lanes_offset_minutes}
              show_system_events={@show_system_events}
            />
        <% end %>
        
    <!-- Timeline Controls Bar -->
        <.timeline_controls
          live_action={@live_action}
          mission_id={@mission.id}
          event_type_filters={@event_type_filters}
          follow_mode={@follow_mode}
          time_range={@time_range}
        />
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".TimelineStream">
      export default {
        mounted() {
          this.updateRelativeTimes()
          this._interval = setInterval(() => this.updateRelativeTimes(), 1000)
        },

        updated() {
          this.updateRelativeTimes()
        },

        destroyed() {
          if (this._interval) {
            clearInterval(this._interval)
            this._interval = null
          }
        },

        updateRelativeTimes() {
          const now = Date.now()
          this.el.querySelectorAll('.timeline-event-relative[data-timestamp]').forEach((el) => {
            const timestamp = el.dataset.timestamp
            if (!timestamp) return
            const parsed = Date.parse(timestamp)
            if (Number.isNaN(parsed)) return
            const diffSeconds = Math.floor((now - parsed) / 1000)
            el.textContent = this.formatRelative(diffSeconds)
          })
        },

        formatRelative(diffSeconds) {
          if (diffSeconds < 0) {
            return `in ${Math.abs(diffSeconds)}s`
          }
          if (diffSeconds < 60) {
            return `${diffSeconds}s ago`
          }
          if (diffSeconds < 3600) {
            return `${Math.floor(diffSeconds / 60)}m ago`
          }
          if (diffSeconds < 86400) {
            return `${Math.floor(diffSeconds / 3600)}h ago`
          }
          return `${Math.floor(diffSeconds / 86400)}d ago`
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".StreamPanelResize">
      export default {
        mounted() {
          this.isDragging = false
          this.startX = 0
          this.startWidth = 0
          this.targetPanel = document.querySelector('.stream-target-filter-panel')
          this._startDrag = (event) => this.startDrag(event)
          this._onDrag = (event) => this.onDrag(event)
          this._endDrag = () => this.endDrag()
          this.el.addEventListener('mousedown', this._startDrag)
          document.addEventListener('mousemove', this._onDrag)
          document.addEventListener('mouseup', this._endDrag)

          // Load saved width
          const savedWidth = localStorage.getItem('stream-target-panel-width')
          if (savedWidth && this.targetPanel) {
            this.targetPanel.style.flex = `0 0 ${savedWidth}px`
          }
        },

        updated() {
          // Re-query the target panel in case it was replaced
          this.targetPanel = document.querySelector('.stream-target-filter-panel')
          // Reapply saved width after LiveView DOM patches
          const savedWidth = localStorage.getItem('stream-target-panel-width')
          if (savedWidth && this.targetPanel) {
            this.targetPanel.style.flex = `0 0 ${savedWidth}px`
          }
        },

        startDrag(event) {
          if (!this.targetPanel) {
            this.targetPanel = document.querySelector('.stream-target-filter-panel')
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
          const container = this.targetPanel.parentElement
          if (!container) return
          const diff = event.clientX - this.startX
          // Clamp between CSS min (150px) and max (400px) values
          const newWidth = Math.max(150, Math.min(400, this.startWidth + diff))
          this.targetPanel.style.flex = `0 0 ${newWidth}px`
          localStorage.setItem('stream-target-panel-width', newWidth)
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
    """
  end

  # ============================================================================
  # Timeline Controls (Bottom Bar)
  # ============================================================================

  attr :live_action, :atom, required: true
  attr :mission_id, :string, required: true
  attr :event_type_filters, :map, required: true
  attr :follow_mode, :boolean, required: true
  attr :time_range, :string, required: true

  defp timeline_controls(assigns) do
    ~H"""
    <div class="timeline-controls">
      <div class="timeline-view-tabs">
        <.link
          navigate={~p"/missions/#{@mission_id}/ops/timeline"}
          class={["timeline-view-tab", @live_action == :stream && "active"]}
        >
          Stream
        </.link>
        <.link
          navigate={~p"/missions/#{@mission_id}/ops/timeline/matrix"}
          class={["timeline-view-tab", @live_action == :matrix && "active"]}
        >
          Matrix
        </.link>
        <.link
          navigate={~p"/missions/#{@mission_id}/ops/timeline/lanes"}
          class={["timeline-view-tab", @live_action == :lanes && "active"]}
        >
          Lanes
        </.link>
      </div>

      <div class="timeline-filters">
        <span
          class={["timeline-filter-toggle", @event_type_filters[:command] && "active"]}
          phx-click="toggle_event_filter"
          phx-value-type="command"
        >
          <span class="filter-badge filter-badge-command">CMD</span>
        </span>
        <span
          class={["timeline-filter-toggle", @event_type_filters[:alarm] && "active"]}
          phx-click="toggle_event_filter"
          phx-value-type="alarm"
        >
          <span class="filter-badge filter-badge-alarm">ALM</span>
        </span>
        <span
          class={["timeline-filter-toggle", @event_type_filters[:procedure] && "active"]}
          phx-click="toggle_event_filter"
          phx-value-type="procedure"
        >
          <span class="filter-badge filter-badge-procedure">PRC</span>
        </span>
        <span
          class={["timeline-filter-toggle", @event_type_filters[:automation] && "active"]}
          phx-click="toggle_event_filter"
          phx-value-type="automation"
        >
          <span class="filter-badge filter-badge-automation">AUT</span>
        </span>
      </div>

      <div :if={@live_action in [:matrix, :lanes]} class="timeline-matrix-controls">
        <select class="timeline-select" phx-change="set_time_range">
          <option value="1h" selected={@time_range == "1h"}>1 Hour</option>
          <option value="4h" selected={@time_range == "4h"}>4 Hours</option>
          <option value="12h" selected={@time_range == "12h"}>12 Hours</option>
          <option value="24h" selected={@time_range == "24h"}>24 Hours</option>
        </select>
      </div>

      <div class="timeline-actions">
        <button
          type="button"
          class={["timeline-action-btn", @follow_mode && "active"]}
          phx-click="toggle_follow"
          title="Follow Mode"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M13 5l7 7-7 7M5 5l7 7-7 7"
            />
          </svg>
        </button>
        <button type="button" class="timeline-action-btn" phx-click="jump_to_now">
          NOW
        </button>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Stream View
  # ============================================================================

  attr :targets, :list, required: true
  attr :selected_targets, :any, required: true
  attr :target_search, :string, required: true
  attr :streams, :map, required: true
  attr :event_type_filters, :map, required: true
  attr :expanded_events, :any, required: true
  attr :event_histories, :map, required: true
  attr :has_more, :boolean, default: false
  attr :current_time, :any, required: true

  defp timeline_stream_view(assigns) do
    filtered_targets =
      if assigns.target_search == "" do
        assigns.targets
      else
        search_lower = String.downcase(assigns.target_search)

        Enum.filter(assigns.targets, fn t ->
          String.contains?(String.downcase(t.name || ""), search_lower)
        end)
      end

    assigns = assign(assigns, :filtered_targets, filtered_targets)

    ~H"""
    <div class="timeline-stream-enhanced">
      <div class="stream-split-layout">
        <!-- Target Filter Panel -->
        <div class="stream-target-filter-panel">
          <div class="stream-target-filter-header">
            <div class="stream-filter-title">
              <span class="stream-filter-title-text">TARGETS</span>
            </div>
            <span class="stream-filter-count">
              {MapSet.size(@selected_targets)}/{length(@targets)}
            </span>
          </div>

          <div class="stream-target-search-wrapper">
            <input
              type="text"
              class="stream-target-search"
              placeholder="Search..."
              value={@target_search}
              phx-keyup="filter_targets"
              phx-debounce="150"
            />
          </div>

          <div class="stream-target-grid">
            <.stream_target_cell
              :for={target <- @filtered_targets}
              target={target}
              selected={MapSet.member?(@selected_targets, target.id)}
            />
          </div>

          <div class="stream-filter-actions-footer">
            <button type="button" class="stream-filter-action" phx-click="clear_target_filter">
              Clear
            </button>
            <button type="button" class="stream-filter-action" phx-click="select_all_targets">
              All
            </button>
          </div>
        </div>
        
    <!-- Resize Handle -->
        <div
          class="stream-resize-handle"
          id="stream-resize"
          phx-hook=".StreamPanelResize"
          phx-update="ignore"
        >
        </div>
        
    <!-- Main Stream Panel -->
        <div class="stream-hud-panel">
          <div class="stream-hud-corners"></div>
          
    <!-- NOW Marker -->
          <div class="timeline-now-marker">
            <div class="timeline-now-line"></div>
            <span class="timeline-now-label">NOW</span>
            <div class="timeline-now-line"></div>
          </div>
          
    <!-- Event Stream with Timeline Spine -->
          <div
            id="event-stream"
            class="timeline-events-list"
            phx-hook=".TimelineStream"
            data-has-more={to_string(@has_more)}
          >
            <div class="timeline-spine-container">
              <div class="timeline-spine"></div>
              <div id="event-list" phx-update="stream">
                <.timeline_event
                  :for={{dom_id, event} <- @streams.events}
                  dom_id={dom_id}
                  event={event}
                  expanded={MapSet.member?(@expanded_events, event.id)}
                  history={Map.get(@event_histories, event.id, [])}
                />
              </div>
            </div>

            <div :if={@has_more} class="text-center py-4">
              <button type="button" class="timeline-action-btn" phx-click="load_more">
                Load More
              </button>
            </div>
          </div>

          <div :if={stream_empty?(@streams)} class="timeline-empty-state">
            No events match current filters
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :target, :map, required: true
  attr :selected, :boolean, required: true

  defp stream_target_cell(assigns) do
    status_class =
      case assigns.target.status do
        s when s in [:nominal, :active, :online] -> "status-online"
        s when s in [:degraded, :warning, :standby] -> "status-standby"
        _ -> "status-offline"
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <div
      class={["stream-target-cell", @status_class, @selected && "selected"]}
      phx-click="toggle_target_filter"
      phx-value-id={@target.id}
    >
      <span class="stream-target-name">{@target.name}</span>
    </div>
    """
  end

  attr :dom_id, :string, required: true
  attr :event, :map, required: true
  attr :expanded, :boolean, default: false
  attr :history, :list, default: []

  defp timeline_event(assigns) do
    event_type = assigns.event.type || :command
    # Events from recordings can potentially have state history
    # Scheduled commands (source_table: :command_queue_entries) don't have history yet
    can_expand = assigns.event.source_table == :recordings
    has_loaded_history = length(assigns.history) > 0

    assigns =
      assigns
      |> assign(:event_type, event_type)
      |> assign(:type_class, "timeline-event-#{event_type}")
      |> assign(:badge_class, "timeline-badge-#{event_type}")
      |> assign(:can_expand, can_expand)
      |> assign(:has_loaded_history, has_loaded_history)

    ~H"""
    <div id={@dom_id} class={["timeline-event-wrapper", @type_class, @expanded && "expanded"]}>
      <div class="timeline-event-marker-dot"></div>

      <div
        class={["timeline-event", @can_expand && "expandable"]}
        phx-click="toggle_event_expand"
        phx-value-id={@event.id}
      >
        <span class="timeline-event-icon">
          <.event_type_icon type={@event_type} />
        </span>

        <div class="timeline-event-content">
          <div class="timeline-event-header">
            <span class="timeline-event-time">{format_event_time(@event.timestamp)}</span>
            <span
              class="timeline-event-relative"
              data-timestamp={@event.timestamp && DateTime.to_iso8601(@event.timestamp)}
            >
              {timeline_relative_time(@event.timestamp)}
            </span>
          </div>

          <div class="timeline-event-body">
            <span class={["timeline-event-type-badge", @badge_class]}>
              {event_type_label(@event_type)}
            </span>
            <span class="timeline-event-title">{event_title(@event)}</span>
            <span :if={event_source(@event) != "System"} class="timeline-event-target">
              {event_source(@event)}
            </span>
          </div>

          <div :if={@event.description} class="timeline-event-description">
            {@event.description}
          </div>
        </div>

        <.event_status_badge :if={@event.status} status={@event.status} />

        <span :if={@can_expand} class="timeline-event-chevron">
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        </span>
      </div>

      <div :if={@expanded && @has_loaded_history} class="timeline-event-history">
        <div class="state-change-header">STATE HISTORY ({length(@history)} events)</div>
        <.state_change_item :for={state <- @history} state={state} />
      </div>
    </div>
    """
  end

  attr :type, :atom, required: true

  defp event_type_icon(%{type: :command} = assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
      />
    </svg>
    """
  end

  defp event_type_icon(%{type: :alarm} = assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
      />
    </svg>
    """
  end

  defp event_type_icon(%{type: :procedure} = assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"
      />
    </svg>
    """
  end

  defp event_type_icon(%{type: :automation} = assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M13 10V3L4 14h7v7l9-11h-7z"
      />
    </svg>
    """
  end

  defp event_type_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="10" stroke-width="2" />
    </svg>
    """
  end

  attr :status, :atom, required: true

  defp event_status_badge(assigns) do
    status_class =
      case assigns.status do
        s when s in [:success, :completed] -> "status-success"
        s when s in [:pending, :queued] -> "status-pending"
        s when s in [:running, :executing] -> "status-running"
        s when s in [:active] -> "status-active"
        s when s in [:error, :failed] -> "status-error"
        _ -> "status-default"
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <span class={["timeline-event-status", @status_class]}>
      {status_label(@status)}
    </span>
    """
  end

  defp status_label(:success), do: "SUCCESS"
  defp status_label(:completed), do: "DONE"
  defp status_label(:pending), do: "PENDING"
  defp status_label(:queued), do: "QUEUED"
  defp status_label(:running), do: "RUNNING"
  defp status_label(:executing), do: "EXEC"
  defp status_label(:active), do: "ACTIVE"
  defp status_label(:error), do: "ERROR"
  defp status_label(:failed), do: "FAILED"
  defp status_label(other), do: other |> to_string() |> String.upcase()

  # State change item for expandable event history
  attr :state, :map, required: true

  defp state_change_item(assigns) do
    ~H"""
    <div class="state-change-item">
      <span class="state-change-time">{format_event_time(@state.timestamp)}</span>
      <span class="state-change-type">{@state.description || @state.title}</span>
      <.event_status_badge :if={@state.status} status={@state.status} />
    </div>
    """
  end

  # Event detail panel
  attr :event, :map, required: true

  defp event_detail(assigns) do
    event_type = assigns.event.type || :command
    assigns = assign(assigns, :event_type, event_type)

    ~H"""
    <div class="stream-detail-content">
      <div class="stream-detail-header">
        <span class={"timeline-event-type-badge timeline-badge-#{@event_type}"}>
          {event_type_label(@event_type)}
        </span>
        <button type="button" class="stream-detail-close" phx-click="close_detail">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>

      <h3 class="stream-detail-title">{event_title(@event)}</h3>

      <dl class="stream-detail-fields">
        <div class="stream-detail-field">
          <dt>Source</dt>
          <dd>{event_source(@event)}</dd>
        </div>
        <div class="stream-detail-field">
          <dt>Time</dt>
          <dd>{format_event_time(@event.timestamp)}</dd>
        </div>
        <div :if={@event.status} class="stream-detail-field">
          <dt>Status</dt>
          <dd><.event_status_badge status={@event.status} /></dd>
        </div>
        <div :if={@event.description} class="stream-detail-field">
          <dt>Message</dt>
          <dd class="stream-detail-message">{@event.description}</dd>
        </div>
      </dl>
    </div>
    """
  end

  # ============================================================================
  # Matrix View
  # ============================================================================

  attr :targets, :list, required: true
  attr :selected_targets, :any, required: true
  attr :target_search, :string, required: true
  attr :streams, :map, required: true
  attr :time_range, :string, required: true

  defp timeline_matrix_view(assigns) do
    ~H"""
    <div class="timeline-matrix">
      <div class="timeline-empty-placeholder">
        <svg class="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1"
            d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"
          />
        </svg>
        <span class="placeholder-title">Matrix View</span>
        <span class="placeholder-description">
          A grid showing events across targets and time buckets.
        </span>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Lanes View
  # ============================================================================

  attr :targets, :list, required: true
  attr :selected_targets, :any, required: true
  attr :target_search, :string, required: true
  attr :events, :list, required: true
  attr :time_range, :string, required: true
  attr :current_time, :any, required: true
  attr :lanes_offset_minutes, :integer, default: 0
  attr :show_system_events, :boolean, default: true

  defp timeline_lanes_view(assigns) do
    # Calculate time window (accounts for pan offset)
    %{
      start_time: start_time,
      end_time: end_time,
      total_ms: total_ms,
      scrubber_position: scrubber_position
    } = lane_window(assigns)

    range_hours = parse_time_range(assigns.time_range)

    # Generate time markers
    marker_interval_mins =
      if range_hours <= 2, do: 30, else: if(range_hours <= 6, do: 60, else: 120)

    time_markers = generate_time_markers(start_time, end_time, total_ms, marker_interval_mins)

    selected_target_list =
      assigns.targets
      |> Enum.filter(fn t -> MapSet.member?(assigns.selected_targets, t.id) end)

    target_lanes =
      Enum.map(selected_target_list, fn target ->
        %{
          target: target,
          events: get_target_events(assigns.events, target.id, start_time, end_time)
        }
      end)

    # Get system events (events with nil target_id)
    system_events = get_system_events(assigns.events, start_time, end_time)
    system_event_count = length(system_events)

    fleet_events = get_all_events(assigns.events, start_time, end_time)

    assigns =
      assigns
      |> assign(:target_lanes, target_lanes)
      |> assign(:selected_target_count, length(selected_target_list))
      |> assign(:fleet_events, fleet_events)
      |> assign(:start_time, start_time)
      |> assign(:end_time, end_time)
      |> assign(:total_ms, total_ms)
      |> assign(:time_markers, time_markers)
      |> assign(:scrubber_position, scrubber_position)
      |> assign(:system_events, system_events)
      |> assign(:system_event_count, system_event_count)

    ~H"""
    <div class="lanes-view-layout">
      <div class="lanes-split-layout">
        <.timeline_lanes_target_picker
          targets={@targets}
          selected_targets={@selected_targets}
          target_search={@target_search}
          show_system_events={@show_system_events}
          system_event_count={@system_event_count}
        />

        <.lanes_resize_handle />

        <.timeline_lanes_panel
          lanes={@target_lanes}
          time_markers={@time_markers}
          scrubber_position={@scrubber_position}
          time_range={@time_range}
          start_time={@start_time}
          total_ms={@total_ms}
          fleet_events={@fleet_events}
          selected_target_count={@selected_target_count}
          show_system_events={@show_system_events}
          system_events={@system_events}
        />
      </div>

      <div class="lanes-activity-stack">
        <.timeline_lanes_activity_panel />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Event handlers
  # ============================================================================

  @impl true
  def handle_event("toggle_target_filter", %{"id" => id}, socket) do
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

  def handle_event("clear_target_filter", _, socket) do
    {:noreply, assign(socket, :selected_targets, MapSet.new())}
  end

  def handle_event("filter_targets", %{"value" => value}, socket) do
    {:noreply, assign(socket, :target_search, value)}
  end

  def handle_event("toggle_system_events", _, socket) do
    {:noreply, assign(socket, :show_system_events, !socket.assigns.show_system_events)}
  end

  def handle_event("toggle_event_filter", %{"type" => type}, socket) do
    type_atom = String.to_existing_atom(type)

    event_type_filters =
      Map.update!(socket.assigns.event_type_filters, type_atom, &(!&1))

    {:noreply, assign(socket, :event_type_filters, event_type_filters)}
  end

  def handle_event("toggle_event_expand", %{"id" => id}, socket) do
    expanded_events = socket.assigns.expanded_events
    event = Enum.find(socket.assigns.events_list, &(&1.id == id))

    if MapSet.member?(expanded_events, id) do
      # Collapse - update stream to trigger re-render
      socket =
        socket
        |> assign(:expanded_events, MapSet.delete(expanded_events, id))

      if event do
        {:noreply, stream_insert(socket, :events, event)}
      else
        {:noreply, socket}
      end
    else
      # Expand - load history if not cached, then update stream to trigger re-render
      socket =
        socket
        |> maybe_load_event_history(id)
        |> assign(:expanded_events, MapSet.put(socket.assigns.expanded_events, id))

      if event do
        {:noreply, stream_insert(socket, :events, event)}
      else
        {:noreply, socket}
      end
    end
  end

  defp maybe_load_event_history(socket, event_id) do
    if Map.has_key?(socket.assigns.event_histories, event_id) do
      socket
    else
      event = Enum.find(socket.assigns.events_list, &(&1.id == event_id))

      if event do
        history = Timeline.get_event_state_history(event)
        assign(socket, :event_histories, Map.put(socket.assigns.event_histories, event_id, history))
      else
        socket
      end
    end
  end

  def handle_event("toggle_follow", _, socket) do
    {:noreply, assign(socket, :follow_mode, !socket.assigns.follow_mode)}
  end

  def handle_event("set_time_range", %{"value" => value}, socket) do
    {:noreply,
     socket
     |> assign(:time_range, value)
     |> load_lanes_events()}
  end

  def handle_event("jump_to_now", _, socket) do
    mission_id = socket.assigns.mission.id
    events = Timeline.list_recent_events(mission_id, 120, limit: @events_page_size)

    socket =
      socket
      |> assign(:events_list, events)
      |> assign(:lanes_events, events)
      |> assign(:lanes_offset_minutes, 0)
      |> assign(:has_more_events, length(events) >= @events_page_size)
      |> assign(:follow_mode, true)
      |> stream(:events, events, reset: true)
      |> push_scrubber_reset()

    {:noreply, socket}
  end

  def handle_event("lanes_scrub_state", %{"dragging" => dragging}, socket) do
    scrubbing? =
      case dragging do
        true -> true
        "true" -> true
        _ -> false
      end

    {:noreply, assign(socket, :lanes_scrubbing?, scrubbing?)}
  end

  def handle_event("pan_lanes", %{"direction" => direction} = params, socket) do
    range_hours = parse_time_range(socket.assigns.time_range)
    base_step = pan_step_minutes(range_hours)

    intensity = normalize_pan_intensity(Map.get(params, "intensity"))

    step_minutes =
      base_step
      |> Kernel.*(intensity)
      |> round()
      |> max(1)

    new_offset =
      case direction do
        "forward" ->
          min(socket.assigns.lanes_offset_minutes + step_minutes, 0)

        "back" ->
          socket.assigns.lanes_offset_minutes - step_minutes

        _ ->
          socket.assigns.lanes_offset_minutes
      end

    {:noreply,
     socket
     |> assign(:lanes_offset_minutes, new_offset)
     |> load_lanes_events()}
  end

  def handle_event("load_more", _, %{assigns: %{events_list: []}} = socket) do
    {:noreply, assign(socket, :has_more_events, false)}
  end

  def handle_event("load_more", _, socket) do
    total_events = length(socket.assigns.events_list)

    if total_events >= @max_cached_events do
      {:noreply,
       socket
       |> assign(:has_more_events, false)
       |> put_flash(:info, "Showing the last #{@max_cached_events} events")}
    else
      cursor = last_event_timestamp(socket.assigns.events_list)

      older_events =
        Timeline.list_events_before(socket.assigns.mission.id, cursor, limit: @events_page_size)

      new_total = total_events + length(older_events)
      has_more = length(older_events) >= @events_page_size && new_total < @max_cached_events

      {:noreply,
       socket
       |> append_older_events(older_events)
       |> assign(:has_more_events, has_more)}
    end
  end

  # Alarm action handlers (from context panel)
  def handle_event("acknowledge_alarm", %{"id" => id}, socket) do
    alarm = Alarms.get_alarm!(id)
    user = socket.assigns.current_scope.user

    case Alarms.acknowledge_alarm(alarm, user.id) do
      {:ok, _updated_alarm} ->
        active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)

        {:noreply,
         socket
         |> assign(:alarms, active_alarms)
         |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to acknowledge alarm")}
    end
  end

  def handle_event("clear_alarm", %{"id" => id}, socket) do
    alarm = Alarms.get_alarm!(id)
    user = socket.assigns.current_scope.user

    case Alarms.clear_alarm(alarm, user.id) do
      {:ok, _cleared_alarm} ->
        active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)

        {:noreply,
         socket
         |> assign(:alarms, active_alarms)
         |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to clear alarm")}
    end
  end

  # PubSub handlers
  @impl true
  def handle_info({:timeline_event, event}, socket) do
    {:noreply, insert_live_event(socket, event)}
  end

  def handle_info({:queue_updated, _entry}, socket) do
    {:noreply, refresh_queue_entries(socket)}
  end

  def handle_info(:tick, %{assigns: %{live_action: :lanes, lanes_scrubbing?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :current_time, DateTime.utc_now())}
  end

  def handle_info({:alarm_triggered, _alarm}, socket) do
    active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)

    socket =
      socket
      |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))
      |> assign(:alarms, active_alarms)

    {:noreply, socket}
  end

  def handle_info({:alarm_cleared, _alarm}, socket) do
    active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)

    socket =
      socket
      |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))
      |> assign(:alarms, active_alarms)

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp append_older_events(socket, []), do: socket

  defp append_older_events(socket, events) do
    existing_ids = MapSet.new(Enum.map(socket.assigns.events_list, & &1.id))
    deduped = Enum.reject(events, &MapSet.member?(existing_ids, &1.id))

    new_list = socket.assigns.events_list ++ deduped

    socket
    |> assign(:events_list, new_list)
    |> stream(:events, deduped, at: -1)
  end

  defp insert_live_event(socket, event) do
    merged =
      [event | socket.assigns.events_list]
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

    {trimmed, dropped} = trim_events(merged, socket.assigns)

    socket =
      socket
      |> assign(:events_list, trimmed)
      |> maybe_add_event_to_lanes(event)
      |> stream_insert(:events, event, at: 0)

    Enum.reduce(dropped, socket, fn ev, acc ->
      stream_delete(acc, :events, ev)
    end)
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

  defp trim_events(events, _assigns) do
    if length(events) > @max_cached_events do
      {Enum.take(events, @max_cached_events), Enum.drop(events, @max_cached_events)}
    else
      {events, []}
    end
  end

  defp last_event_timestamp([]), do: DateTime.utc_now()

  defp last_event_timestamp(events) do
    case List.last(events) do
      %{timestamp: %DateTime{} = ts} -> ts
      _ -> DateTime.utc_now()
    end
  end

  defp load_lanes_events(socket) do
    %{start_time: start_time, end_time: end_time} = lane_window(socket.assigns)

    mission_id = socket.assigns.mission.id

    events =
      Timeline.list_events_for_mission(mission_id, start_time, end_time,
        limit: @lanes_fetch_limit
      )

    assign(socket, :lanes_events, events)
  end

  defp maybe_add_event_to_lanes(socket, %{timestamp: %DateTime{} = timestamp} = event) do
    %{start_time: start_time, end_time: end_time} = lane_window(socket.assigns)

    if DateTime.compare(timestamp, start_time) != :lt &&
         DateTime.compare(timestamp, end_time) != :gt do
      lane_events =
        [event | socket.assigns.lanes_events || []]
        |> Enum.uniq_by(& &1.id)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

      assign(socket, :lanes_events, lane_events)
    else
      socket
    end
  end

  defp maybe_add_event_to_lanes(socket, _event), do: socket

  defp push_scrubber_reset(socket) do
    %{scrubber_position: position} = lane_window(socket.assigns)
    push_event(socket, "scrubber_reset", %{position: position})
  end

  defp lane_window(assigns) do
    current_time = assigns.current_time || DateTime.utc_now()
    range_hours = parse_time_range(assigns.time_range)
    offset_minutes = Map.get(assigns, :lanes_offset_minutes, 0)

    anchor_time = DateTime.add(current_time, offset_minutes, :minute)
    range_ms = range_hours * 60 * 60 * 1000
    past_ms = round(range_ms * 1.6)
    future_ms = round(range_ms * 0.4)

    start_time = DateTime.add(anchor_time, -past_ms, :millisecond)
    end_time = DateTime.add(anchor_time, future_ms, :millisecond)
    total_ms = DateTime.diff(end_time, start_time, :millisecond)

    scrubber_position =
      if total_ms <= 0 do
        80.0
      else
        diff_ms = DateTime.diff(current_time, start_time, :millisecond)
        clamp_percentage(diff_ms / total_ms * 100)
      end

    %{
      start_time: start_time,
      end_time: end_time,
      total_ms: total_ms,
      scrubber_position: scrubber_position
    }
  end

  defp clamp_percentage(value) when is_number(value) do
    value
    |> max(0.0)
    |> min(100.0)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp stream_empty?(%{events: events}) when events == [], do: true
  defp stream_empty?(_), do: false

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

  # Lanes view helpers

  defp parse_time_range("1h"), do: 1
  defp parse_time_range("4h"), do: 4
  defp parse_time_range("12h"), do: 12
  defp parse_time_range("24h"), do: 24
  defp parse_time_range(_), do: 4

  # Base step is ~2.5% of the visible range for smooth but noticeable panning
  # For 1h range (120min total window): ~3 minutes per step
  # For 4h range (480min total window): ~12 minutes per step
  defp pan_step_minutes(range_hours) when is_number(range_hours) do
    total_window_minutes = range_hours * 60 * 2
    step = total_window_minutes * 0.025
    trunc(max(step, 1))
  end

  defp normalize_pan_intensity(nil), do: 1.0

  defp normalize_pan_intensity(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> clamp_pan_intensity(num)
      _ -> 1.0
    end
  end

  defp normalize_pan_intensity(value) when is_number(value) do
    clamp_pan_intensity(value)
  end

  defp normalize_pan_intensity(_), do: 1.0

  defp clamp_pan_intensity(value) do
    value
    |> max(0.15)
    |> min(12.0)
  end

  defp generate_time_markers(start_time, end_time, total_ms, interval_mins) do
    interval_ms = interval_mins * 60 * 1000

    # Round start_time up to nearest interval
    start_unix = DateTime.to_unix(start_time, :millisecond)
    first_marker_unix = ceil(start_unix / interval_ms) * interval_ms

    Stream.iterate(first_marker_unix, &(&1 + interval_ms))
    |> Stream.take_while(&(&1 <= DateTime.to_unix(end_time, :millisecond)))
    |> Enum.map(fn marker_unix ->
      marker_time = DateTime.from_unix!(marker_unix, :millisecond)
      position = (marker_unix - start_unix) / total_ms * 100

      %{
        time: marker_time,
        position: position,
        label: Calendar.strftime(marker_time, "%H:%M")
      }
    end)
  end

  defp get_target_events(events, target_id, start_time, end_time) do
    events
    |> Enum.filter(fn event ->
      event.target_id == target_id and
        DateTime.compare(event.timestamp, start_time) != :lt and
        DateTime.compare(event.timestamp, end_time) != :gt
    end)
  end

  defp get_all_events(events, start_time, end_time) do
    events
    |> Enum.filter(fn event ->
      DateTime.compare(event.timestamp, start_time) != :lt and
        DateTime.compare(event.timestamp, end_time) != :gt
    end)
  end

  defp get_system_events(events, start_time, end_time) do
    events
    |> Enum.filter(fn event ->
      is_nil(event.target_id) and
        DateTime.compare(event.timestamp, start_time) != :lt and
        DateTime.compare(event.timestamp, end_time) != :gt
    end)
  end
end
