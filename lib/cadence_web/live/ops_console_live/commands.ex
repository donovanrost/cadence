defmodule CadenceWeb.OpsConsoleLive.Commands do
  @moduledoc """
  Commands mode for OPS Console.

  Provides:
  - Target selection grid
  - Command browser with search
  - Staging panel for commands
  - Queue execution
  """

  use CadenceWeb, :live_view

  alias Cadence.{Alarms, Commands, Targets}
  alias Cadence.MissionDatabase.{Database, DefinitionSet, MetaCommand}

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.mission
    mission_id = mission.id

    # Load targets
    targets = Targets.list_targets(mission)

    # Load command definitions
    command_definitions = load_command_definitions(mission_id)

    # Load staged commands
    staged_commands = Commands.list_staged(mission_id)

    # Load data for layout
    active_alarms = Alarms.list_active_alarms(mission_id)
    alarm_counts = calculate_alarm_counts(active_alarms)

    queue_entries = build_context_queue_entries(mission_id, targets)

    fleet_health = calculate_fleet_health(targets)

    # Subscribe to updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:queue")
      Commands.subscribe_staging(mission_id)
      :timer.send_interval(1000, self(), :tick)
    end

    socket =
      socket
      |> assign(:page_title, "Commands - #{mission.name}")
      |> assign(:targets, targets)
      |> assign(:command_definitions, command_definitions)
      |> assign(:staged_commands, staged_commands)
      |> assign(:selected_targets, MapSet.new())
      |> assign(:selected_command, nil)
      |> assign(:selected_target_ids, [])
      |> assign(:per_target_mode, false)
      |> assign(:active_target_index, 0)
      |> assign(:target_search, "")
      |> assign(:command_search, "")
      |> assign(:target_view_mode, "compact")
      |> assign(:staging_expanded, true)
      |> assign(:staging_filter, "")
      |> assign(:staging_view_mode, "table")
      |> assign(:show_param_modal, nil)
      |> assign(:param_form, %{})
      |> assign(:dispatch_mode, :stage)
      |> assign(:priority, 3)
      # Layout data
      |> assign(:alarm_counts, alarm_counts)
      |> assign(:alarms, active_alarms)
      |> assign(:queue_entries, queue_entries)
      |> assign(:fleet_health, fleet_health)
      |> assign(:running_procedures, [])
      |> assign(:current_time, DateTime.utc_now())
      |> assign(:dashboards, [])
      |> assign(:current_mode, :commands)

    {:ok, socket, layout: {CadenceWeb.Layouts, :ops_console_mode}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="commands-mode-container">
      <div class="commands-mode-layout">
        <!-- Top: Target Selection and Command Browser -->
        <div class="cmd-panels-row" id="cmd-panels-row">
          <!-- Left: Target Selection -->
          <div class="cmd-target-panel" id="cmd-target-panel" phx-hook=".CmdTargetPanel">
            <div class="cmd-panel-header">
              <div class="cmd-panel-title">
                <span class="mc-label-subsystem">TARGET SELECTION</span>
                <span class="cmd-selection-count">
                  {MapSet.size(@selected_targets)} of {length(@targets)}
                </span>
              </div>
              <div class="cmd-view-toggle">
                <button
                  type="button"
                  class={["cmd-view-btn", @target_view_mode == "compact" && "active"]}
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
                  class={["cmd-view-btn", @target_view_mode == "detailed" && "active"]}
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
            <div class="cmd-target-filters">
              <input
                type="text"
                class="cmd-target-search"
                placeholder="Filter targets..."
                value={@target_search}
                phx-keyup="filter_targets"
                phx-debounce="150"
              />
            </div>
            <div class={["cmd-target-grid", @target_view_mode == "detailed" && "detailed-view"]}>
              <.cmd_target_cell
                :for={target <- filter_targets(@targets, @target_search)}
                target={target}
                selected={MapSet.member?(@selected_targets, target.id)}
                view_mode={@target_view_mode}
              />
              <div :if={filter_targets(@targets, @target_search) == []} class="cmd-empty-state">
                No targets match filter
              </div>
            </div>
            <div class="cmd-selection-actions">
              <button type="button" class="btn btn-ghost btn-xs" phx-click="select_all_targets">
                Select All
              </button>
              <button type="button" class="btn btn-ghost btn-xs" phx-click="clear_selection">
                Clear
              </button>
            </div>
          </div>
          
    <!-- Resize Handle -->
          <div class="cmd-resize-handle" id="cmd-resize-handle" phx-hook=".CmdPanelResize" phx-update="ignore"></div>
          
    <!-- Right: Command Browser -->
          <div class="cmd-command-panel">
            <div class="cmd-panel-header">
              <span class="mc-label-subsystem">COMMANDS</span>
              <span class="cmd-command-count">{length(@command_definitions)} available</span>
            </div>
            <div class="cmd-command-filters">
              <input
                type="text"
                class="cmd-command-search"
                placeholder="Search commands..."
                value={@command_search}
                phx-keyup="filter_commands"
                phx-debounce="150"
              />
            </div>
            <div class="cmd-command-list">
              <.cmd_command_item
                :for={cmd <- filter_commands(@command_definitions, @command_search)}
                command={cmd}
                selected={@selected_command && @selected_command.id == cmd.id}
              />
              <div
                :if={filter_commands(@command_definitions, @command_search) == []}
                class="cmd-empty-state"
              >
                No commands match filter
              </div>
            </div>
          </div>
        </div>
        
    <!-- Bottom: Staging Panel -->
        <.staging_panel
          staged_commands={@staged_commands}
          targets={@targets}
          command_definitions={@command_definitions}
          expanded={@staging_expanded}
          filter={@staging_filter}
          view_mode={@staging_view_mode}
        />
      </div>
    </div>

    <!-- Parameter Entry Slideout -->
    <div
      :if={@show_param_modal}
      id="cmd-slideout-backdrop"
      class="cmd-slideout-backdrop visible"
      phx-click="close_param_modal"
    >
      <.form
        for={%{}}
        phx-submit="stage_command"
        id="cmd-slideout"
        class="cmd-slideout visible"
        phx-click="ignore_slideout_click"
      >
        <div class="cmd-slideout-header">
          <div class="cmd-slideout-title">
            <div class="command-name">{@show_param_modal.name}</div>
            <div class="target-count">
              {MapSet.size(@selected_targets)} target{if MapSet.size(@selected_targets) != 1,
                do: "s",
                else: ""}
            </div>
          </div>
          <button
            type="button"
            class="cmd-slideout-close"
            phx-click="close_param_modal"
            title="Close"
          >
            ✕
          </button>
        </div>

        <div class="cmd-slideout-breadcrumb-bar">
          <span class="cmd-mode-label">
            <%= if @per_target_mode do %>
              Configuring each target
            <% else %>
              Uniform parameters
            <% end %>
          </span>
          <span
            :if={!@per_target_mode && MapSet.size(@selected_targets) > 1}
            class="cmd-mode-switch"
            phx-click="set_param_mode"
            phx-value-mode="per_target"
          >
            Configure each →
          </span>
          <span
            :if={@per_target_mode}
            class="cmd-mode-switch"
            phx-click="set_param_mode"
            phx-value-mode="uniform"
          >
            ← Uniform
          </span>
        </div>

        <div class="cmd-slideout-body">
          <div class="cmd-slideout-section">
            <div class="cmd-slideout-section-header">
              <div class="cmd-slideout-section-title">Targets</div>
            </div>
            <div class="cmd-slideout-targets">
              <span
                :for={{target, idx} <-
                  Enum.with_index(
                    Enum.filter(@targets, fn t ->
                      MapSet.member?(@selected_targets, t.id)
                    end)
                  )}
                class={[
                  "cmd-slideout-target-chip",
                  @per_target_mode && idx == @active_target_index && "active"
                ]}
                phx-click="select_param_target"
                phx-value-index={idx}
              >
                <span class="status-dot"></span>
                {target.name || target.identifier}
              </span>
              <span
                :if={
                  Enum.empty?(
                    Enum.filter(@targets, fn t ->
                      MapSet.member?(@selected_targets, t.id)
                    end)
                  )
                }
                class="cmd-empty-targets"
              >
                No targets selected
              </span>
            </div>
          </div>

          <div class="cmd-slideout-section">
            <div class="cmd-slideout-section-title">Parameters</div>
            <div class="cmd-param-form">
              <div
                :if={@show_param_modal.arguments && length(@show_param_modal.arguments) > 0}
                class="cmd-param-inputs"
              >
                <div :for={arg <- @show_param_modal.arguments} class="cmd-param-field">
                  <label class="cmd-param-label">{arg.name}</label>
                  <input
                    type={param_input_type(arg)}
                    name={"params[#{arg.name}]"}
                    value={Map.get(@param_form, arg.name, arg.default_value)}
                    class="cmd-param-input"
                  />
                </div>
              </div>
              <div
                :if={!@show_param_modal.arguments || length(@show_param_modal.arguments) == 0}
                class="cmd-no-params"
              >
                This command has no parameters.
              </div>
            </div>
          </div>
        </div>

        <div class="cmd-slideout-footer">
          <div class="cmd-slideout-options">
            <div class="cmd-slideout-priority">
              <label>Priority</label>
              <select name="priority" class="cmd-priority-select">
                <option value="1" selected={@priority == 1}>Low (1)</option>
                <option value="3" selected={@priority == 3}>Normal (3)</option>
                <option value="5" selected={@priority == 5}>High (5)</option>
                <option value="7" selected={@priority == 7}>Critical (7)</option>
              </select>
            </div>
            <div class="cmd-dispatch-mode">
              <label>Action</label>
              <div class="cmd-dispatch-mode-toggle">
                <button
                  type="button"
                  class={["cmd-mode-btn", @dispatch_mode == :stage && "active"]}
                  phx-click="set_dispatch_mode"
                  phx-value-mode="stage"
                >
                  Stage
                </button>
                <button
                  type="button"
                  class={["cmd-mode-btn", @dispatch_mode == :queue && "active"]}
                  phx-click="set_dispatch_mode"
                  phx-value-mode="queue"
                >
                  Queue
                </button>
                <button
                  type="button"
                  class={["cmd-mode-btn send-now", @dispatch_mode == :immediate && "active"]}
                  phx-click="set_dispatch_mode"
                  phx-value-mode="immediate"
                >
                  Send Now
                </button>
              </div>
            </div>
          </div>
          <div class="cmd-dispatch-actions">
            <button type="button" class="cmd-dispatch-btn cancel" phx-click="close_param_modal">
              Cancel
            </button>
            <button
              type="submit"
              class={[
                "cmd-dispatch-btn",
                @dispatch_mode == :stage && "stage",
                @dispatch_mode == :queue && "queue",
                @dispatch_mode == :immediate && "send-now"
              ]}
              phx-disable-with={dispatch_button_loading_text(@dispatch_mode)}
            >
              <%= if @per_target_mode do %>
                <% active_target =
                  Enum.at(
                    Enum.filter(@targets, fn t -> MapSet.member?(@selected_targets, t.id) end),
                    @active_target_index
                  ) %>
                {dispatch_button_text(@dispatch_mode)} {if active_target, do: active_target.name, else: "target"} ({@active_target_index + 1}/{MapSet.size(@selected_targets)})
              <% else %>
                {dispatch_button_text(@dispatch_mode)} {MapSet.size(@selected_targets)} target{if MapSet.size(@selected_targets) != 1,
                  do: "s",
                  else: ""}
              <% end %>
            </button>
          </div>
        </div>
      </.form>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CmdTargetPanel">
      export default {
        mounted() {
          this.applySavedWidth()
        },

        updated() {
          this.applySavedWidth()
        },

        applySavedWidth() {
          const savedWidth = localStorage.getItem('cmd-target-panel-width')
          if (savedWidth) {
            this.el.style.flex = `0 0 ${savedWidth}%`
          }
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CmdPanelResize">
      export default {
        mounted() {
          this.isDragging = false
          this.startX = 0
          this.startWidth = 0
          this.targetPanel = document.getElementById('cmd-target-panel')
          this._startDrag = (event) => this.startDrag(event)
          this._onDrag = (event) => this.onDrag(event)
          this._endDrag = () => this.endDrag()
          this.el.addEventListener('mousedown', this._startDrag)
          document.addEventListener('mousemove', this._onDrag)
          document.addEventListener('mouseup', this._endDrag)

          // Load saved width
          const savedWidth = localStorage.getItem('cmd-target-panel-width')
          if (savedWidth && this.targetPanel) {
            this.targetPanel.style.flex = `0 0 ${savedWidth}%`
          }
        },

        updated() {
          // Re-query the target panel in case it was replaced
          this.targetPanel = document.getElementById('cmd-target-panel')
          // Reapply saved width after LiveView DOM patches
          const savedWidth = localStorage.getItem('cmd-target-panel-width')
          if (savedWidth && this.targetPanel) {
            this.targetPanel.style.flex = `0 0 ${savedWidth}%`
          }
        },

        startDrag(event) {
          if (!this.targetPanel) {
            this.targetPanel = document.getElementById('cmd-target-panel')
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
          const panelsRow = document.getElementById('cmd-panels-row')
          if (!panelsRow) return
          const diff = event.clientX - this.startX
          const newWidth = Math.max(150, Math.min(panelsRow.offsetWidth * 0.6, this.startWidth + diff))
          this.targetPanel.style.flex = `0 0 ${newWidth}px`
          // Save as percentage for persistence
          const newPercent = (newWidth / panelsRow.offsetWidth) * 100
          localStorage.setItem('cmd-target-panel-width', newPercent.toFixed(1))
        },

        endDrag() {
          if (!this.isDragging) return
          this.isDragging = false
          document.body.style.cursor = ''
          document.body.style.userSelect = ''
          this.el.classList.remove('dragging')
          if (this.targetPanel) {
            const panelsRow = document.getElementById('cmd-panels-row')
            if (panelsRow) {
              const percent = (this.targetPanel.offsetWidth / panelsRow.offsetWidth) * 100
              localStorage.setItem('cmd-target-panel-width', percent.toFixed(1))
            }
          }
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

  # Target cell component
  attr :target, :map, required: true
  attr :selected, :boolean, required: true
  attr :view_mode, :string, required: true

  defp cmd_target_cell(assigns) do
    status_class = Map.get(assigns.target, :status, :online)
    mode = Map.get(assigns.target, :mode) || Map.get(assigns.target, :active_limit_set) || "NOMINAL"
    target_type = Map.get(assigns.target, :target_type) || Map.get(assigns.target, :type) || "Unknown"

    assigns =
      assigns
      |> assign(:status_class, status_class)
      |> assign(:mode, mode)
      |> assign(:target_type, target_type)

    ~H"""
    <div
      class={[
        "cmd-target-cell",
        @selected && "selected",
        "status-#{@status_class}"
      ]}
      phx-click="toggle_target"
      phx-value-id={@target.id}
    >
      <%= if @view_mode == "detailed" do %>
        <div class="cmd-target-main">
          <span class="cmd-target-name">{@target.name}</span>
          <span class="cmd-target-mode">{@mode}</span>
        </div>
        <div class="cmd-target-meta">
          <span class="cmd-target-type">{@target_type}</span>
        </div>
      <% else %>
        <span class="cmd-target-name">{@target.name}</span>
      <% end %>
    </div>
    """
  end

  # Command item component
  attr :command, :map, required: true
  attr :selected, :boolean, required: true

  defp cmd_command_item(assigns) do
    opcode_hex =
      if assigns.command.opcode do
        "0x" <>
          String.upcase(
            Integer.to_string(assigns.command.opcode, 16)
            |> String.pad_leading(4, "0")
          )
      else
        nil
      end

    assigns = assign(assigns, :opcode_hex, opcode_hex)

    ~H"""
    <div
      class={[
        "cmd-command-item",
        @selected && "selected",
        @command.is_hazardous && "hazardous"
      ]}
      phx-click="select_command"
      phx-value-id={@command.id}
    >
      <div class="cmd-command-header">
        <span class="cmd-command-name">{@command.name}</span>
        <span :if={@command.is_hazardous} class="cmd-hazard-badge">HAZARD</span>
      </div>
      <div class="cmd-command-meta">
        <span :if={@opcode_hex} class="cmd-opcode">{@opcode_hex}</span>
        <span :if={@command.description} class="cmd-description">{@command.description}</span>
      </div>
    </div>
    """
  end

  # Staging panel component
  attr :staged_commands, :list, required: true
  attr :targets, :list, required: true
  attr :command_definitions, :list, required: true
  attr :expanded, :boolean, required: true
  attr :filter, :string, required: true
  attr :view_mode, :string, required: true

  defp staging_panel(assigns) do
    total_items = count_staged_items(assigns.staged_commands)
    is_empty = total_items == 0

    assigns =
      assigns
      |> assign(:total_items, total_items)
      |> assign(:is_empty, is_empty)

    ~H"""
    <div class={[
      "cmd-staging-panel",
      @is_empty && "empty",
      !@is_empty && !@expanded && "minimized",
      !@is_empty && @expanded && "expanded",
      @view_mode == "cards" && "card-view",
      @view_mode == "table" && "table-view"
    ]}>
      <div class="cmd-staging-resize-handle" id="staging-resize-handle"></div>
      <div class="cmd-staging-header" phx-click="toggle_staging_panel">
        <div class="cmd-staging-title">
          <span class="mc-label-subsystem">STAGED</span>
          <span class="cmd-staging-count">
            {if @is_empty,
              do: "empty",
              else: "#{@total_items} item#{if @total_items != 1, do: "s", else: ""}"}
          </span>
        </div>
        <div class="cmd-staging-actions">
          <div :if={!@is_empty && @expanded} class="cmd-staging-view-toggle">
            <button
              type="button"
              class={["cmd-view-btn", @view_mode == "table" && "active"]}
              phx-click="set_staging_view_mode"
              phx-value-mode="table"
              title="Table view"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M3 6h18M3 12h18M3 18h18" />
              </svg>
            </button>
            <button
              type="button"
              class={["cmd-view-btn", @view_mode == "cards" && "active"]}
              phx-click="set_staging_view_mode"
              phx-value-mode="cards"
              title="Card view"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="3" y="3" width="7" height="7" rx="1" />
                <rect x="14" y="3" width="7" height="7" rx="1" />
                <rect x="3" y="14" width="7" height="7" rx="1" />
                <rect x="14" y="14" width="7" height="7" rx="1" />
              </svg>
            </button>
          </div>
          <button
            type="button"
            class="cmd-staging-btn queue-all"
            phx-click="queue_all_staged"
            disabled={@is_empty}
          >
            Queue All ({@total_items})
          </button>
          <button
            type="button"
            class="cmd-staging-btn clear"
            phx-click="clear_staged"
            disabled={@is_empty}
          >
            Clear
          </button>
        </div>
      </div>

      <div :if={!@is_empty && @expanded} class="cmd-staging-filters">
        <input
          type="text"
          class="cmd-staging-search"
          placeholder="Filter by target or command..."
          value={@filter}
          phx-keyup="filter_staging"
          phx-debounce="150"
        />
      </div>

      <div :if={!@is_empty && @expanded} class="cmd-staging-body">
        <%= if @view_mode == "table" do %>
          <table class="cmd-staging-table">
            <thead>
              <tr>
                <th>Target</th>
                <th>Command</th>
                <th>Parameters</th>
                <th>Pri</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for {staged, cmd_idx} <- Enum.with_index(@staged_commands),
                      {target_entry, target_idx} <- Enum.with_index(staged.targets) do %>
                <.staged_row
                  staged={staged}
                  target_entry={target_entry}
                  cmd_idx={cmd_idx}
                  target_idx={target_idx}
                  targets={@targets}
                  command_definitions={@command_definitions}
                  filter={@filter}
                />
              <% end %>
            </tbody>
          </table>
        <% else %>
          <div class="cmd-staging-cards">
            <%= for {staged, cmd_idx} <- Enum.with_index(@staged_commands),
                    {target_entry, target_idx} <- Enum.with_index(staged.targets) do %>
              <.staged_card
                staged={staged}
                target_entry={target_entry}
                cmd_idx={cmd_idx}
                target_idx={target_idx}
                targets={@targets}
                command_definitions={@command_definitions}
                filter={@filter}
              />
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="cmd-staging-panel-corners"></div>
    </div>
    """
  end

  # Staged row component (table view)
  attr :staged, :map, required: true
  attr :target_entry, :map, required: true
  attr :cmd_idx, :integer, required: true
  attr :target_idx, :integer, required: true
  attr :targets, :list, required: true
  attr :command_definitions, :list, required: true
  attr :filter, :string, required: true

  defp staged_row(assigns) do
    target = Enum.find(assigns.targets, &(&1.id == assigns.target_entry.target_id))
    target_name = if target, do: target.name, else: assigns.target_entry.target_id
    cmd_def =
      Enum.find(assigns.command_definitions, fn cmd ->
        cmd.id == (assigns.staged.meta_command_id || assigns.staged.command_id)
      end)
    is_hazardous = cmd_def && cmd_def.is_hazardous

    params = assigns.target_entry.params || %{}

    params_preview =
      params |> Enum.take(3) |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)

    has_more_params = map_size(params) > 3

    # Filter check
    filter = String.downcase(assigns.filter)

    matches =
      filter == "" or
        String.contains?(String.downcase(target_name), filter) or
        String.contains?(String.downcase(assigns.staged.command_name), filter)

    assigns =
      assigns
      |> assign(:target_name, target_name)
      |> assign(:is_hazardous, is_hazardous)
      |> assign(:params_preview, params_preview)
      |> assign(:has_more_params, has_more_params)
      |> assign(:matches, matches)

    ~H"""
    <tr :if={@matches} class={["cmd-staged-row", @is_hazardous && "hazardous"]}>
      <td class="cmd-staged-target">{@target_name}</td>
      <td class="cmd-staged-command">
        {@staged.command_name}
        <span :if={@is_hazardous} class="cmd-hazard-badge-sm">HAZ</span>
      </td>
      <td class="cmd-staged-params">{@params_preview}{if @has_more_params, do: "...", else: ""}</td>
      <td class="cmd-staged-priority">P{@staged.priority}</td>
      <td class="cmd-staged-actions">
        <div class="cmd-staged-actions-inner">
          <button
            type="button"
            class="cmd-staged-queue"
            phx-click="queue_staged_item"
            phx-value-cmd-idx={@cmd_idx}
            phx-value-target-idx={@target_idx}
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M5 12h14M12 5l7 7-7 7" />
            </svg>
            <span class="cmd-action-label">Queue</span>
          </button>
          <button
            type="button"
            class="cmd-staged-remove"
            phx-click="remove_staged_item"
            phx-value-cmd-idx={@cmd_idx}
            phx-value-target-idx={@target_idx}
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M18 6L6 18M6 6l12 12" />
            </svg>
            <span class="cmd-action-label">Remove</span>
          </button>
        </div>
      </td>
    </tr>
    """
  end

  # Staged card component (card view)
  attr :staged, :map, required: true
  attr :target_entry, :map, required: true
  attr :cmd_idx, :integer, required: true
  attr :target_idx, :integer, required: true
  attr :targets, :list, required: true
  attr :command_definitions, :list, required: true
  attr :filter, :string, required: true

  defp staged_card(assigns) do
    target = Enum.find(assigns.targets, &(&1.id == assigns.target_entry.target_id))
    target_name = if target, do: target.name, else: assigns.target_entry.target_id
    cmd_def =
      Enum.find(assigns.command_definitions, fn cmd ->
        cmd.id == (assigns.staged.meta_command_id || assigns.staged.command_id)
      end)
    is_hazardous = cmd_def && cmd_def.is_hazardous

    params = assigns.target_entry.params || %{}

    # Filter check
    filter = String.downcase(assigns.filter)

    matches =
      filter == "" or
        String.contains?(String.downcase(target_name), filter) or
        String.contains?(String.downcase(assigns.staged.command_name), filter)

    assigns =
      assigns
      |> assign(:target_name, target_name)
      |> assign(:is_hazardous, is_hazardous)
      |> assign(:params, params)
      |> assign(:matches, matches)

    ~H"""
    <div :if={@matches} class={["cmd-staged-card", @is_hazardous && "hazardous"]}>
      <div class="cmd-card-header">
        <span class="cmd-card-target">{@target_name}</span>
        <span class="cmd-card-priority">P{@staged.priority}</span>
      </div>
      <div class="cmd-card-command">
        {@staged.command_name}
        <span :if={@is_hazardous} class="cmd-hazard-badge-sm">HAZ</span>
      </div>
      <div :if={map_size(@params) > 0} class="cmd-card-params">
        <div :for={{key, val} <- Enum.take(@params, 4)} class="cmd-card-param">
          <span class="cmd-card-param-key">{key}</span>
          <span class="cmd-card-param-val">{val}</span>
        </div>
      </div>
      <div class="cmd-card-actions">
        <button
          type="button"
          class="cmd-card-btn queue"
          phx-click="queue_staged_item"
          phx-value-cmd-idx={@cmd_idx}
          phx-value-target-idx={@target_idx}
        >
          Queue
        </button>
        <button
          type="button"
          class="cmd-card-btn remove"
          phx-click="remove_staged_item"
          phx-value-cmd-idx={@cmd_idx}
          phx-value-target-idx={@target_idx}
        >
          Remove
        </button>
      </div>
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

  def handle_event("clear_selection", _, socket) do
    {:noreply, assign(socket, :selected_targets, MapSet.new())}
  end

  def handle_event("filter_targets", %{"value" => value}, socket) do
    {:noreply, assign(socket, :target_search, value)}
  end

  def handle_event("set_target_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :target_view_mode, mode)}
  end

  def handle_event("filter_commands", %{"value" => value}, socket) do
    {:noreply, assign(socket, :command_search, value)}
  end

  def handle_event("set_param_mode", %{"mode" => mode}, socket) do
    per_target = mode == "per_target"
    {:noreply, assign(socket, :per_target_mode, per_target)}
  end

  def handle_event("set_dispatch_mode", %{"mode" => mode}, socket) do
    dispatch_mode =
      case mode do
        "stage" -> :stage
        "queue" -> :queue
        "immediate" -> :immediate
        _ -> :stage
      end

    {:noreply, assign(socket, :dispatch_mode, dispatch_mode)}
  end

  def handle_event("select_param_target", %{"index" => index}, socket) do
    idx = String.to_integer(index)
    {:noreply, assign(socket, :active_target_index, idx)}
  end

  def handle_event("select_command", %{"id" => id}, socket) do
    command = Enum.find(socket.assigns.command_definitions, &(&1.id == id))

    if MapSet.size(socket.assigns.selected_targets) == 0 do
      {:noreply, put_flash(socket, :error, "Select at least one target first")}
    else
      selected_ids = socket.assigns.selected_targets |> Enum.to_list()
      has_multiple = length(selected_ids) > 1

      {:noreply,
       socket
       |> assign(:selected_command, command)
       |> assign(:show_param_modal, command)
       |> assign(:param_form, %{})
       |> assign(:selected_target_ids, selected_ids)
       |> assign(:per_target_mode, has_multiple)
       |> assign(:active_target_index, 0)}
    end
  end

  def handle_event("close_param_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_param_modal, nil)
     |> assign(:selected_command, nil)
     |> assign(:per_target_mode, false)
     |> assign(:active_target_index, 0)
     |> assign(:selected_target_ids, [])}
  end

  def handle_event("ignore_slideout_click", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("stage_command", %{"priority" => priority} = params, socket) do
    command = socket.assigns.show_param_modal
    priority = String.to_integer(priority)
    dispatch_mode = socket.assigns.dispatch_mode
    cmd_params = Map.get(params, "params", %{})

    user = socket.assigns.current_scope.user
    mission_id = socket.assigns.mission.id

    if socket.assigns.per_target_mode do
      dispatch_per_target(socket, command, cmd_params, priority, dispatch_mode, user, mission_id)
    else
      dispatch_uniform(socket, command, cmd_params, priority, dispatch_mode, user, mission_id)
    end
  end

  def handle_event("toggle_staging_panel", _, socket) do
    {:noreply, assign(socket, :staging_expanded, !socket.assigns.staging_expanded)}
  end

  def handle_event("set_staging_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :staging_view_mode, mode)}
  end

  def handle_event("filter_staging", %{"value" => value}, socket) do
    {:noreply, assign(socket, :staging_filter, value)}
  end

  def handle_event("queue_all_staged", _, socket) do
    mission_id = socket.assigns.mission.id

    case Commands.queue_all_staged(mission_id) do
      {:ok, _count} ->
        staged_commands = Commands.list_staged(mission_id)

        {:noreply,
         socket
         |> assign(:staged_commands, staged_commands)
         |> put_flash(:info, "All staged commands queued")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue: #{inspect(reason)}")}
    end
  end

  def handle_event("clear_staged", _, socket) do
    Commands.clear_stage(socket.assigns.mission.id)
    staged_commands = Commands.list_staged(socket.assigns.mission.id)

    {:noreply,
     socket
     |> assign(:staged_commands, staged_commands)
     |> put_flash(:info, "Staging area cleared")}
  end

  def handle_event(
        "queue_staged_item",
        %{"cmd-idx" => cmd_idx, "target-idx" => target_idx},
        socket
      ) do
    cmd_idx = String.to_integer(cmd_idx)
    target_idx = String.to_integer(target_idx)

    staged = Enum.at(socket.assigns.staged_commands, cmd_idx)
    target_entry = Enum.at(staged.targets, target_idx)

    # queue_staged_target also removes the target from staging on success
    case Commands.queue_staged_target(target_entry.id) do
      {:ok, _queue_entry} ->
        staged_commands = Commands.list_staged(socket.assigns.mission.id)

        {:noreply,
         socket
         |> assign(:staged_commands, staged_commands)
         |> put_flash(:info, "Command queued")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "remove_staged_item",
        %{"cmd-idx" => cmd_idx, "target-idx" => target_idx},
        socket
      ) do
    cmd_idx = String.to_integer(cmd_idx)
    target_idx = String.to_integer(target_idx)

    staged = Enum.at(socket.assigns.staged_commands, cmd_idx)
    target_entry = Enum.at(staged.targets, target_idx)

    Commands.remove_staged_target(target_entry.id)
    staged_commands = Commands.list_staged(socket.assigns.mission.id)

    {:noreply, assign(socket, :staged_commands, staged_commands)}
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
  def handle_info({:staging_updated, _}, socket) do
    staged_commands = Commands.list_staged(socket.assigns.mission.id)
    {:noreply, assign(socket, :staged_commands, staged_commands)}
  end

  def handle_info({:queue_updated, _entry}, socket) do
    {:noreply, refresh_queue_entries(socket)}
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

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :current_time, DateTime.utc_now())}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # Private helpers

  defp load_command_definitions(mission_id) do
    import Ecto.Query

    # Find first published definition set for this mission
    definition_set =
      from(ds in DefinitionSet,
        join: db in Database,
        on: ds.database_id == db.id,
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

  defp filter_targets(targets, search) do
    if search == "" do
      targets
    else
      search_lower = String.downcase(search)

      Enum.filter(targets, fn t ->
        String.contains?(String.downcase(t.name || ""), search_lower)
      end)
    end
  end

  defp filter_commands(commands, search) do
    if search == "" do
      commands
    else
      search_lower = String.downcase(search)

      Enum.filter(commands, fn cmd ->
        String.contains?(String.downcase(cmd.name || ""), search_lower) or
          String.contains?(String.downcase(cmd.description || ""), search_lower)
      end)
    end
  end

  defp count_staged_items(staged_commands) do
    Enum.reduce(staged_commands, 0, fn staged, acc ->
      acc + length(staged.targets)
    end)
  end

  defp param_input_type(%{data_type_ref: ref}) when is_binary(ref) do
    down = String.downcase(ref)

    cond do
      String.contains?(down, "bool") -> "checkbox"
      String.contains?(down, "int") -> "number"
      String.contains?(down, "float") or String.contains?(down, "double") -> "number"
      true -> "text"
    end
  end

  defp param_input_type(_), do: "text"

  defp dispatch_button_text(:stage), do: "Stage"
  defp dispatch_button_text(:queue), do: "Queue"
  defp dispatch_button_text(:immediate), do: "Send"

  defp dispatch_button_loading_text(:stage), do: "Staging..."
  defp dispatch_button_loading_text(:queue), do: "Queueing..."
  defp dispatch_button_loading_text(:immediate), do: "Sending..."

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

  # Dispatch helpers for different modes

  defp dispatch_per_target(socket, command, cmd_params, priority, dispatch_mode, user, mission_id) do
    target_ids = socket.assigns.selected_target_ids || []
    active_index = socket.assigns.active_target_index || 0
    target_id = Enum.at(target_ids, active_index)

    if is_nil(target_id) do
      {:noreply, socket}
    else
      target = Enum.find(socket.assigns.targets, &(&1.id == target_id))
      target_name = if target, do: target.name, else: target_id

      result = execute_dispatch(dispatch_mode, mission_id, command, target_id, cmd_params, priority, user)

      case result do
        {:ok, _} ->
          staged_commands = Commands.list_staged(mission_id)
          queue_entries = build_context_queue_entries(mission_id, socket.assigns.targets)

          next_index =
            case length(target_ids) do
              0 -> 0
              count -> rem(active_index + 1, count)
            end

          {:noreply,
           socket
           |> assign(:staged_commands, staged_commands)
           |> assign(:queue_entries, queue_entries)
           |> assign(:active_target_index, next_index)
           |> put_flash(:info, "#{dispatch_action_past(dispatch_mode)} #{target_name}")}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Failed to #{dispatch_action_verb(dispatch_mode)}: #{format_error(reason)}")}
      end
    end
  end

  defp dispatch_uniform(socket, command, cmd_params, priority, dispatch_mode, user, mission_id) do
    target_ids = MapSet.to_list(socket.assigns.selected_targets)

    results =
      Enum.map(target_ids, fn target_id ->
        execute_dispatch(dispatch_mode, mission_id, command, target_id, cmd_params, priority, user)
      end)

    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = length(results) - successes

    cond do
      failures == 0 ->
        staged_commands = Commands.list_staged(mission_id)
        queue_entries = build_context_queue_entries(mission_id, socket.assigns.targets)

        {:noreply,
         socket
         |> assign(:staged_commands, staged_commands)
         |> assign(:queue_entries, queue_entries)
         |> assign(:show_param_modal, nil)
         |> assign(:selected_command, nil)
         |> assign(:selected_targets, MapSet.new())
         |> assign(:selected_target_ids, [])
         |> assign(:per_target_mode, false)
         |> assign(:active_target_index, 0)
         |> put_flash(:info, "#{dispatch_action_past(dispatch_mode)} #{successes} target(s)")}

      successes == 0 ->
        {:noreply, put_flash(socket, :error, "Failed to #{dispatch_action_verb(dispatch_mode)} commands")}

      true ->
        staged_commands = Commands.list_staged(mission_id)
        queue_entries = build_context_queue_entries(mission_id, socket.assigns.targets)

        {:noreply,
         socket
         |> assign(:staged_commands, staged_commands)
         |> assign(:queue_entries, queue_entries)
         |> put_flash(
           :warning,
           "#{dispatch_action_past(dispatch_mode)} #{successes} target(s), #{failures} failed"
         )}
    end
  end

  defp execute_dispatch(:stage, mission_id, command, target_id, cmd_params, priority, user) do
    # For staging, we pass target info directly - target name will be resolved from context
    targets = [
      %{
        target_id: target_id,
        target_name: target_id,
        params: cmd_params
      }
    ]

    Commands.add_to_stage(user, mission_id, command, targets, priority: priority)
  end

  defp execute_dispatch(:queue, mission_id, command, target_id, cmd_params, priority, _user) do
    Commands.enqueue(mission_id, command.name, cmd_params, target_id: target_id, priority: priority)
  end

  defp execute_dispatch(:immediate, mission_id, command, target_id, cmd_params, priority, _user) do
    Commands.dispatch(mission_id, command.name, cmd_params, target_id: target_id, priority: priority)
  end

  defp dispatch_action_verb(:stage), do: "stage"
  defp dispatch_action_verb(:queue), do: "queue"
  defp dispatch_action_verb(:immediate), do: "send"

  defp dispatch_action_past(:stage), do: "Staged"
  defp dispatch_action_past(:queue), do: "Queued"
  defp dispatch_action_past(:immediate), do: "Sent"

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error(reason), do: inspect(reason)
end
