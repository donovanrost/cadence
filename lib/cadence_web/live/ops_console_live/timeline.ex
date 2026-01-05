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

  alias Cadence.{Alarms, Commands, Outbox, Targets, Timeline}
  alias Cadence.Procedures.Events.ProcedureExecutionEvent
  alias Cadence.Timeline.Event, as: TimelineEvent
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
    targets_by_id = Map.new(targets, &{&1.id, &1})

    # Load recent timeline events
    events = Timeline.list_recent_events(mission_id, 120, limit: @events_page_size)

    # Load data for layout (status bar and context panel)
    active_alarms = Alarms.list_active_alarms(mission_id)
    alarm_counts = calculate_alarm_counts(active_alarms)

    queue_entries = build_context_queue_entries(mission_id, targets)
    queue_entry_status_by_id = Map.new(queue_entries, &{&1.id, &1.status})

    fleet_health = calculate_fleet_health(targets)

    # Subscribe to timeline, alarm, and queue updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:timeline")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:procedures")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:automations")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:queue")
      Outbox.subscribe_mission(mission_id)
      :timer.send_interval(1000, self(), :tick)
    end

    # Default all event type filters to active
    event_type_filters =
      Enum.reduce(@event_types, %{}, fn type, acc -> Map.put(acc, type, true) end)

    events_with_context = add_time_context(events)

    socket =
      socket
      |> assign(:page_title, "Timeline - #{mission.name}")
      |> assign(:targets, targets)
      |> assign(:targets_by_id, targets_by_id)
      |> stream(:events, events_with_context)
      |> assign(:events_list, events)
      |> assign(:selected_targets, MapSet.new(targets, & &1.id))
      |> assign(:event_type_filters, event_type_filters)
      |> assign(:target_search, "")
      |> assign(:expanded_events, MapSet.new())
      |> assign(:event_histories, %{})
      |> assign(:has_more_events, length(events) > 0)
      |> assign(:follow_mode, true)
      |> assign(:time_range, "1h")
      # Layout data
      |> assign(:alarm_counts, alarm_counts)
      |> assign(:alarms, active_alarms)
      |> assign(:queue_entries, queue_entries)
      |> assign(:queue_entry_status_by_id, queue_entry_status_by_id)
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
          this.isLoading = false
          this.lastScrollHeight = this.el.scrollHeight
          this.loadCooldown = false
          this.updateRelativeTimes()
          this._interval = setInterval(() => this.updateRelativeTimes(), 1000)
          this._onScroll = () => this.handleScroll()
          this.el.addEventListener('scroll', this._onScroll)
          // Check on mount if we need to load more (content doesn't fill container)
          setTimeout(() => this.checkLoadMore(), 100)
        },

        updated() {
          this.updateRelativeTimes()
          this.isLoading = false
          // Track if content grew - if not, add cooldown to prevent rapid re-triggers
          const newScrollHeight = this.el.scrollHeight
          if (newScrollHeight <= this.lastScrollHeight) {
            this.loadCooldown = true
            setTimeout(() => { this.loadCooldown = false }, 1000)
          }
          this.lastScrollHeight = newScrollHeight
          // Check if we still need more content after update
          setTimeout(() => this.checkLoadMore(), 100)
        },

        destroyed() {
          if (this._interval) {
            clearInterval(this._interval)
            this._interval = null
          }
          if (this._onScroll) {
            this.el.removeEventListener('scroll', this._onScroll)
          }
        },

        handleScroll() {
          this.checkLoadMore()
        },

        checkLoadMore() {
          if (this.isLoading || this.loadCooldown) return
          const hasMore = this.el.dataset.hasMore === 'true'
          if (!hasMore) return

          const scrollHeight = this.el.scrollHeight
          const scrollTop = this.el.scrollTop
          const clientHeight = this.el.clientHeight
          const scrollBottom = scrollHeight - scrollTop - clientHeight

          // Load more when within 200px of the bottom OR content doesn't fill container
          if (scrollBottom < 200) {
            this.isLoading = true
            this.pushEvent('load_more', {})
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
                <%= for {dom_id, event} <- @streams.events do %>
                  <.timeline_event
                    :if={event_visible?(event, @event_type_filters, @selected_targets)}
                    dom_id={dom_id}
                    event={event}
                    expanded={MapSet.member?(@expanded_events, event.id)}
                    history={get_event_history(@event_histories, event)}
                  />
                <% end %>
              </div>
            </div>

            <div :if={@has_more} class="stream-loading-more">
              <span class="stream-loading-spinner"></span>
              <span>LOADING</span>
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
    # Events are expandable if:
    # 1. They're from recordings (can load history from DB)
    # 2. They have live state history from aggregation
    has_loaded_history = length(assigns.history) > 0
    can_expand = assigns.event.source_table == :recordings || has_loaded_history
    gap_minutes = Map.get(assigns.event, :gap_minutes)
    show_gap = show_gap_indicator?(gap_minutes)
    gap_text = if show_gap, do: format_gap(gap_minutes)

    assigns =
      assigns
      |> assign(:event_type, event_type)
      |> assign(:type_class, "timeline-event-#{event_type}")
      |> assign(:badge_class, "timeline-badge-#{event_type}")
      |> assign(:can_expand, can_expand)
      |> assign(:has_loaded_history, has_loaded_history)
      |> assign(:show_bucket_header, Map.get(assigns.event, :show_bucket_header, false))
      |> assign(:time_bucket, Map.get(assigns.event, :time_bucket))
      |> assign(:show_gap, show_gap)
      |> assign(:gap_text, gap_text)

    ~H"""
    <div id={@dom_id} class="timeline-event-container">
      <!-- Time Bucket Header - outside wrapper for proper sticky behavior -->
      <div :if={@show_bucket_header} class="timeline-bucket-header">
        <div class="timeline-bucket-line"></div>
        <span class="timeline-bucket-label">{@time_bucket}</span>
        <div class="timeline-bucket-line"></div>
      </div>
      <!-- Gap Indicator -->
      <div :if={@show_gap && !@show_bucket_header} class="timeline-gap-indicator">
        <div class="timeline-gap-line"></div>
        <span class="timeline-gap-label">{@gap_text}</span>
        <div class="timeline-gap-line"></div>
      </div>

      <div class={["timeline-event-wrapper", @type_class, @expanded && "expanded"]}>
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

          <.event_status_badge
            :if={@event.status}
            status={@event.status}
            label={command_status_label(@event)}
          />

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
  attr :label, :string, default: nil

  defp event_status_badge(assigns) do
    status_class =
      case assigns.status do
        s when s in [:success, :completed] -> "status-success"
        s when s in [:pending, :queued] -> "status-pending"
        s when s in [:running, :executing] -> "status-running"
        s when s in [:active] -> "status-active"
        s when s in [:error, :failed, :cancelled, :expired] -> "status-error"
        _ -> "status-default"
      end

    display_label = assigns.label || status_label(assigns.status)

    assigns =
      assigns |> assign(:status_class, status_class) |> assign(:display_label, display_label)

    ~H"""
    <span class={["timeline-event-status", @status_class]}>
      {@display_label}
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

  # Custom label for command events based on recordable_type
  defp command_status_label(%{metadata: %{recordable_type: "CommandQueued"}}), do: "QUEUED"

  defp command_status_label(%{metadata: %{recordable_type: "CommandDispatched"}}),
    do: "DISPATCHED"

  defp command_status_label(%{metadata: %{recordable_type: "CommandSent"}}),
    do: "AWAITING VERIFICATION"

  defp command_status_label(_), do: nil

  # State change item for expandable event history
  attr :state, :map, required: true

  defp state_change_item(assigns) do
    ~H"""
    <div class="state-change-item">
      <span class="state-change-time">{format_event_time(@state.timestamp)}</span>
      <span class="state-change-type">{@state.description || @state.title}</span>
      <.event_status_badge
        :if={terminal_state?(@state)}
        status={@state.status}
        label={command_status_label(@state)}
      />
    </div>
    """
  end

  defp terminal_state?(%{metadata: %{recordable_type: type}})
       when type in ~w(CommandVerified CommandErrored CommandRejected CommandVerificationFailed),
       do: true

  defp terminal_state?(%{status: status})
       when status in [:success, :completed, :error, :failed],
       do: true

  defp terminal_state?(_), do: false

  # Check if an event should be visible based on active filters
  defp event_visible?(event, event_type_filters, selected_targets) do
    type_visible?(event, event_type_filters) && target_visible?(event, selected_targets)
  end

  defp type_visible?(event, event_type_filters) do
    event_type = event.type || :command
    Map.get(event_type_filters, event_type, true)
  end

  defp target_visible?(event, selected_targets) do
    event.target_id == nil || MapSet.member?(selected_targets, event.target_id)
  end

  # Event detail panel (legacy, kept for reference)
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

    {:noreply,
     socket
     |> assign(:selected_targets, selected)
     |> reset_events_stream()}
  end

  def handle_event("select_all_targets", _, socket) do
    all_ids = socket.assigns.targets |> Enum.map(& &1.id) |> MapSet.new()

    {:noreply,
     socket
     |> assign(:selected_targets, all_ids)
     |> reset_events_stream()}
  end

  def handle_event("clear_target_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_targets, MapSet.new())
     |> reset_events_stream()}
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

    {:noreply,
     socket
     |> assign(:event_type_filters, event_type_filters)
     |> reset_events_stream()}
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
      |> assign(:has_more_events, length(events) > 0)
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

  # Reset the events stream to apply current filters
  defp reset_events_stream(socket) do
    events_with_context = add_time_context(socket.assigns.events_list)
    stream(socket, :events, events_with_context, reset: true)
  end

  defp maybe_load_event_history(socket, event_id) do
    if Map.has_key?(socket.assigns.event_histories, event_id) do
      socket
    else
      event = Enum.find(socket.assigns.events_list, &(&1.id == event_id))

      if event do
        history = Timeline.get_event_state_history(event)

        assign(
          socket,
          :event_histories,
          Map.put(socket.assigns.event_histories, event_id, history)
        )
      else
        socket
      end
    end
  end

  # PubSub handlers
  @impl true
  def handle_info({:timeline_event, event}, socket) do
    {:noreply, insert_live_event(socket, maybe_attach_target_name(socket, event))}
  end

  def handle_info({:queue_updated, entry}, socket) do
    {socket, timeline_event} = maybe_queue_update_to_timeline_event(socket, entry)

    socket =
      socket
      |> maybe_insert_timeline_event(timeline_event)
      |> refresh_queue_entries()

    {:noreply, socket}
  end

  def handle_info({:outbox_event, %{event_type: event_type} = event}, socket)
      when event_type in ["command_enqueued", "command_status_changed", "command_cancelled"] do
    timeline_event = outbox_command_event_to_timeline_event(event)

    {:noreply,
     socket
     |> refresh_queue_entries()
     |> maybe_insert_timeline_event(timeline_event)}
  end

  def handle_info({:outbox_event, _event}, socket) do
    {:noreply, socket}
  end

  def handle_info({:procedure_event, %ProcedureExecutionEvent{} = event}, socket) do
    timeline_event = procedure_event_to_timeline_event(event)
    {:noreply, maybe_insert_timeline_event(socket, timeline_event)}
  end

  def handle_info(:tick, %{assigns: %{live_action: :lanes, lanes_scrubbing?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :current_time, DateTime.utc_now())}
  end

  def handle_info({:alarm_triggered, alarm}, socket) do
    active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)
    timeline_event = alarm_to_timeline_event(alarm, :triggered)

    socket =
      socket
      |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))
      |> assign(:alarms, active_alarms)
      |> maybe_insert_timeline_event(timeline_event)

    {:noreply, socket}
  end

  def handle_info({:alarm_cleared, alarm}, socket) do
    active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)
    timeline_event = alarm_to_timeline_event(alarm, :cleared)

    socket =
      socket
      |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))
      |> assign(:alarms, active_alarms)
      |> maybe_insert_timeline_event(timeline_event)

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp append_older_events(socket, []), do: socket

  defp append_older_events(socket, events) do
    existing_ids = MapSet.new(Enum.map(socket.assigns.events_list, & &1.id))
    new_events = Enum.reject(events, &MapSet.member?(existing_ids, &1.id))

    new_list = socket.assigns.events_list ++ new_events

    socket
    |> assign(:events_list, new_list)
    |> reset_events_stream()
  end

  defp insert_live_event(socket, event) do
    event_aggregate_id = get_event_aggregate_id(event)

    # Find existing event with same aggregate_id to replace in the stream
    existing_event =
      if event_aggregate_id do
        Enum.find(socket.assigns.events_list, fn existing ->
          get_event_aggregate_id(existing) == event_aggregate_id
        end)
      end

    # Track state history when replacing an event
    socket =
      if existing_event && event_aggregate_id do
        append_to_aggregate_history(socket, event_aggregate_id, existing_event)
      else
        socket
      end

    # Merge the new event into the events list, replacing any with the same aggregate_id
    merged =
      if event_aggregate_id do
        # Remove old event with same aggregate_id, add new one
        socket.assigns.events_list
        |> Enum.reject(fn existing ->
          get_event_aggregate_id(existing) == event_aggregate_id
        end)
        |> then(fn list -> [event | list] end)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
      else
        # No aggregate_id, just merge by event id
        [event | socket.assigns.events_list]
        |> Enum.uniq_by(& &1.id)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
      end

    {trimmed, dropped} = trim_events(merged, socket.assigns)

    # Add time context to the new event for proper rendering
    event_with_context = add_time_context_to_event(event, trimmed)

    socket =
      socket
      |> assign(:events_list, trimmed)
      |> maybe_add_event_to_lanes(event)
      |> then(fn s ->
        # If replacing an existing event, delete the old one from stream first
        if existing_event do
          stream_delete(s, :events, existing_event)
        else
          s
        end
      end)
      |> stream_insert(:events, event_with_context, at: 0)

    Enum.reduce(dropped, socket, fn ev, acc ->
      stream_delete(acc, :events, ev)
    end)
  end

  # Append old event state to history for the aggregate
  defp append_to_aggregate_history(socket, aggregate_id, old_event) do
    histories = socket.assigns.event_histories

    # Get existing history for this aggregate, or start empty
    existing_history = Map.get(histories, aggregate_id, [])

    # Create a history entry from the old event
    history_entry = %{
      timestamp: old_event.timestamp,
      title: old_event.title,
      description: old_event.description,
      status: old_event.status,
      metadata: old_event.metadata
    }

    # Append to history (keeping chronological order - oldest first)
    updated_history = existing_history ++ [history_entry]

    assign(socket, :event_histories, Map.put(histories, aggregate_id, updated_history))
  end

  defp get_event_aggregate_id(event) do
    get_in(event, [Access.key(:metadata, %{}), :aggregate_id])
  end

  # Get history for an event - check by aggregate_id first, then event id
  defp get_event_history(histories, event) do
    aggregate_id = get_event_aggregate_id(event)

    cond do
      # Check aggregate_id first (for live state aggregation)
      aggregate_id && Map.has_key?(histories, aggregate_id) ->
        Map.get(histories, aggregate_id, [])

      # Fall back to event id (for DB-loaded history)
      Map.has_key?(histories, event.id) ->
        Map.get(histories, event.id, [])

      true ->
        []
    end
  end

  defp add_time_context_to_event(event, events_list) do
    now = DateTime.utc_now()
    bucket = time_bucket(event.timestamp, now)

    # Find the event that would come before this one (next older event)
    prev_event =
      events_list
      |> Enum.find(fn e ->
        e.id != event.id &&
          e.timestamp &&
          DateTime.compare(e.timestamp, event.timestamp) == :lt
      end)

    prev_bucket = if prev_event, do: time_bucket(prev_event.timestamp, now)

    gap_minutes =
      if prev_event && prev_event.timestamp && event.timestamp do
        abs(DateTime.diff(prev_event.timestamp, event.timestamp, :second)) / 60
      end

    event
    |> Map.put(:time_bucket, bucket)
    |> Map.put(:show_bucket_header, bucket != prev_bucket)
    |> Map.put(:gap_minutes, gap_minutes)
  end

  defp maybe_attach_target_name(
         %{assigns: %{targets_by_id: _targets_by_id}},
         %{target_name: name} = event
       )
       when is_binary(name) and name != "" do
    event
  end

  defp maybe_attach_target_name(
         %{assigns: %{targets_by_id: targets_by_id}},
         %{target_id: id} = event
       )
       when is_binary(id) and id != "" do
    case Map.get(targets_by_id, id) do
      nil -> event
      target -> %{event | target_name: target.name}
    end
  end

  defp maybe_attach_target_name(_socket, event), do: event

  defp maybe_insert_timeline_event(socket, nil), do: socket

  defp maybe_insert_timeline_event(socket, event) do
    insert_live_event(socket, maybe_attach_target_name(socket, event))
  end

  defp maybe_queue_update_to_timeline_event(socket, entry) do
    entry_id = Map.get(entry, :id) || Map.get(entry, "id")

    status =
      entry
      |> Map.get(:status, Map.get(entry, "status"))
      |> normalize_queue_status()

    if is_binary(entry_id) and not is_nil(status) do
      status_by_id = Map.get(socket.assigns, :queue_entry_status_by_id, %{})
      previous_status = Map.get(status_by_id, entry_id)
      socket = assign(socket, :queue_entry_status_by_id, Map.put(status_by_id, entry_id, status))

      if is_nil(previous_status) or previous_status != status do
        {socket, queue_entry_to_timeline_event(entry, entry_id, status)}
      else
        {socket, nil}
      end
    else
      {socket, nil}
    end
  end

  defp normalize_queue_status(status) when is_atom(status), do: status
  defp normalize_queue_status("pending"), do: :pending
  defp normalize_queue_status("executing"), do: :executing
  defp normalize_queue_status("completed"), do: :completed
  defp normalize_queue_status("failed"), do: :failed
  defp normalize_queue_status("cancelled"), do: :cancelled
  defp normalize_queue_status("expired"), do: :expired
  defp normalize_queue_status(_), do: nil

  defp entry_field(entry, key, default \\ nil) when is_atom(key) do
    Map.get(entry, key) || Map.get(entry, Atom.to_string(key)) || default
  end

  defp queue_entry_to_timeline_event(entry, entry_id, status) do
    command_name = entry_field(entry, :command_name, "Command")
    target_id = entry_field(entry, :target_id)
    priority = entry_field(entry, :priority)
    scheduled_at = entry_field(entry, :scheduled_at)
    attempts = entry_field(entry, :attempts, 0)
    user_id = entry_field(entry, :user_id)
    created_at = entry_field(entry, :created_at)
    last_attempt_at = entry_field(entry, :last_attempt_at)
    # Use command_aggregate_id for aggregation (matches recording events)
    command_aggregate_id = entry_field(entry, :command_aggregate_id)

    timestamp =
      case {status, created_at, last_attempt_at} do
        {:pending, %DateTime{} = created_at, _} -> created_at
        {:executing, _, %DateTime{} = last_attempt_at} -> last_attempt_at
        _ -> DateTime.utc_now()
      end

    {description, badge_status} = queue_status_description_and_badge(status, scheduled_at)

    # Use command_aggregate_id if available, otherwise fall back to entry_id
    aggregate_id = command_aggregate_id || entry_id

    %TimelineEvent{
      id: "queue-#{entry_id}-#{badge_status}-#{attempts}",
      type: :command,
      timestamp: timestamp,
      target_id: target_id,
      target_name: nil,
      target_group: nil,
      title: command_name,
      description: description,
      status: badge_status,
      status_label: badge_status |> to_string() |> String.upcase(),
      user_id: user_id,
      user_name: nil,
      is_future: false,
      metadata: %{
        aggregate_id: aggregate_id,
        priority: priority,
        scheduled_at: scheduled_at,
        attempts: attempts
      },
      source_id: entry_id,
      source_table: :command_queue_entries
    }
  end

  defp queue_status_description_and_badge(:pending, %DateTime{} = scheduled_at) do
    now = DateTime.utc_now()

    if DateTime.compare(scheduled_at, now) == :gt do
      {"Scheduled", :queued}
    else
      {"Queued", :queued}
    end
  end

  defp queue_status_description_and_badge(:pending, _), do: {"Queued", :queued}
  defp queue_status_description_and_badge(:executing, _), do: {"Executing", :executing}
  defp queue_status_description_and_badge(:completed, _), do: {"Completed", :completed}
  defp queue_status_description_and_badge(:failed, _), do: {"Failed", :failed}
  defp queue_status_description_and_badge(:cancelled, _), do: {"Cancelled", :cancelled}
  defp queue_status_description_and_badge(:expired, _), do: {"Expired", :expired}
  defp queue_status_description_and_badge(_status, _), do: {"Queued", :queued}

  defp outbox_command_event_to_timeline_event(event) do
    payload = Map.get(event, :payload, %{})
    command_name = Map.get(payload, "command_name", "Command")
    target_id = Map.get(payload, "target_id")
    status = Map.get(payload, "status")

    {description, badge_status} =
      outbox_command_description_and_badge(Map.get(event, :event_type), status)

    id =
      case Map.get(event, :recording_id) do
        recording_id when is_binary(recording_id) -> "rec-#{recording_id}"
        _ -> "outbox-#{event.id}"
      end

    aggregate_id = Map.get(event, :aggregate_id)

    %TimelineEvent{
      id: id,
      type: :command,
      timestamp: Map.get(event, :inserted_at) || DateTime.utc_now(),
      target_id: target_id,
      target_name: nil,
      target_group: nil,
      title: command_name,
      description: description,
      status: badge_status,
      status_label: badge_status |> to_string() |> String.upcase(),
      user_id: Map.get(event, :actor_id),
      user_name: nil,
      is_future: false,
      metadata: %{
        aggregate_id: aggregate_id,
        outbox_event_id: event.id,
        event_type: Map.get(event, :event_type),
        priority: Map.get(payload, "priority"),
        scheduled_at: Map.get(payload, "scheduled_at")
      },
      source_id: aggregate_id,
      source_table: :outbox_events
    }
  end

  defp outbox_command_description_and_badge("command_enqueued", _status), do: {"Queued", :queued}

  defp outbox_command_description_and_badge("command_status_changed", "completed"),
    do: {"Completed", :completed}

  defp outbox_command_description_and_badge("command_status_changed", "failed"),
    do: {"Failed", :failed}

  defp outbox_command_description_and_badge("command_status_changed", "executing"),
    do: {"Executing", :executing}

  defp outbox_command_description_and_badge("command_status_changed", "pending"),
    do: {"Queued", :queued}

  defp outbox_command_description_and_badge("command_cancelled", _status),
    do: {"Cancelled", :cancelled}

  defp outbox_command_description_and_badge(_event_type, _status), do: {"Queued", :queued}

  defp procedure_event_to_timeline_event(%ProcedureExecutionEvent{} = proc_event) do
    %TimelineEvent{
      id: "proc-evt-#{proc_event.execution_id}-#{proc_event.id}",
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
        aggregate_id: proc_event.execution_id,
        execution_id: proc_event.execution_id,
        procedure_id: proc_event.procedure_id,
        event_type: proc_event.event_type,
        step_index: proc_event.step_index,
        error_message: proc_event.error_message,
        triggered_by: proc_event.triggered_by,
        step_info: proc_event.step_info
      },
      source_id: proc_event.execution_id,
      source_table: :procedure_executions
    }
  end

  defp format_procedure_event_description(%{event_type: :started}), do: "Execution started"
  defp format_procedure_event_description(%{event_type: :completed}), do: "Completed successfully"

  defp format_procedure_event_description(%{event_type: :failed, error_message: msg})
       when is_binary(msg) and msg != "",
       do: "Failed: #{msg}"

  defp format_procedure_event_description(%{event_type: :failed}), do: "Execution failed"

  defp format_procedure_event_description(%{event_type: :paused, step_index: idx})
       when is_integer(idx),
       do: "Paused at step #{idx + 1}"

  defp format_procedure_event_description(%{event_type: :paused}), do: "Paused"
  defp format_procedure_event_description(%{event_type: :pausing}), do: "Pausing..."
  defp format_procedure_event_description(%{event_type: :resumed}), do: "Resumed"
  defp format_procedure_event_description(%{event_type: :cancelled}), do: "Cancelled"

  defp format_procedure_event_description(%{event_type: :step_started, step_index: idx})
       when is_integer(idx),
       do: "Step #{idx + 1} started"

  defp format_procedure_event_description(%{event_type: :step_completed, step_index: idx})
       when is_integer(idx),
       do: "Step #{idx + 1} completed"

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

  defp alarm_to_timeline_event(alarm, event_type) do
    {description, status} = alarm_description_and_status(event_type)

    %TimelineEvent{
      id: "alm-#{alarm.id}-#{System.unique_integer([:positive])}",
      type: :alarm,
      timestamp: DateTime.utc_now(),
      target_id: alarm.target_id,
      target_name: nil,
      target_group: nil,
      title: alarm.message || alarm.alarm_type || "Alarm",
      description: description,
      status: status,
      status_label: event_type |> to_string() |> String.upcase(),
      user_id: nil,
      user_name: nil,
      is_future: false,
      metadata: %{
        aggregate_id: alarm.id,
        severity: alarm.severity,
        source_type: alarm.source_type,
        source_id: alarm.source_id
      },
      source_id: alarm.id,
      source_table: :alarms
    }
  end

  defp alarm_description_and_status(:triggered), do: {"Alarm triggered", :active}
  defp alarm_description_and_status(:cleared), do: {"Cleared", :success}
  defp alarm_description_and_status(_), do: {nil, :active}

  defp refresh_queue_entries(socket) do
    mission_id = socket.assigns.mission.id
    targets = socket.assigns.targets

    queue_entries = build_context_queue_entries(mission_id, targets)

    queue_entry_status_by_id =
      socket.assigns
      |> Map.get(:queue_entry_status_by_id, %{})
      |> Map.merge(Map.new(queue_entries, &{&1.id, &1.status}))

    socket
    |> assign(:queue_entries, queue_entries)
    |> assign(:queue_entry_status_by_id, queue_entry_status_by_id)
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

  # ============================================================================
  # Event Aggregation - Dedupe related state transitions
  # ============================================================================

  @doc false
  # Deduplicate events by aggregate_id, keeping only the latest state.
  # Events with the same aggregate_id (e.g., CommandQueued → CommandVerified)
  # are collapsed into a single entry showing the most recent state.
  defp dedupe_by_aggregate(events) do
    # Group events by aggregate_id (from metadata)
    # Events without aggregate_id get a unique key to stay separate
    {with_aggregate, without_aggregate} =
      Enum.split_with(events, fn event ->
        get_in(event, [Access.key(:metadata, %{}), :aggregate_id]) != nil
      end)

    # Group by aggregate_id and keep the latest (most recent state)
    deduped =
      with_aggregate
      |> Enum.group_by(fn event ->
        get_in(event, [Access.key(:metadata, %{}), :aggregate_id])
      end)
      |> Enum.map(fn {_aggregate_id, group} ->
        # Keep the most recent event (latest timestamp = current state)
        Enum.max_by(group, & &1.timestamp, DateTime)
      end)

    # Combine and re-sort by timestamp descending
    (deduped ++ without_aggregate)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  # ============================================================================
  # Time Context - Bucket Headers & Gap Indicators
  # ============================================================================

  @gap_threshold_minutes 5

  @doc false
  defp add_time_context(events) do
    now = DateTime.utc_now()
    deduped = dedupe_by_aggregate(events)

    deduped
    |> Enum.with_index()
    |> Enum.map(fn {event, index} ->
      bucket = time_bucket(event.timestamp, now)
      prev_event = if index > 0, do: Enum.at(deduped, index - 1)
      prev_bucket = if prev_event, do: time_bucket(prev_event.timestamp, now)

      gap_minutes =
        if prev_event && prev_event.timestamp && event.timestamp do
          abs(DateTime.diff(prev_event.timestamp, event.timestamp, :second)) / 60
        end

      event
      |> Map.put(:time_bucket, bucket)
      |> Map.put(:show_bucket_header, bucket != prev_bucket)
      |> Map.put(:gap_minutes, gap_minutes)
    end)
  end

  defp time_bucket(nil, _now), do: "UNKNOWN"

  defp time_bucket(timestamp, now) do
    diff_seconds = DateTime.diff(now, timestamp, :second)
    diff_minutes = div(diff_seconds, 60)
    diff_hours = div(diff_minutes, 60)
    diff_days = div(diff_hours, 24)

    cond do
      diff_seconds < 0 -> "UPCOMING"
      diff_minutes < 5 -> "NOW"
      diff_minutes < 15 -> "15 MIN AGO"
      diff_minutes < 30 -> "30 MIN AGO"
      diff_hours < 1 -> "1 HOUR AGO"
      diff_hours < 2 -> "2 HOURS AGO"
      diff_hours < 4 -> "4 HOURS AGO"
      diff_hours < 8 -> "8 HOURS AGO"
      diff_hours < 24 -> "TODAY"
      diff_days < 2 -> "YESTERDAY"
      diff_days < 7 -> "THIS WEEK"
      true -> "OLDER"
    end
  end

  defp format_gap(minutes) when is_number(minutes) do
    cond do
      minutes < 60 -> "#{round(minutes)} min"
      minutes < 1440 -> "#{Float.round(minutes / 60, 1)} hrs"
      true -> "#{round(minutes / 1440)} days"
    end
  end

  defp format_gap(_), do: nil

  defp show_gap_indicator?(gap_minutes) when is_number(gap_minutes) do
    gap_minutes >= @gap_threshold_minutes
  end

  defp show_gap_indicator?(_), do: false
end
