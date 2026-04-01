defmodule CadenceWeb.OpsConsoleLive.NavPanelComponent do
  @moduledoc """
  Navigation panel for OPS Console.

  Displays:
  - Mode selector (Dashboard, Commands, Queue, Alarms, Timeline)
  - Dashboard list (when in dashboard mode)
  - Quick actions

  Supports collapsed (rail) and expanded states.
  """

  use CadenceWeb, :live_component

  @modes [
    %{id: :dashboard, label: "Dashboard", icon: :squares, path_suffix: ""},
    %{id: :commands, label: "Commands", icon: :terminal, path_suffix: "/commands"},
    %{id: :queue, label: "Queue", icon: :queue, path_suffix: "/queue"},
    %{id: :alarms, label: "Alarms", icon: :bell, path_suffix: "/alarms"},
    %{id: :timeline, label: "Timeline", icon: :clock, path_suffix: "/timeline"}
  ]

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:collapsed, fn -> false end)
      |> assign_new(:current_dashboard_id, fn -> nil end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :modes, @modes)

    ~H"""
    <div class="nav-panel-v2 flex flex-col h-full">
      <!-- Expanded view (hidden when panel is collapsed) -->
      <div class="nav-expanded flex flex-col h-full hud-grid">
        <!-- Header with mission name -->
        <div class="flex items-center gap-2 px-3 py-2 border-b border-base-300/50">
          <span class="text-xs font-medium text-base-content/70 truncate">
            {@mission.name}
          </span>
        </div>
        <!-- Mode selector -->
        <div class="flex-1 overflow-y-auto py-2">
          <div class="mode-selector">
            <.mode_button
              :for={mode <- @modes}
              mode={mode}
              current_mode={@current_mode}
              mission_id={@mission.id}
            />
          </div>
          <!-- Dashboard list (only when in dashboard mode) -->
          <div
            :if={@current_mode == :dashboard}
            class="mt-4 px-2 border-t border-base-300/50 pt-4"
          >
            <div class="flex items-center justify-between mb-2">
              <span class="text-[0.65rem] uppercase tracking-wide text-base-content/40">
                Dashboards
              </span>
              <button
                type="button"
                phx-click="open_create_dashboard"
                class="btn btn-ghost btn-xs"
                title="Create dashboard"
              >
                <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 4v16m8-8H4"
                  />
                </svg>
              </button>
            </div>
            <div class="space-y-0.5">
              <.dashboard_item
                :for={dashboard <- @dashboards}
                dashboard={dashboard}
                active={dashboard.id == @current_dashboard_id}
              />
            </div>
          </div>
        </div>
      </div>
      
    <!-- Rail view (shown when panel is collapsed) -->
      <div class="nav-rail hidden flex-col items-center py-2 hud-grid">
        <div class="rail-section">
          <.rail_mode_button
            :for={mode <- @modes}
            mode={mode}
            current_mode={@current_mode}
            mission_id={@mission.id}
          />
        </div>
      </div>
    </div>
    """
  end

  # Mode button component (expanded view)
  attr :mode, :map, required: true
  attr :current_mode, :atom, required: true
  attr :mission_id, :string, required: true

  defp mode_button(assigns) do
    path = build_mode_path(assigns.mission_id, assigns.mode.path_suffix)
    active = assigns.current_mode == assigns.mode.id
    assigns = assign(assigns, path: path, active: active)

    ~H"""
    <.link
      navigate={@path}
      class={[
        "mode-btn",
        @active && "active"
      ]}
    >
      <.mode_icon icon={@mode.icon} class="mode-icon" />
      <span class="mode-label">{@mode.label}</span>
    </.link>
    """
  end

  # Rail mode button (collapsed view - icon only)
  attr :mode, :map, required: true
  attr :current_mode, :atom, required: true
  attr :mission_id, :string, required: true

  defp rail_mode_button(assigns) do
    path = build_mode_path(assigns.mission_id, assigns.mode.path_suffix)
    active = assigns.current_mode == assigns.mode.id
    assigns = assign(assigns, path: path, active: active)

    ~H"""
    <.link
      navigate={@path}
      class={["rail-btn", @active && "active"]}
      title={@mode.label}
    >
      <.mode_icon icon={@mode.icon} class="w-5 h-5" />
    </.link>
    """
  end

  # Dashboard item component
  attr :dashboard, :map, required: true
  attr :active, :boolean, required: true

  defp dashboard_item(assigns) do
    ~H"""
    <div class={[
      "group flex items-center gap-1 px-2 py-1 rounded text-xs",
      @active && "bg-primary/10 text-primary",
      !@active && "text-base-content/60 hover:bg-base-300"
    ]}>
      <button
        type="button"
        phx-click="switch_dashboard"
        phx-value-id={@dashboard.id}
        class="flex-1 truncate text-left"
      >
        {@dashboard.name}
      </button>
      <div class="opacity-0 group-hover:opacity-100 flex items-center gap-0.5">
        <button
          type="button"
          phx-click="open_rename_dashboard"
          phx-value-id={@dashboard.id}
          phx-value-name={@dashboard.name}
          class="btn btn-ghost btn-xs btn-square"
          title="Rename"
        >
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"
            />
          </svg>
        </button>
        <button
          type="button"
          phx-click="open_delete_confirm"
          phx-value-id={@dashboard.id}
          phx-value-name={@dashboard.name}
          class="btn btn-ghost btn-xs btn-square text-error/70 hover:text-error"
          title="Delete"
        >
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
            />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  # Mode icons
  attr :icon, :atom, required: true
  attr :class, :string, default: ""

  defp mode_icon(%{icon: :squares} = assigns) do
    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"
      />
    </svg>
    """
  end

  defp mode_icon(%{icon: :terminal} = assigns) do
    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
      />
    </svg>
    """
  end

  defp mode_icon(%{icon: :queue} = assigns) do
    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
      />
    </svg>
    """
  end

  defp mode_icon(%{icon: :bell} = assigns) do
    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
      />
    </svg>
    """
  end

  defp mode_icon(%{icon: :clock} = assigns) do
    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
    """
  end

  # Build mode path - routes are:
  # /missions/:id/ops (dashboard)
  # /missions/:id/ops/commands
  # /missions/:id/ops/queue
  # /missions/:id/ops/alarms
  # /missions/:id/ops/timeline
  defp build_mode_path(mission_id, ""), do: "/missions/#{mission_id}/ops"
  defp build_mode_path(mission_id, suffix), do: "/missions/#{mission_id}/ops#{suffix}"
end
