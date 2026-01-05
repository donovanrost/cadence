defmodule CadenceWeb.OpsConsoleLive.Components do
  @moduledoc """
  Shared function components for OPS Console modes.

  These components are used across Commands, Queue, Alarms, and Timeline modes
  to provide consistent UI patterns and reduce duplication.
  """

  use Phoenix.Component
  use CadenceWeb, :verified_routes

  alias Phoenix.LiveView.JS

  # ============================================================================
  # Context Panel Components
  # ============================================================================

  @doc """
  Generic container for the OPS context panel.

  The outer `aside.panel-context` element controls collapsed/expanded state
  via CSS; this component simply renders expanded and rail content slots.
  """
  attr :id, :string, default: nil
  attr :class, :string, default: ""
  slot :expanded, required: true
  slot :rail

  def context_panel(assigns) do
    ~H"""
    <div id={@id} class={["flex flex-col h-full", @class]}>
      <div class="context-panel-v2 p-3 hud-grid">
        {render_slot(@expanded)}
      </div>

      <div class="context-rail flex-col items-center py-2 gap-1 hud-grid">
        {render_slot(@rail)}
      </div>
    </div>
    """
  end

  attr :alarms, :list, required: true
  attr :alarm_counts, :map, required: true
  attr :collapsed_sections, :any, default: MapSet.new()
  attr :toggle_target, :any, default: nil

  def context_alarms_section(assigns) do
    grouped_alarms = group_alarms_by_severity(assigns.alarms)

    total_alarms =
      case assigns.alarm_counts do
        %{critical: c, warning: w, info: i} -> c + w + i
        _ -> 0
      end

    assigns =
      assigns
      |> assign(:grouped_alarms, grouped_alarms)
      |> assign(:total_alarms, total_alarms)

    ~H"""
    <div class={["context-section", MapSet.member?(@collapsed_sections, :alarms) && "collapsed"]}>
      <button
        type="button"
        class="context-section-header"
        phx-click="toggle_section"
        phx-value-section="alarms"
        phx-target={@toggle_target}
      >
        <div class="flex items-center gap-2">
          <svg
            class="section-chevron w-3 h-3 transition-transform"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
          <span class="mc-label-subsystem text-base-content/40">ACTIVE ALARMS</span>
          <span class="text-xs text-base-content/60">({@total_alarms})</span>
        </div>
        <div :if={@total_alarms > 0} class="flex items-center gap-1.5">
          <span :if={@alarm_counts.critical > 0} class="w-2 h-2 rounded-full bg-error"></span>
          <span :if={@alarm_counts.warning > 0} class="w-2 h-2 rounded-full bg-warning"></span>
          <span :if={@alarm_counts.info > 0} class="w-2 h-2 rounded-full bg-info"></span>
        </div>
      </button>
      <div class="context-section-content">
        <div :if={length(@grouped_alarms.critical) > 0} class="alarm-group mb-3">
          <div class="alarm-group-header alarm-group-critical mb-2">
            <span class="w-2 h-2 rounded-full bg-error"></span>
            <span>CRITICAL ({length(@grouped_alarms.critical)})</span>
          </div>
          <div class="flex flex-col gap-1">
            <.context_alarm_item :for={alarm <- @grouped_alarms.critical} alarm={alarm} />
          </div>
        </div>

        <div :if={length(@grouped_alarms.warning) > 0} class="alarm-group mb-3">
          <div class="alarm-group-header alarm-group-warning mb-2">
            <span class="w-2 h-2 rounded-full bg-warning"></span>
            <span>WARNING ({length(@grouped_alarms.warning)})</span>
          </div>
          <div class="flex flex-col gap-1">
            <.context_alarm_item :for={alarm <- @grouped_alarms.warning} alarm={alarm} />
          </div>
        </div>

        <div :if={length(@grouped_alarms.info) > 0} class="alarm-group mb-3">
          <div class="alarm-group-header alarm-group-info mb-2">
            <span class="w-2 h-2 rounded-full bg-info"></span>
            <span>INFO ({length(@grouped_alarms.info)})</span>
          </div>
          <div class="flex flex-col gap-1">
            <.context_alarm_item :for={alarm <- @grouped_alarms.info} alarm={alarm} />
          </div>
        </div>

        <div :if={@total_alarms == 0} class="text-center py-4 text-base-content/40">
          <p class="text-xs">No active alarms</p>
        </div>
      </div>
    </div>
    """
  end

  attr :alarm, :map, required: true

  def context_alarm_item(assigns) do
    severity_class = alarm_severity_class(assigns.alarm)
    assigns = assign(assigns, :severity_class, severity_class)

    ~H"""
    <div class={"alarm-item #{@severity_class}"} data-id={@alarm.id}>
      <div class="alarm-header">
        <span class="alarm-source">{alarm_source(@alarm)}</span>
        <span class="alarm-time">{format_alarm_time(@alarm.triggered_at)}</span>
      </div>
      <div class="alarm-message">{@alarm.message || @alarm.name || "Alarm"}</div>
      <div class="alarm-actions">
        <button
          type="button"
          class="alarm-btn alarm-btn-ack"
          phx-click="acknowledge_alarm"
          phx-value-id={@alarm.id}
        >
          ACK
        </button>
        <button
          type="button"
          class="alarm-btn alarm-btn-clear"
          phx-click="clear_alarm"
          phx-value-id={@alarm.id}
        >
          CLEAR
        </button>
      </div>
    </div>
    """
  end

  attr :queue_entries, :list, required: true
  attr :targets_map, :map, default: %{}
  attr :collapsed_sections, :any, default: MapSet.new()
  attr :toggle_target, :any, default: nil

  def context_queue_section(assigns) do
    has_executing = Enum.any?(assigns.queue_entries, &(&1.status == :executing))

    assigns = assign(assigns, :has_executing, has_executing)

    ~H"""
    <div class={[
      "context-section mt-3 pt-3 border-t border-base-300",
      MapSet.member?(@collapsed_sections, :queue) && "collapsed"
    ]}>
      <button
        type="button"
        class="context-section-header"
        phx-click="toggle_section"
        phx-value-section="queue"
        phx-target={@toggle_target}
      >
        <div class="flex items-center gap-2">
          <svg
            class="section-chevron w-3 h-3 transition-transform"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
          <span class="mc-label-subsystem text-base-content/40">COMMAND QUEUE</span>
          <span class="text-xs text-base-content/60">({length(@queue_entries)})</span>
        </div>
        <span
          :if={@has_executing}
          class="w-2 h-2 rounded-full bg-warning animate-pulse"
        >
        </span>
      </button>
      <div class="context-section-content cmd-queue-list">
        <.context_queue_entry_item
          :for={entry <- Enum.take(@queue_entries, 10)}
          entry={entry}
          targets_map={@targets_map}
        />
        <p
          :if={@queue_entries == []}
          class="text-xs text-base-content/40 text-center py-4"
        >
          No pending commands
        </p>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :targets_map, :map, default: %{}

  def context_queue_entry_item(assigns) do
    status = assigns.entry.status || :pending
    status_class = queue_status_class(status)
    priority = Map.get(assigns.entry, :priority, 3)
    priority_class = priority_class(priority)

    status_label =
      case status do
        :pending -> "PEND"
        :held -> "HOLD"
        :executing -> "EXEC"
        :completed -> "DONE"
        :failed -> "FAIL"
        other -> other |> to_string() |> String.upcase() |> String.slice(0, 4)
      end

    target_name = queue_target_name(assigns.entry, assigns.targets_map)

    assigns =
      assigns
      |> assign(:status_class, status_class)
      |> assign(:priority, priority)
      |> assign(:priority_class, priority_class)
      |> assign(:status_label, status_label)
      |> assign(:is_executing, status == :executing)
      |> assign(:is_failed, status == :failed)
      |> assign(:target_name, target_name)

    ~H"""
    <div class={"qe #{@status_class}"} data-id={@entry.id}>
      <div class="qe-meta-row">
        <span class="qe-target">{@target_name}</span>
        <div class="qe-badges">
          <span class={"qe-priority #{@priority_class}"}>P{@priority}</span>
          <span class="qe-status">{@status_label}</span>
        </div>
      </div>
      <div class="qe-command-row">
        <span :if={@is_executing} class="qe-pulse-inline"></span>
        <svg
          :if={@is_failed}
          class="qe-error-inline"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
          />
        </svg>
        <span class="qe-command">{@entry.command_name || "Command"}</span>
      </div>
      <.context_queue_params_row :if={has_params?(@entry)} entry={@entry} />
    </div>
    """
  end

  attr :entry, :map, required: true

  def context_queue_params_row(assigns) do
    params = Map.get(assigns.entry, :parameters, %{}) || %{}
    param_items = Enum.take(params, 3)
    assigns = assign(assigns, :param_items, param_items)

    ~H"""
    <div class="qe-params-row">
      <span :for={{key, val} <- @param_items} class="qe-param-item">
        <span class="qe-param-key">{key}</span>
        <span class="qe-param-val">{format_param_value(val)}</span>
      </span>
    </div>
    """
  end

  attr :alarm_counts, :map, required: true
  attr :queue_entries, :list, required: true

  def context_panel_rail(assigns) do
    ~H"""
    <div>
      <div
        class={["rail-alarm-badge critical", @alarm_counts.critical > 0 && "has-alarms"]}
        title="Critical Alarms"
      >
        <span class="rail-alarm-count">{@alarm_counts.critical}</span>
        <span class="rail-alarm-label">CRIT</span>
      </div>

      <div class="rail-alarm-badge warning" title="Warning Alarms">
        <span class="rail-alarm-count">{@alarm_counts.warning}</span>
        <span class="rail-alarm-label">WARN</span>
      </div>

      <div class="rail-alarm-badge info" title="Info Alarms">
        <span class="rail-alarm-count">{@alarm_counts.info}</span>
        <span class="rail-alarm-label">INFO</span>
      </div>

      <div class="rail-divider"></div>

      <div
        class={["rail-command-badge", length(@queue_entries) > 0 && "has-commands"]}
        title="Pending Commands"
      >
        <span class="rail-command-count">{length(@queue_entries)}</span>
        <span class="rail-command-label">CMD</span>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Target Selection Components
  # ============================================================================

  @doc """
  Renders a target selector panel with search, grid, and selection controls.

  ## Attributes
    * `:targets` - List of target structs
    * `:selected` - MapSet of selected target IDs
    * `:search` - Current search term (default "")
    * `:view` - Display mode, :compact or :detailed (default :compact)
    * `:on_select` - Event name for selection toggle
    * `:on_select_all` - Event name for select all
    * `:on_clear` - Event name for clear selection

  ## Examples

      <.target_selector
        targets={@targets}
        selected={@selected_targets}
        on_select="toggle_target"
        on_select_all="select_all_targets"
        on_clear="clear_target_selection"
      />
  """
  attr :targets, :list, required: true
  attr :selected, :any, default: MapSet.new()
  attr :search, :string, default: ""
  attr :view, :atom, default: :compact
  attr :on_select, :string, required: true
  attr :on_select_all, :string, default: nil
  attr :on_clear, :string, default: nil
  attr :class, :string, default: ""

  def target_selector(assigns) do
    filtered_targets =
      if assigns.search == "" do
        assigns.targets
      else
        search_down = String.downcase(assigns.search)

        Enum.filter(assigns.targets, fn t ->
          String.contains?(String.downcase(t.name), search_down)
        end)
      end

    assigns = assign(assigns, :filtered_targets, filtered_targets)

    ~H"""
    <div class={["target-selector flex flex-col h-full", @class]}>
      <!-- Header with view toggle -->
      <div class="flex items-center justify-between px-2 py-1.5 border-b border-base-300">
        <span class="mc-label-subsystem text-base-content/40">TARGETS</span>
        <div class="flex items-center gap-1">
          <button
            type="button"
            phx-click={JS.push("set_target_view", value: %{view: "compact"})}
            class={[
              "btn btn-ghost btn-xs",
              @view == :compact && "btn-active"
            ]}
            title="Compact view"
          >
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"
              />
            </svg>
          </button>
          <button
            type="button"
            phx-click={JS.push("set_target_view", value: %{view: "detailed"})}
            class={[
              "btn btn-ghost btn-xs",
              @view == :detailed && "btn-active"
            ]}
            title="Detailed view"
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
        </div>
      </div>
      <!-- Search -->
      <div class="px-2 py-1.5 border-b border-base-300">
        <input
          type="text"
          placeholder="Filter targets..."
          value={@search}
          phx-keyup="filter_targets"
          phx-debounce="150"
          class="input input-xs input-bordered w-full bg-base-300/50"
        />
      </div>
      <!-- Target grid -->
      <div class="flex-1 overflow-y-auto p-2">
        <div class={[
          "grid gap-1",
          @view == :compact && "grid-cols-4",
          @view == :detailed && "grid-cols-1"
        ]}>
          <.target_cell
            :for={target <- @filtered_targets}
            target={target}
            selected={MapSet.member?(@selected, target.id)}
            view={@view}
            on_select={@on_select}
          />
        </div>
        <div :if={@filtered_targets == []} class="text-center text-base-content/40 py-4 text-xs">
          No targets match filter
        </div>
      </div>
      <!-- Selection actions -->
      <div
        :if={@on_select_all || @on_clear}
        class="flex items-center justify-between px-2 py-1.5 border-t border-base-300"
      >
        <span class="text-xs text-base-content/50">
          {MapSet.size(@selected)}/{length(@targets)} selected
        </span>
        <div class="flex items-center gap-1">
          <button
            :if={@on_select_all}
            type="button"
            phx-click={@on_select_all}
            class="btn btn-ghost btn-xs"
          >
            Select All
          </button>
          <button
            :if={@on_clear && MapSet.size(@selected) > 0}
            type="button"
            phx-click={@on_clear}
            class="btn btn-ghost btn-xs"
          >
            Clear
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Commands Mode Components
  # ============================================================================

  @doc """
  Target cell for Commands mode target grid.

  Used by the Commands LiveView and any future commands-related widgets.
  """
  attr :target, :map, required: true
  attr :selected, :boolean, required: true
  attr :view_mode, :string, required: true

  def cmd_target_cell(assigns) do
    status_class = assigns.target.status || :online
    mode = assigns.target.mode || "NOMINAL"

    assigns =
      assigns
      |> assign(:status_class, status_class)
      |> assign(:mode, mode)

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
          <span class="cmd-target-type">{@target.target_type || "Unknown"}</span>
        </div>
      <% else %>
        <span class="cmd-target-name">{@target.name}</span>
      <% end %>
    </div>
    """
  end

  @doc """
  Command list item for Commands mode command browser.
  """
  attr :command, :map, required: true
  attr :selected, :boolean, required: true

  def cmd_command_item(assigns) do
    opcode_hex =
      if assigns.command.opcode do
        "0x" <>
          (assigns.command.opcode
           |> Integer.to_string(16)
           |> String.upcase()
           |> String.pad_leading(4, "0"))
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

  @doc """
  Staging panel for Commands mode, including table and card views.
  """
  attr :staged_commands, :list, required: true
  attr :targets, :list, required: true
  attr :command_definitions, :list, required: true
  attr :expanded, :boolean, required: true
  attr :filter, :string, required: true
  attr :view_mode, :string, required: true

  def staging_panel(assigns) do
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

  @doc """
  Table-row view for a staged command entry.
  """
  attr :staged, :map, required: true
  attr :target_entry, :map, required: true
  attr :cmd_idx, :integer, required: true
  attr :target_idx, :integer, required: true
  attr :targets, :list, required: true
  attr :command_definitions, :list, required: true
  attr :filter, :string, required: true

  def staged_row(assigns) do
    target = Enum.find(assigns.targets, &(&1.id == assigns.target_entry.target_id))
    target_name = if target, do: target.name, else: assigns.target_entry.target_id
    cmd_def = Enum.find(assigns.command_definitions, &(&1.id == assigns.staged.command_id))
    is_hazardous = cmd_def && cmd_def.is_hazardous

    params = assigns.target_entry.params || %{}

    # Build params preview with at most 3 entries
    params_preview =
      params
      |> Enum.take(3)
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(", ")

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
      <td class="cmd-staged-params">
        {@params_preview}{if @has_more_params, do: "...", else: ""}
      </td>
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

  @doc """
  Card view for a staged command entry.
  """
  attr :staged, :map, required: true
  attr :target_entry, :map, required: true
  attr :cmd_idx, :integer, required: true
  attr :target_idx, :integer, required: true
  attr :targets, :list, required: true
  attr :command_definitions, :list, required: true
  attr :filter, :string, required: true

  def staged_card(assigns) do
    target = Enum.find(assigns.targets, &(&1.id == assigns.target_entry.target_id))
    target_name = if target, do: target.name, else: assigns.target_entry.target_id
    cmd_def = Enum.find(assigns.command_definitions, &(&1.id == assigns.staged.command_id))
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

  defp count_staged_items(staged_commands) do
    Enum.reduce(staged_commands, 0, fn staged, acc ->
      acc + length(staged.targets)
    end)
  end

  # ============================================================================
  # Timeline Lanes Components
  # ============================================================================

  attr :targets, :list, required: true
  attr :selected_targets, :any, default: MapSet.new()
  attr :target_search, :string, default: ""
  attr :show_system_events, :boolean, default: true
  attr :system_event_count, :integer, default: 0
  attr :on_toggle, :string, default: "toggle_target_filter"
  attr :on_toggle_system, :string, default: "toggle_system_events"
  attr :on_filter, :string, default: "filter_targets"
  attr :on_select_all, :string, default: "select_all_targets"
  attr :on_clear, :string, default: "clear_target_filter"

  def timeline_lanes_target_picker(assigns) do
    filtered_targets =
      if assigns.target_search == "" do
        assigns.targets
      else
        downcased = String.downcase(assigns.target_search)

        Enum.filter(assigns.targets, fn target ->
          String.contains?(String.downcase(target.name || ""), downcased)
        end)
      end

    # Count includes system if selected
    system_selected = if assigns.show_system_events, do: 1, else: 0
    total_count = length(assigns.targets) + 1

    assigns =
      assigns
      |> assign(:filtered_targets, filtered_targets)
      |> assign(:selected_count, MapSet.size(assigns.selected_targets) + system_selected)
      |> assign(:total_count, total_count)

    ~H"""
    <div class="lanes-target-picker-panel" id="lanes-target-picker" phx-hook=".LanesTargetPicker">
      <div class="lanes-target-picker-header">
        <div class="lanes-picker-title-row">
          <span class="lanes-picker-title">TARGETS</span>
          <span class="lanes-picker-count">
            {@selected_count}/{@total_count}
          </span>
        </div>
        <span class="lanes-picker-available">
          {length(@filtered_targets)} available
        </span>
      </div>

      <div class="lanes-target-search-wrapper">
        <input
          type="text"
          class="lanes-target-search"
          placeholder="Search targets..."
          value={@target_search}
          phx-keyup={@on_filter}
          phx-debounce="150"
        />
      </div>

      <div class="lanes-target-grid">
        <!-- System pseudo-target (always first) -->
        <div
          class={["lanes-target-cell", "system-target", @show_system_events && "selected"]}
          phx-click={@on_toggle_system}
          title={"System events (#{@system_event_count} events)"}
        >
          <span class="lanes-target-name">◆ SYSTEM</span>
        </div>

        <.lanes_target_cell
          :for={target <- @filtered_targets}
          target={target}
          selected={MapSet.member?(@selected_targets, target.id)}
          on_toggle={@on_toggle}
        />
      </div>

      <div class="lanes-picker-actions">
        <button type="button" class="lanes-picker-action" phx-click={@on_clear}>
          Clear
        </button>
        <button type="button" class="lanes-picker-action" phx-click={@on_select_all}>
          All
        </button>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".LanesTargetPicker">
      export default {
        mounted() {
          this.applySavedWidth()
        },

        updated() {
          this.applySavedWidth()
        },

        applySavedWidth() {
          const savedWidth = localStorage.getItem('lanes-picker-width')
          if (savedWidth) {
            this.el.style.flex = `0 0 ${savedWidth}`
          }
        }
      }
    </script>
    """
  end

  @doc """
  Renders a vertical resize handle between Target Selector and Target Lanes panels.
  """
  def lanes_resize_handle(assigns) do
    ~H"""
    <div class="lanes-resize-handle" id="lanes-resize" phx-hook=".LanesPickerResize"></div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".LanesPickerResize">
      export default {
        mounted() {
          this.isDragging = false
          this.startX = 0
          this.startWidth = 0
          this.pickerPanel = document.getElementById('lanes-target-picker')
          this._startDrag = (event) => this.startDrag(event)
          this._onDrag = (event) => this.onDrag(event)
          this._endDrag = () => this.endDrag()
          this.el.addEventListener('mousedown', this._startDrag)
          document.addEventListener('mousemove', this._onDrag)
          document.addEventListener('mouseup', this._endDrag)

          // Load saved width from localStorage
          const savedWidth = localStorage.getItem('lanes-picker-width')
          if (savedWidth && this.pickerPanel) {
            this.pickerPanel.style.flex = `0 0 ${savedWidth}`
          }
        },

        updated() {
          // Re-query the picker panel in case it was replaced
          this.pickerPanel = document.getElementById('lanes-target-picker')
          // Reapply saved width after LiveView DOM patches
          const savedWidth = localStorage.getItem('lanes-picker-width')
          if (savedWidth && this.pickerPanel) {
            this.pickerPanel.style.flex = `0 0 ${savedWidth}`
          }
        },

        startDrag(event) {
          if (!this.pickerPanel) {
            this.pickerPanel = document.getElementById('lanes-target-picker')
          }
          if (!this.pickerPanel) return
          this.isDragging = true
          this.startX = event.clientX
          this.startWidth = this.pickerPanel.offsetWidth
          document.body.style.cursor = 'col-resize'
          document.body.style.userSelect = 'none'
          this.el.classList.add('dragging')
        },

        onDrag(event) {
          if (!this.isDragging || !this.pickerPanel) return
          const diff = event.clientX - this.startX
          const newWidth = Math.max(150, Math.min(400, this.startWidth + diff))
          this.pickerPanel.style.flex = `0 0 ${newWidth}px`
          // Save during drag so it survives page refresh mid-resize
          localStorage.setItem('lanes-picker-width', `${newWidth}px`)
        },

        endDrag() {
          if (!this.isDragging) return
          this.isDragging = false
          document.body.style.cursor = ''
          document.body.style.userSelect = ''
          this.el.classList.remove('dragging')
          if (this.pickerPanel) {
            localStorage.setItem('lanes-picker-width', `${this.pickerPanel.offsetWidth}px`)
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

  attr :lanes, :list, required: true
  attr :time_markers, :list, required: true
  attr :scrubber_position, :any, required: true
  attr :time_range, :string, required: true
  attr :start_time, :any, required: true
  attr :total_ms, :integer, required: true
  attr :fleet_events, :list, default: []
  attr :selected_target_count, :integer, default: 0
  attr :show_system_events, :boolean, default: true
  attr :system_events, :list, default: []
  attr :on_remove_lane, :string, default: "toggle_target_filter"
  attr :on_toggle_system, :string, default: "toggle_system_events"

  def timeline_lanes_panel(assigns) do
    assigns =
      assigns
      |> assign_new(:lanes, fn -> [] end)

    ~H"""
    <div class="lanes-main-panel">
      <div
        class="lanes-hud-panel"
        id="lanes-hud-panel"
        phx-hook=".LanesScrubber"
        data-time-range={@time_range}
        data-scrubber-position={@scrubber_position}
        data-now-position={@scrubber_position}
      >
        <div class="lanes-panel-header">
          <div class="lanes-panel-title">
            <span class="lanes-panel-label">TARGET LANES</span>
            <span class="lanes-panel-count">
              {@selected_target_count} TARGETS
            </span>
          </div>
        </div>

        <div class="timeline-lanes-axis">
          <div class="lanes-axis-label">TIME</div>
          <div class="lanes-axis-track">
            <div
              :for={marker <- @time_markers}
              class="lanes-time-marker"
              style={"left: #{marker.position}%"}
            >
              <span class="lanes-time-label">{marker.label}</span>
            </div>
            <div class="lanes-view-marker" style={"left: #{@scrubber_position}%"}>
              <div class="lanes-now-line"></div>
              <span class="lanes-now-label">NOW</span>
            </div>
          </div>
        </div>

        <div class="timeline-lanes-body">
          <div
            class="lanes-scrub-line"
            style={"left: calc(120px + (100% - 120px) * #{@scrubber_position} / 100)"}
          >
          </div>

          <div class="timeline-lanes-container">
            <%= if Enum.empty?(@lanes) and not @show_system_events do %>
              <div class="timeline-empty-state">
                Select targets from the panel on the left to show lanes.
              </div>
            <% else %>
              <!-- System lane (shown first when enabled) -->
              <.system_lane
                :if={@show_system_events}
                events={@system_events}
                start_time={@start_time}
                total_ms={@total_ms}
                on_toggle={@on_toggle_system}
              />

              <.timeline_lane
                :for={lane <- @lanes}
                target={lane.target}
                events={lane.events}
                start_time={@start_time}
                total_ms={@total_ms}
                on_remove={@on_remove_lane}
              />
            <% end %>
          </div>

          <div class="timeline-lanes-summary">
            <div class="lane-header">
              <span class="lane-target-name">FLEET</span>
            </div>
            <div class="lane-track lane-summary-track">
              <.fleet_sparkline events={@fleet_events} start_time={@start_time} total_ms={@total_ms} />
            </div>
          </div>
        </div>

        <div class="lanes-hud-corners"></div>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".LanesScrubber">
      export default {
        mounted() {
          this.isDragging = false
          this.startX = 0
          this.startPosition = 80
          this.currentPosition = this.readDatasetPosition('scrubberPosition', 80)
          this.scrubLine = null
          this.nowMarker = null
          this.axisTrack = null
          this.lanesBody = this.el.querySelector('.timeline-lanes-body')
          this.activityPanel = document.getElementById('lanes-activity-panel')
          this.nowBaseline = this.readDatasetPosition('nowPosition', 80)
          this.panCooldown = false
          this.autoPanInterval = null
          this.autoPanDirection = null
          this.autoPanIntervalDuration = 250
          this.autoPanIntensity = 1
          this.autoPanThreshold = 5
          this._scrubListener = (e) => this.startDrag(e)
          this._markerListener = (e) => this.startDrag(e)
          this._axisClick = (e) => this.jumpToPosition(e)

          this.eventElements = []
          this.gatherEventElements()
          this.updateScrubberPosition(this.currentPosition)

          this.refreshInteractiveElements()

          this._onDrag = (e) => this.onDrag(e)
          this._endDrag = () => this.endDrag()
          this._onWheel = (e) => this.onWheel(e)
          document.addEventListener('mousemove', this._onDrag)
          document.addEventListener('mouseup', this._endDrag)
          if (this.lanesBody) {
            this.lanesBody.addEventListener('wheel', this._onWheel, { passive: false })
          }

          this.handleEvent('scrubber_reset', ({ position }) => {
            const target = typeof position === 'number' ? position : this.nowBaseline
            this.currentPosition = target
            this.updateScrubberPosition(target)
          })
        },

        gatherEventElements() {
          this.eventElements = []
          const tracks = this.el.querySelectorAll('.lane-track')
          tracks.forEach(track => {
            const events = track.querySelectorAll('.lane-event')
            events.forEach(el => {
              const left = parseFloat(el.style.left)
              if (!isNaN(left)) {
                this.eventElements.push({
                  element: el,
                  position: left,
                  id: el.dataset.eventId,
                  title: el.getAttribute('title')
                })
              }
            })
          })
          this.eventElements.sort((a, b) => a.position - b.position)
        },

        updated() {
          this.refreshInteractiveElements()
          this.nowBaseline = this.readDatasetPosition('nowPosition', this.nowBaseline)
          this.gatherEventElements()
          this.updateScrubberPosition(this.currentPosition)
          if (this.isDragging) {
            this.showEventsNearScrubber(this.currentPosition)
          }
        },

        startDrag(e) {
          e.preventDefault()
          this.isDragging = true
          this.startX = e.clientX
          this.startPosition = this.currentPosition
          document.body.style.cursor = 'ew-resize'
          document.body.style.userSelect = 'none'
          this.el.classList.add('is-scrubbing')
          this.pushEvent('lanes_scrub_state', { dragging: true })

          if (this.activityPanel && this.activityPanel.classList.contains('minimized')) {
            this.activityPanel.classList.remove('minimized')
            this.activityPanel.classList.add('expanded')
            const hint = this.activityPanel.querySelector('.lanes-activity-hint')
            if (hint) hint.textContent = 'Click to collapse'
          }
        },

        onDrag(e) {
          if (!this.isDragging) return

          const container = this.lanesBody || this.el
          const rect = container.getBoundingClientRect()
          const labelWidth = 120
          const trackWidth = rect.width - labelWidth
          const relativeX = e.clientX - rect.left - labelWidth

          let newPosition = (relativeX / trackWidth) * 100
          newPosition = Math.max(0, Math.min(100, newPosition))

          this.currentPosition = newPosition
          this.updateScrubberPosition(newPosition)
          this.showEventsNearScrubber(newPosition)
          this.updateAutoPan()
        },

        onWheel(e) {
          const horizontal = Math.abs(e.deltaX) > Math.abs(e.deltaY)
          const delta = horizontal ? e.deltaX : e.deltaY
          if (!delta) return

          e.preventDefault()

          // Accumulate delta for smoother continuous scrolling
          this.accumulatedDelta = (this.accumulatedDelta || 0) + delta

          // Use requestAnimationFrame for smooth updates, with a minimum threshold
          if (this.panCooldown) return
          this.panCooldown = true

          requestAnimationFrame(() => {
            const totalDelta = this.accumulatedDelta
            this.accumulatedDelta = 0

            if (Math.abs(totalDelta) < 5) {
              this.panCooldown = false
              return
            }

            const direction = totalDelta > 0 ? 'forward' : 'back'
            // More aggressive intensity scaling for faster scrolling
            // Normalize by 50 instead of 160, and allow higher max intensity
            const intensity = this.clampIntensity(Math.abs(totalDelta) / 50, 0.5, 8)
            this.pushEvent('pan_lanes', { direction, intensity })

            // Shorter cooldown (50ms) for more responsive continuous scrolling
            setTimeout(() => {
              this.panCooldown = false
            }, 50)
          })
        },

        jumpToPosition(e) {
          if (e.target.closest('.lanes-time-marker') || e.target.closest('.lanes-view-marker')) return

          const rect = this.axisTrack.getBoundingClientRect()
          const relativeX = e.clientX - rect.left
          let newPosition = (relativeX / rect.width) * 100
          newPosition = Math.max(0, Math.min(100, newPosition))

          this.currentPosition = newPosition
          this.updateScrubberPosition(newPosition)
          this.showEventsNearScrubber(newPosition)
        },

        updateScrubberPosition(position) {
          if (this.scrubLine) {
            this.scrubLine.style.left = `calc(120px + (100% - 120px) * ${position} / 100)`
          }
          if (this.nowMarker) {
            this.nowMarker.style.left = `${position}%`
            const nowLabel = this.nowMarker.querySelector('.lanes-now-label')
            if (nowLabel) {
              const offsetFromNow = position - this.nowBaseline
              if (Math.abs(offsetFromNow) < 1) {
                nowLabel.textContent = 'NOW'
                nowLabel.classList.remove('offset')
              } else {
                const timeRange = parseFloat(this.el.dataset.timeRange || '1')
                const totalMinutes = timeRange * 60 * 2
                const offsetMinutes = (offsetFromNow / 100) * totalMinutes
                const absMinutes = Math.abs(Math.round(offsetMinutes))
                if (offsetMinutes < 0) {
                  nowLabel.textContent = `-${absMinutes}m`
                } else {
                  nowLabel.textContent = `+${absMinutes}m`
                }
                nowLabel.classList.add('offset')
              }
            }
          }

          const returnBtn = this.el.querySelector('.lanes-return-now-btn')
          if (returnBtn) {
            const isAtNow = Math.abs(position - this.nowBaseline) < 1
            returnBtn.style.opacity = isAtNow ? '0.3' : '1'
            returnBtn.style.pointerEvents = isAtNow ? 'none' : 'auto'
          }
        },

        showEventsNearScrubber(position) {
          if (!this.activityPanel) return

          const body = this.activityPanel.querySelector('.lanes-activity-body')
          if (!body) return

          const tolerance = 2
          const nearbyEvents = this.eventElements.filter(evt =>
            Math.abs(evt.position - position) <= tolerance
          )

          if (nearbyEvents.length === 0) {
            body.innerHTML = `
              <div class="lanes-activity-empty">
                <span class="empty-icon">⊙</span>
                <span class="empty-text">Drag scrubber over events to see details</span>
              </div>
            `
            return
          }

          const cards = nearbyEvents.map(evt => {
            const typeClass = Array.from(evt.element.classList).find(c => c.startsWith('lane-event-'))
            const eventType = typeClass ? typeClass.replace('lane-event-', '') : 'event'
            const title = evt.title || 'Event'

            return `
              <div class="activity-card type-${eventType}" data-event-id="${evt.id}">
                <div class="activity-card-header">
                  <span class="activity-card-type">${eventType.toUpperCase()}</span>
                </div>
                <div class="activity-card-title">${this.escapeHtml(title)}</div>
              </div>
            `
          }).join('')

          body.innerHTML = `
            <div class="lanes-activity-grid">
              ${cards}
            </div>
          `

          this.eventElements.forEach(evt => {
            evt.element.classList.toggle('highlighted', nearbyEvents.includes(evt))
          })
        },

        escapeHtml(text) {
          const div = document.createElement('div')
          div.textContent = text
          return div.innerHTML
        },

        endDrag() {
          if (!this.isDragging) return
          this.isDragging = false
          document.body.style.cursor = ''
          document.body.style.userSelect = ''
          this.el.classList.remove('is-scrubbing')
          this.pushEvent('lanes_scrub_state', { dragging: false })
          this.stopAutoPan()

          this.eventElements.forEach(evt => {
            evt.element.classList.remove('highlighted')
          })
        },

        destroyed() {
          document.removeEventListener('mousemove', this._onDrag)
          document.removeEventListener('mouseup', this._endDrag)
          if (this.lanesBody && this._onWheel) {
            this.lanesBody.removeEventListener('wheel', this._onWheel)
          }
          this.detachInteractiveElements()
          this.stopAutoPan()
          this.pushEvent('lanes_scrub_state', { dragging: false })
        },

        readDatasetPosition(key, fallback) {
          const value = parseFloat(this.el.dataset[key] || `${fallback}`)
          return Number.isNaN(value) ? fallback : value
        },

        clampIntensity(value, min = 0.2, max = 10) {
          const num = Number(value)
          if (Number.isNaN(num)) return min
          return Math.max(min, Math.min(max, num))
        },

        refreshInteractiveElements() {
          const newScrubLine = this.el.querySelector('.lanes-scrub-line')
          if (newScrubLine !== this.scrubLine) {
            if (this.scrubLine && this._scrubListener) {
              this.scrubLine.removeEventListener('mousedown', this._scrubListener)
            }
            this.scrubLine = newScrubLine
            if (this.scrubLine && this._scrubListener) {
              this.scrubLine.addEventListener('mousedown', this._scrubListener)
            }
          }

          const newNowMarker = this.el.querySelector('.lanes-view-marker')
          if (newNowMarker !== this.nowMarker) {
            if (this.nowMarker && this._markerListener) {
              this.nowMarker.removeEventListener('mousedown', this._markerListener)
            }
            this.nowMarker = newNowMarker
            if (this.nowMarker && this._markerListener) {
              this.nowMarker.addEventListener('mousedown', this._markerListener)
            }
          }

          const newAxisTrack = this.el.querySelector('.lanes-axis-track')
          if (newAxisTrack !== this.axisTrack) {
            if (this.axisTrack && this._axisClick) {
              this.axisTrack.removeEventListener('click', this._axisClick)
            }
            this.axisTrack = newAxisTrack
            if (this.axisTrack && this._axisClick) {
              this.axisTrack.addEventListener('click', this._axisClick)
            }
          }
        },

        detachInteractiveElements() {
          if (this.scrubLine && this._scrubListener) {
            this.scrubLine.removeEventListener('mousedown', this._scrubListener)
          }
          if (this.nowMarker && this._markerListener) {
            this.nowMarker.removeEventListener('mousedown', this._markerListener)
          }
          if (this.axisTrack && this._axisClick) {
            this.axisTrack.removeEventListener('click', this._axisClick)
          }
          this.scrubLine = null
          this.nowMarker = null
          this.axisTrack = null
        },

        updateAutoPan() {
          if (!this.isDragging) {
            this.stopAutoPan()
            return
          }

          if (this.currentPosition <= this.autoPanThreshold) {
            const closeness =
              (this.autoPanThreshold - this.currentPosition) / this.autoPanThreshold
            this.startAutoPan('back', this.clampIntensity(0.6 + closeness * 1.4, 0.4, 2.5))
          } else if (this.currentPosition >= 100 - this.autoPanThreshold) {
            const closeness =
              (this.currentPosition - (100 - this.autoPanThreshold)) / this.autoPanThreshold
            this.startAutoPan('forward', this.clampIntensity(0.6 + closeness * 1.4, 0.4, 2.5))
          } else {
            this.stopAutoPan()
          }
        },

        startAutoPan(direction, intensity = 1) {
          const normalized = this.clampIntensity(intensity)

          if (this.autoPanDirection === direction && this.autoPanInterval) {
            this.autoPanIntensity = normalized
            return
          }

          this.stopAutoPan()
          this.autoPanDirection = direction
          this.autoPanIntensity = normalized

          const tick = () => {
            if (!this.autoPanDirection) return
            this.pushEvent('pan_lanes', {
              direction: this.autoPanDirection,
              intensity: this.autoPanIntensity
            })
          }

          tick()
          this.autoPanInterval = setInterval(tick, this.autoPanIntervalDuration)
        },

        stopAutoPan() {
          if (this.autoPanInterval) {
            clearInterval(this.autoPanInterval)
            this.autoPanInterval = null
          }
          this.autoPanDirection = null
          this.autoPanIntensity = 1
        }
      }
    </script>
    """
  end

  attr :on_jump_to_now, :string, default: "jump_to_now"

  def timeline_lanes_activity_panel(assigns) do
    ~H"""
    <div class="lanes-activity-panel minimized" id="lanes-activity-panel" phx-hook=".LanesActivity">
      <div class="lanes-activity-resize-handle"></div>
      <div class="lanes-activity-header">
        <div class="lanes-activity-title">
          <span class="lanes-activity-label">FLEET ACTIVITY</span>
          <span class="lanes-activity-hint">Click to expand</span>
        </div>
        <div class="lanes-activity-actions">
          <button type="button" class="lanes-return-now-btn" phx-click={@on_jump_to_now}>
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <span>NOW</span>
          </button>
        </div>
      </div>
      <div class="lanes-activity-body">
        <div class="lanes-activity-empty">
          <span class="empty-icon">⊙</span>
          <span class="empty-text">Click an event or drag the timeline to see activity</span>
        </div>
      </div>
      <div class="lanes-activity-corners"></div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".LanesActivity">
      export default {
        mounted() {
          this.header = this.el.querySelector('.lanes-activity-header')
          this.body = this.el.querySelector('.lanes-activity-body')
          this.hint = this.el.querySelector('.lanes-activity-hint')
          this.resizeHandle = this.el.querySelector('.lanes-activity-resize-handle')

          // Load saved state from localStorage
          const savedExpanded = localStorage.getItem('lanes-activity-expanded')
          const savedHeight = localStorage.getItem('lanes-activity-height')

          this.expanded = savedExpanded === 'true'

          // Apply saved state
          if (savedHeight) {
            this.el.style.setProperty('--activity-height', savedHeight)
          }

          if (this.expanded) {
            this.el.classList.remove('minimized')
            this.el.classList.add('expanded')
            if (this.hint) {
              this.hint.textContent = 'Click to collapse'
            }
          }

          this._onHeaderClick = (event) => {
            if (event.target.closest('.lanes-return-now-btn')) return
            this.togglePanel()
          }

          this._onLaneEventClick = (event) => {
            const eventEl = event.target.closest('.lane-event')
            if (eventEl) {
              const eventId = eventEl.dataset.eventId
              if (eventId) {
                this.showEventDetail(eventId, eventEl)
              }
            }
          }

          if (this.header) {
            this.header.addEventListener('click', this._onHeaderClick)
          }

          document.addEventListener('click', this._onLaneEventClick)

          if (this.resizeHandle) {
            this.setupResize()
          }
        },

        updated() {
          // Reapply saved state after LiveView DOM patches
          // LiveView may reset classes to server-side defaults
          if (this.expanded) {
            this.el.classList.remove('minimized')
            this.el.classList.add('expanded')
            const savedHeight = localStorage.getItem('lanes-activity-height')
            if (savedHeight) {
              this.el.style.setProperty('--activity-height', savedHeight)
            }
          }
        },

        togglePanel() {
          this.expanded = !this.expanded
          this.el.classList.toggle('expanded', this.expanded)
          this.el.classList.toggle('minimized', !this.expanded)

          if (this.hint) {
            this.hint.textContent = this.expanded ? 'Click to collapse' : 'Click to expand'
          }

          // Save expanded state to localStorage
          localStorage.setItem('lanes-activity-expanded', this.expanded.toString())
        },

        showEventDetail(eventId, eventEl) {
          if (!this.expanded) {
            this.togglePanel()
          }

          const detail = document.createElement('div')
          detail.className = 'lanes-activity-card'
          detail.innerHTML = `
            <div class="activity-card-header">
              <span class="activity-card-type">${eventEl?.classList.contains('lane-event-alarm') ? 'ALARM' : 'EVENT'}</span>
              <button class="activity-close" type="button" aria-label="Close">
                &times;
              </button>
            </div>
            <div class="activity-card-content">
              <div class="activity-card-title">Event ${eventId}</div>
              <div class="activity-card-meta">Details not loaded</div>
            </div>
          `

          const closeBtn = detail.querySelector('.activity-close')
          if (closeBtn) {
            closeBtn.addEventListener('click', () => detail.remove())
          }

          this.body.innerHTML = ''
          this.body.appendChild(detail)
        },

        gatherEventElements() {
          this.eventElements = []
          const tracks = document.querySelectorAll('.lane-track')
          tracks.forEach(track => {
            const events = track.querySelectorAll('.lane-event')
            events.forEach(el => {
              const left = parseFloat(el.style.left)
              if (!isNaN(left)) {
                this.eventElements.push({
                  element: el,
                  position: left,
                  id: el.dataset.eventId,
                  title: el.getAttribute('title')
                })
              }
            })
          })
        },

        setupResize() {
          this.isResizing = false
          this.startY = 0
          this.startHeight = 0

          this._onResizeStart = (event) => {
            this.isResizing = true
            this.startY = event.clientY
            this.startHeight = this.el.offsetHeight
            document.body.style.cursor = 'row-resize'
            document.body.style.userSelect = 'none'
            this.el.classList.add('resizing')

            if (this.el.classList.contains('minimized')) {
              this.el.classList.remove('minimized')
              this.el.classList.add('expanded')
              this.expanded = true
              localStorage.setItem('lanes-activity-expanded', 'true')
              if (this.hint) {
                this.hint.textContent = 'Click to collapse'
              }
            }
          }

          this._onResizeMove = (event) => {
            if (!this.isResizing) return
            const diff = this.startY - event.clientY
            // Allow dragging down to 60px to trigger minimize
            const newHeight = Math.max(60, Math.min(400, this.startHeight + diff))
            this.el.style.setProperty('--activity-height', `${newHeight}px`)
            // Save during drag so it survives page refresh mid-resize
            if (newHeight >= 80) {
              localStorage.setItem('lanes-activity-height', `${newHeight}px`)
            }
          }

          this._onResizeEnd = () => {
            if (!this.isResizing) return
            this.isResizing = false
            document.body.style.cursor = ''
            document.body.style.userSelect = ''
            this.el.classList.remove('resizing')

            // Check if dragged small enough to minimize
            const heightStr = getComputedStyle(this.el).getPropertyValue('--activity-height')
            const height = parseInt(heightStr, 10)

            if (height < 80) {
              // Minimize the panel
              this.expanded = false
              this.el.classList.remove('expanded')
              this.el.classList.add('minimized')
              localStorage.setItem('lanes-activity-expanded', 'false')
              if (this.hint) {
                this.hint.textContent = 'Click to expand'
              }
            } else {
              // Save height to localStorage
              localStorage.setItem('lanes-activity-height', `${height}px`)
            }
          }

          this.resizeHandle.addEventListener('mousedown', this._onResizeStart)
          document.addEventListener('mousemove', this._onResizeMove)
          document.addEventListener('mouseup', this._onResizeEnd)
        },

        destroyed() {
          if (this.header && this._onHeaderClick) {
            this.header.removeEventListener('click', this._onHeaderClick)
          }

          if (this._onLaneEventClick) {
            document.removeEventListener('click', this._onLaneEventClick)
          }

          if (this.resizeHandle && this._onResizeStart) {
            this.resizeHandle.removeEventListener('mousedown', this._onResizeStart)
          }
          if (this._onResizeMove) {
            document.removeEventListener('mousemove', this._onResizeMove)
          }
          if (this._onResizeEnd) {
            document.removeEventListener('mouseup', this._onResizeEnd)
          }
        }
      }
    </script>
    """
  end

  attr :target, :map, required: true
  attr :selected, :boolean, required: true
  attr :on_toggle, :string, default: "toggle_target_filter"

  def lanes_target_cell(assigns) do
    status_class =
      case assigns.target.status do
        s when s in [:nominal, :active, :online] -> "status-online"
        s when s in [:degraded, :warning, :standby] -> "status-standby"
        _ -> "status-offline"
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <div
      class={["lanes-target-cell", @status_class, @selected && "selected"]}
      phx-click={@on_toggle}
      phx-value-id={@target.id}
    >
      <span class="lanes-target-name">{@target.name}</span>
    </div>
    """
  end

  attr :events, :list, required: true
  attr :start_time, :any, required: true
  attr :total_ms, :integer, required: true
  attr :on_toggle, :string, default: "toggle_system_events"

  def system_lane(assigns) do
    ~H"""
    <div class="timeline-lane system-lane" data-target-id="__SYSTEM__">
      <div class="lane-header">
        <span class="lane-target-name">◆ SYSTEM</span>
        <button
          type="button"
          class="lane-unpin"
          phx-click={@on_toggle}
          title="Hide system events"
        >
          ×
        </button>
      </div>
      <div class="lane-track">
        <.lane_event
          :for={event <- @events}
          event={event}
          start_time={@start_time}
          total_ms={@total_ms}
        />
      </div>
    </div>
    """
  end

  attr :target, :map, required: true
  attr :events, :list, required: true
  attr :start_time, :any, required: true
  attr :total_ms, :integer, required: true
  attr :on_remove, :string, default: "toggle_target_filter"

  def timeline_lane(assigns) do
    ~H"""
    <div class="timeline-lane" data-target-id={@target.id}>
      <div class="lane-header">
        <span class="lane-target-name">{@target.name || @target.identifier}</span>
        <button
          type="button"
          class="lane-unpin"
          phx-click={@on_remove}
          phx-value-id={@target.id}
          title="Remove lane"
        >
          ×
        </button>
      </div>
      <div class="lane-track">
        <.lane_event
          :for={event <- @events}
          event={event}
          start_time={@start_time}
          total_ms={@total_ms}
        />
      </div>
    </div>
    """
  end

  attr :event, :map, required: true
  attr :start_time, :any, required: true
  attr :total_ms, :integer, required: true

  def lane_event(assigns) do
    event_time = assigns.event.timestamp
    position = calculate_position(event_time, assigns.start_time, assigns.total_ms)
    event_type = assigns.event.type || :command
    type_class = "lane-event-#{event_type}"

    status_class =
      if assigns.event.status in [:error, :failed], do: "has-error", else: ""

    future_class =
      if DateTime.compare(event_time, DateTime.utc_now()) == :gt, do: "is-future", else: ""

    assigns =
      assigns
      |> assign(:position, position)
      |> assign(:type_class, type_class)
      |> assign(:status_class, status_class)
      |> assign(:future_class, future_class)

    ~H"""
    <div
      class={["lane-event", @type_class, @status_class, @future_class]}
      style={"left: #{@position}%"}
      data-event-id={@event.id}
      title={"#{event_title(@event)} - #{format_event_time(@event.timestamp)}"}
    >
      {lane_event_symbol(@event.type || :command)}
    </div>
    """
  end

  attr :events, :list, required: true
  attr :start_time, :any, required: true
  attr :total_ms, :integer, required: true

  def fleet_sparkline(assigns) do
    bucket_count = 50
    bucket_ms = assigns.total_ms / bucket_count

    buckets =
      Enum.reduce(assigns.events, List.duplicate(0, bucket_count), fn event, acc ->
        event_time = event.timestamp
        diff_ms = DateTime.diff(event_time, assigns.start_time, :millisecond)
        bucket_index = trunc(diff_ms / bucket_ms)

        if bucket_index >= 0 and bucket_index < bucket_count do
          List.update_at(acc, bucket_index, &(&1 + 1))
        else
          acc
        end
      end)

    max_count = Enum.max(buckets, fn -> 1 end) |> max(1)

    assigns =
      assigns
      |> assign(:buckets, buckets)
      |> assign(:max_count, max_count)
      |> assign(:bucket_count, bucket_count)

    ~H"""
    <div class="sparkline-container">
      <div
        :for={{count, idx} <- Enum.with_index(@buckets)}
        class={["sparkline-bar", count > 0 && "has-activity"]}
        style={"left: #{idx / @bucket_count * 100}%; width: #{100 / @bucket_count}%; height: #{count / @max_count * 100}%"}
      >
      </div>
    </div>
    """
  end

  # Shared formatting helpers for timeline views/components
  def event_type_label(:command), do: "CMD"
  def event_type_label(:alarm), do: "ALM"
  def event_type_label(:procedure), do: "PRC"
  def event_type_label(:automation), do: "AUT"
  def event_type_label(other), do: other |> to_string() |> String.upcase() |> String.slice(0, 3)

  def event_title(%{title: title}) when is_binary(title), do: title
  def event_title(%{command_name: name}) when is_binary(name), do: name
  def event_title(%{message: msg}) when is_binary(msg), do: String.slice(msg, 0, 50)
  def event_title(%{event_type: type}), do: "#{type} event"
  def event_title(_), do: "Event"

  def event_source(%{target_name: name}) when is_binary(name), do: name
  def event_source(%{target: %{name: name}}) when is_binary(name), do: name
  def event_source(_), do: "System"

  def format_event_time(nil), do: "—"

  def format_event_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  def format_event_time(_), do: "—"

  def timeline_relative_time(nil), do: ""

  def timeline_relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 0 -> "in #{abs(diff)}s"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  def timeline_relative_time(_), do: ""

  defp lane_event_symbol(:command), do: "·"
  defp lane_event_symbol(:alarm), do: "●"
  defp lane_event_symbol(:procedure), do: "▲"
  defp lane_event_symbol(:automation), do: "◆"
  defp lane_event_symbol(_), do: "·"

  defp calculate_position(%DateTime{} = event_time, start_time, total_ms) do
    diff_ms = DateTime.diff(event_time, start_time, :millisecond)
    diff_ms / total_ms * 100
  end

  defp calculate_position(_, _, _), do: 0

  @doc """
  Renders a single target cell in the target selector grid.
  """
  attr :target, :map, required: true
  attr :selected, :boolean, default: false
  attr :view, :atom, default: :compact
  attr :on_select, :string, required: true

  def target_cell(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@on_select}
      phx-value-id={@target.id}
      class={[
        "target-cell transition-all",
        @view == :compact && "p-1.5 text-center rounded",
        @view == :detailed && "p-2 text-left rounded flex items-center gap-2",
        @selected && "bg-primary/20 border border-primary text-primary",
        !@selected && "bg-base-300/50 border border-transparent hover:border-base-content/20"
      ]}
    >
      <span
        :if={@view == :detailed}
        class={[
          "w-2 h-2 rounded-full flex-shrink-0",
          target_health_color(@target)
        ]}
      >
      </span>
      <span class={[
        "font-mono truncate",
        @view == :compact && "text-[0.65rem]",
        @view == :detailed && "text-xs"
      ]}>
        {@target.name}
      </span>
      <span
        :if={@view == :detailed}
        class="ml-auto text-[0.6rem] text-base-content/40 font-mono"
      >
        {target_status_label(@target)}
      </span>
    </button>
    """
  end

  defp target_health_color(%{health_status: :healthy}), do: "bg-success"
  defp target_health_color(%{health_status: :degraded}), do: "bg-warning"
  defp target_health_color(%{health_status: :critical}), do: "bg-error"
  defp target_health_color(_), do: "bg-base-content/30"

  defp target_status_label(%{health_status: status}) when is_atom(status) do
    status |> to_string() |> String.upcase()
  end

  defp target_status_label(_), do: "UNKNOWN"

  # ============================================================================
  # Mode Header Components
  # ============================================================================

  @doc """
  Renders a mode header with title, view tabs, and optional actions.

  ## Attributes
    * `:title` - Mode title (e.g., "Commands", "Queue")
    * `:tabs` - List of tab tuples: [{:label, :action, :active?}]
    * `:actions` - Slot for action buttons

  ## Examples

      <.mode_header title="Queue">
        <:tabs>
          <.mode_tab label="Overview" action={:overview} active={@live_action == :overview} />
          <.mode_tab label="Table" action={:table} active={@live_action == :table} />
        </:tabs>
        <:actions>
          <button class="btn btn-sm btn-primary">Pause All</button>
        </:actions>
      </.mode_header>
  """
  attr :title, :string, required: true
  attr :class, :string, default: ""

  slot :tabs
  slot :actions

  def mode_header(assigns) do
    ~H"""
    <header class={[
      "mode-header flex items-center justify-between px-4 py-2 border-b border-base-300 bg-base-200/50",
      @class
    ]}>
      <div class="flex items-center gap-4">
        <h1 class="text-sm font-semibold text-base-content tracking-wide uppercase">
          {@title}
        </h1>
        <div :if={@tabs != []} class="flex items-center gap-1">
          {render_slot(@tabs)}
        </div>
      </div>
      <div :if={@actions != []} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc """
  Renders a tab button for mode headers.
  """
  attr :label, :string, required: true
  attr :to, :string, default: nil
  attr :action, :string, default: nil
  attr :active, :boolean, default: false

  def mode_tab(assigns) do
    ~H"""
    <.link
      :if={@to}
      navigate={@to}
      class={[
        "px-3 py-1 text-xs font-medium rounded transition-colors",
        @active && "bg-primary text-primary-content",
        !@active && "text-base-content/60 hover:text-base-content hover:bg-base-300"
      ]}
    >
      {@label}
    </.link>
    <button
      :if={@action && !@to}
      type="button"
      phx-click={@action}
      class={[
        "px-3 py-1 text-xs font-medium rounded transition-colors",
        @active && "bg-primary text-primary-content",
        !@active && "text-base-content/60 hover:text-base-content hover:bg-base-300"
      ]}
    >
      {@label}
    </button>
    """
  end

  # ============================================================================
  # Status & Severity Badges
  # ============================================================================

  @doc """
  Renders a severity badge (Critical, Warning, Info).
  """
  attr :severity, :atom, required: true
  attr :count, :integer, default: nil
  attr :class, :string, default: ""

  def severity_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium",
      severity_badge_class(@severity),
      @class
    ]}>
      <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
      <span :if={@count} class="font-mono">{@count}</span>
      <span class="uppercase text-[0.65rem]">{severity_label(@severity)}</span>
    </span>
    """
  end

  defp severity_badge_class(:critical), do: "bg-error/20 text-error"
  defp severity_badge_class(:warning), do: "bg-warning/20 text-warning"
  defp severity_badge_class(:info), do: "bg-info/20 text-info"
  defp severity_badge_class(_), do: "bg-base-300 text-base-content/60"

  defp severity_label(:critical), do: "CRIT"
  defp severity_label(:warning), do: "WARN"
  defp severity_label(:info), do: "INFO"
  defp severity_label(other), do: to_string(other) |> String.upcase()

  # Note: status_badge is provided by CadenceWeb.CoreComponents

  # ============================================================================
  # Time Display Components
  # ============================================================================

  @doc """
  Renders a timestamp with both relative and absolute time.
  """
  attr :time, :any, required: true
  attr :class, :string, default: ""

  def timestamp_display(assigns) do
    ~H"""
    <span class={["timestamp-display", @class]} title={format_absolute_time(@time)}>
      <span class="text-xs text-base-content/60">{format_relative_time(@time)}</span>
    </span>
    """
  end

  defp format_relative_time(nil), do: "—"

  defp format_relative_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> format_relative_time(dt)
      _ -> time
    end
  end

  defp format_relative_time(%DateTime{} = time) do
    diff = DateTime.diff(DateTime.utc_now(), time, :second)

    cond do
      diff < 0 -> "in #{format_duration(-diff)}"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp format_relative_time(_), do: "—"

  defp format_absolute_time(nil), do: ""

  defp format_absolute_time(%DateTime{} = time) do
    Calendar.strftime(time, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_absolute_time(_), do: ""

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp format_duration(seconds), do: "#{div(seconds, 3600)}h"

  # ============================================================================
  # Empty State Component
  # ============================================================================

  @doc """
  Renders an empty state placeholder.
  """
  attr :icon, :string, default: "inbox"
  attr :title, :string, required: true
  attr :description, :string, default: nil

  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <div class="w-12 h-12 mb-4 text-base-content/20">
        <.empty_state_icon icon={@icon} />
      </div>
      <p class="text-sm font-medium text-base-content/60">{@title}</p>
      <p :if={@description} class="text-xs text-base-content/40 mt-1 max-w-xs">
        {@description}
      </p>
      <div :if={@action != []} class="mt-4">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  defp empty_state_icon(%{icon: "inbox"} = assigns) do
    ~H"""
    <svg class="w-full h-full" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="1.5"
        d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
      />
    </svg>
    """
  end

  defp empty_state_icon(%{icon: "alarm"} = assigns) do
    ~H"""
    <svg class="w-full h-full" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="1.5"
        d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
      />
    </svg>
    """
  end

  defp empty_state_icon(%{icon: "queue"} = assigns) do
    ~H"""
    <svg class="w-full h-full" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="1.5"
        d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
      />
    </svg>
    """
  end

  defp empty_state_icon(%{icon: "timeline"} = assigns) do
    ~H"""
    <svg class="w-full h-full" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="1.5"
        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
    """
  end

  defp empty_state_icon(assigns) do
    ~H"""
    <svg class="w-full h-full" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="1.5"
        d="M4 6h16M4 10h16M4 14h16M4 18h16"
      />
    </svg>
    """
  end

  # ============================================================================
  # Metric Card Component
  # ============================================================================

  @doc """
  Renders a metric card for dashboards and overview pages.
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :variant, :atom, default: :default
  attr :class, :string, default: ""

  def metric_card(assigns) do
    ~H"""
    <div class={[
      "metric-card p-4 rounded bg-base-200 border border-base-300",
      metric_variant_class(@variant),
      @class
    ]}>
      <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">
        {@label}
      </div>
      <div class="text-2xl font-mono font-bold">
        {@value}
      </div>
    </div>
    """
  end

  defp metric_variant_class(:success), do: "border-success/30"
  defp metric_variant_class(:warning), do: "border-warning/30"
  defp metric_variant_class(:error), do: "border-error/30"
  defp metric_variant_class(:info), do: "border-info/30"
  defp metric_variant_class(_), do: ""

  defp group_alarms_by_severity(alarms) do
    %{
      critical: Enum.filter(alarms, &(&1.severity == :critical)),
      warning: Enum.filter(alarms, &(&1.severity == :warning)),
      info: Enum.filter(alarms, &(&1.severity == :info))
    }
  end

  defp alarm_severity_class(%{severity: :critical}), do: "alarm-item-critical"
  defp alarm_severity_class(%{severity: :warning}), do: "alarm-item-warning"
  defp alarm_severity_class(%{severity: :info}), do: "alarm-item-info"
  defp alarm_severity_class(_), do: "alarm-item-info"

  defp alarm_source(%{target_name: name}) when is_binary(name), do: name
  defp alarm_source(%{target: %{name: name}}) when is_binary(name), do: name
  defp alarm_source(_), do: "Unknown"

  defp format_alarm_time(nil), do: "--:--"

  defp format_alarm_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> format_alarm_time(dt)
      _ -> time
    end
  end

  defp format_alarm_time(%DateTime{} = time) do
    Calendar.strftime(time, "%H:%M:%S")
  end

  defp format_alarm_time(_), do: "--:--"

  defp has_params?(%{parameters: params}) when is_map(params) and map_size(params) > 0, do: true
  defp has_params?(_), do: false

  defp format_param_value(val) when is_binary(val), do: val
  defp format_param_value(val) when is_number(val), do: to_string(val)
  defp format_param_value(val) when is_boolean(val), do: to_string(val)
  defp format_param_value(val) when is_list(val), do: "[...]"
  defp format_param_value(val) when is_map(val), do: "{...}"
  defp format_param_value(nil), do: "null"
  defp format_param_value(_), do: "?"

  defp queue_status_class(:pending), do: "pending"
  defp queue_status_class(:held), do: "held"
  defp queue_status_class(:executing), do: "executing"
  defp queue_status_class(:completed), do: "completed"
  defp queue_status_class(:failed), do: "failed"
  defp queue_status_class(_), do: "pending"

  defp priority_class(p) when p <= 1, do: "priority-high"
  defp priority_class(p) when p >= 4, do: "priority-low"
  defp priority_class(_), do: ""

  defp queue_target_name(%{target: %{name: name}}, _targets_map), do: name
  defp queue_target_name(%{target_name: name}, _targets_map) when is_binary(name), do: name

  defp queue_target_name(%{target_id: target_id}, targets_map) when is_map(targets_map) do
    case Map.get(targets_map, target_id) do
      %{name: name} -> name
      _ -> "?"
    end
  end

  defp queue_target_name(_, _), do: "?"

  # ============================================================================
  # Action Toolbar Component
  # ============================================================================

  @doc """
  Renders an action toolbar with consistent styling.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def action_toolbar(assigns) do
    ~H"""
    <div class={[
      "action-toolbar flex items-center gap-2 px-4 py-2 bg-base-200/50 border-b border-base-300",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ============================================================================
  # Resizable Panel Layout
  # ============================================================================

  @doc """
  Renders a two-pane resizable layout.

  Note: The actual resize behavior requires the colocated .SplitPanelResize hook.
  """
  attr :id, :string, required: true
  attr :left_width, :string, default: "30%"
  attr :min_left, :integer, default: 180
  attr :max_left, :integer, default: 640
  attr :class, :string, default: ""

  slot :left, required: true
  slot :right, required: true

  def resizable_panel(assigns) do
    ~H"""
    <div
      id={@id}
      class={["resizable-panel flex h-full", @class]}
      phx-hook=".SplitPanelResize"
      data-left-width={@left_width}
      data-min-left={@min_left}
      data-max-left={@max_left}
    >
      <div class="panel-left overflow-hidden" style={"width: #{@left_width}"}>
        {render_slot(@left)}
      </div>
      <div class="panel-resize-handle w-1 bg-base-300 hover:bg-primary/50 cursor-col-resize flex-shrink-0">
      </div>
      <div class="panel-right flex-1 overflow-hidden">
        {render_slot(@right)}
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SplitPanelResize">
      export default {
        mounted() {
          this.leftPanel = this.el.querySelector('.panel-left')
          this.handle = this.el.querySelector('.panel-resize-handle')
          this.rightPanel = this.el.querySelector('.panel-right')
          this.minWidth = Number(this.el.dataset.minLeft || 180)
          this.maxWidth = Number(this.el.dataset.maxLeft || 640)
          this.active = false

          if (this.handle && this.leftPanel && this.rightPanel) {
            this._onMouseMove = (event) => this.onDrag(event)
            this._onMouseUp = () => this.endDrag()
            this._onMouseDown = (event) => this.startDrag(event)
            this.handle.addEventListener('mousedown', this._onMouseDown)
          }
        },

        startDrag(event) {
          event.preventDefault()
          this.active = true
          this.startX = event.clientX
          this.startWidth = this.leftPanel.offsetWidth
          document.body.style.cursor = 'col-resize'
          document.body.style.userSelect = 'none'
          document.addEventListener('mousemove', this._onMouseMove)
          document.addEventListener('mouseup', this._onMouseUp)
        },

        onDrag(event) {
          if (!this.active) return
          const delta = event.clientX - this.startX
          let newWidth = this.startWidth + delta
          newWidth = Math.max(this.minWidth, Math.min(this.maxWidth, newWidth))
          this.leftPanel.style.width = `${newWidth}px`
        },

        endDrag() {
          if (!this.active) return
          this.active = false
          document.body.style.cursor = ''
          document.body.style.userSelect = ''
          document.removeEventListener('mousemove', this._onMouseMove)
          document.removeEventListener('mouseup', this._onMouseUp)
        },

        destroyed() {
          if (this.handle && this._onMouseDown) {
            this.handle.removeEventListener('mousedown', this._onMouseDown)
          }
          document.removeEventListener('mousemove', this._onMouseMove)
          document.removeEventListener('mouseup', this._onMouseUp)
        }
      }
    </script>
    """
  end
end
