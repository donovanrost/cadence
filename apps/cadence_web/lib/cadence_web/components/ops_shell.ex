defmodule CadenceWeb.Components.OpsShell do
  @moduledoc """
  Chrome for the full-screen ops console layout: the top status bar and the
  collapsible left nav rail. Composed entirely from Tailwind utilities and
  existing HUD classes — no new CSS selectors.
  """

  use CadenceWeb, :html

  alias Phoenix.LiveView.JS

  attr :mission, :any, required: true
  attr :fleet_health, :any, required: true
  attr :current_scope, :any, required: true
  attr :unread_count, :integer, required: true
  attr :notifications, :list, required: true
  attr :memberships, :list, required: true
  attr :platform_admin?, :boolean, required: true

  def ops_status_bar(assigns) do
    ~H"""
    <header class="h-10 shrink-0 flex items-center gap-3 px-3 border-b border-primary/20 bg-base-200 hud-grid">
      <.link
        navigate={~p"/missions/#{@mission.mission_id}"}
        class="flex items-center gap-2 min-w-0 text-base-content/60 hover:text-base-content"
      >
        <span class="hero-arrow-left h-3.5 w-3.5 shrink-0"></span>
        <span class="text-sm font-bold text-base-content truncate">{@mission.display_name}</span>
        <span class="font-mono text-xs text-base-content/60">{@mission.slug}</span>
      </.link>

      <div class="flex-1 flex items-center justify-center gap-2 min-w-0">
        <%= if @fleet_health do %>
          <span class="hud-label hidden md:inline">Fleet</span>
          <.severity_badge
            severity={:critical}
            count={@fleet_health.normalized_state_counts.red}
            label="Red"
          />
          <.severity_badge
            severity={:warning}
            count={@fleet_health.normalized_state_counts.yellow}
            label="Yellow"
          />
          <.severity_badge
            severity={:info}
            count={@fleet_health.normalized_state_counts.blue}
            label="Blue"
          />
          <.severity_badge
            severity={:nominal}
            count={@fleet_health.normalized_state_counts.green}
            label="Green"
          />
          <span class="font-mono text-xs text-base-content/60 hidden lg:inline">
            {@fleet_health.violating_points} violating
          </span>
        <% end %>
      </div>

      <span
        id="ops-utc-clock"
        phx-hook="UtcClock"
        phx-update="ignore"
        class="font-mono text-xs text-base-content/70 tabular-nums"
      >
      </span>
      <span
        id="ops-conn-ok"
        class="h-2 w-2 rounded-full bg-success"
        title="Connected"
        phx-connected={JS.show()}
        phx-disconnected={JS.hide()}
      >
      </span>
      <span
        id="ops-conn-lost"
        class="hidden h-2 w-2 rounded-full bg-error motion-safe:animate-pulse"
        title="Connection lost"
        phx-disconnected={JS.show()}
        phx-connected={JS.hide()}
      >
      </span>

      <%= if @current_scope && @current_scope.user do %>
        <.notifications_bell
          id="notifications-bell-ops"
          count={@unread_count}
          notifications={@notifications}
        />
        <.user_menu
          id="user-menu-ops"
          scope={@current_scope}
          memberships={@memberships}
          platform_admin?={@platform_admin?}
        />
      <% end %>
    </header>
    """
  end

  attr :mission, :any, required: true
  attr :dashboards, :list, required: true
  attr :active_dashboard_id, :string, required: true
  attr :active_item, :atom, required: true

  def ops_nav_rail(assigns) do
    ~H"""
    <nav
      id="ops-nav-rail"
      phx-hook="NavRail"
      data-storage-key="cadence-ops-rail"
      data-rail-role="navigation"
      class="group/rail w-12 data-[expanded]:w-56 shrink-0 flex flex-col border-r border-primary/20 bg-base-200 hud-grid overflow-y-auto overflow-x-hidden transition-[width] duration-150"
    >
      <button
        type="button"
        data-rail-toggle
        aria-label="Toggle navigation"
        class="h-9 shrink-0 flex items-center justify-center text-base-content/60 hover:text-base-content"
      >
        <span class="hero-bars-3 h-4 w-4 pointer-events-none"></span>
      </button>

      <div class="px-2 pt-2 space-y-0.5">
        <span class="hud-label px-1 hidden group-data-[expanded]/rail:block">Modes</span>
        <.rail_link
          navigate={~p"/missions/#{@mission.mission_id}/ops/dashboards"}
          icon="hero-squares-2x2"
          label="Dashboards"
          active={@active_item == :dashboards}
        />
        <.rail_link
          navigate={~p"/missions/#{@mission.mission_id}/ops/data-sources"}
          icon="hero-circle-stack"
          label="Data Sources"
          active={@active_item == :data_sources}
        />
        <.rail_link
          navigate={~p"/missions/#{@mission.mission_id}/ops/planning"}
          icon="hero-chart-bar-square"
          label="Planning"
          active={@active_item == :planning}
        />
        <.rail_link
          navigate={~p"/missions/#{@mission.mission_id}/ops/requirements"}
          icon="hero-clipboard-document-list"
          label="Requirements"
          active={@active_item == :requirements}
        />
        <.rail_link
          navigate={~p"/missions/#{@mission.mission_id}/ops/contacts"}
          icon="hero-calendar-days"
          label="Contacts"
          active={@active_item == :contacts}
        />
        <.rail_item icon="hero-command-line" label="Commands" active={false} disabled={true} />
        <.rail_item icon="hero-bell-alert" label="Alarms" active={false} disabled={true} />
        <.rail_item icon="hero-clock" label="Timeline" active={false} disabled={true} />
      </div>

      <div class="mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5 min-h-0">
        <span class="hud-label px-1 hidden group-data-[expanded]/rail:block">Dashboards</span>
        <.link
          :for={dashboard <- @dashboards}
          navigate={~p"/missions/#{@mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"}
          title={dashboard.name}
          class={[
            "flex items-center gap-2 px-2 py-1.5 text-xs truncate",
            dashboard.dashboard_id == @active_dashboard_id &&
              "bg-primary/10 text-primary border-l-2 border-primary",
            dashboard.dashboard_id != @active_dashboard_id &&
              "text-base-content/70 hover:text-base-content"
          ]}
        >
          <span class="font-mono text-[0.625rem] uppercase shrink-0 w-4 text-center">
            {String.first(dashboard.name)}
          </span>
          <span class="truncate hidden group-data-[expanded]/rail:inline">{dashboard.name}</span>
        </.link>
        <.link
          navigate={~p"/missions/#{@mission.mission_id}/ops/dashboards/new"}
          title="New dashboard"
          class="flex items-center gap-2 px-2 py-1.5 text-xs text-base-content/60 hover:text-primary"
        >
          <span class="hero-plus h-3.5 w-3.5 shrink-0"></span>
          <span class="hidden group-data-[expanded]/rail:inline">New Dashboard</span>
        </.link>
      </div>
    </nav>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true

  defp rail_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      title={@label}
      class={[
        "flex items-center gap-2 px-2 py-1.5 text-xs",
        @active && "bg-primary/10 text-primary border-l-2 border-primary",
        not @active && "text-base-content/70 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="h-4 w-4 shrink-0" />
      <span class="truncate hidden group-data-[expanded]/rail:inline">{@label}</span>
    </.link>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :disabled, :boolean, default: false

  defp rail_item(assigns) do
    ~H"""
    <span
      title={if @disabled, do: "#{@label} — coming soon", else: @label}
      class={[
        "flex items-center gap-2 px-2 py-1.5 text-xs",
        @active && "bg-primary/10 text-primary border-l-2 border-primary",
        @disabled && "opacity-40 cursor-not-allowed text-base-content/70",
        not @active and not @disabled && "text-base-content/70"
      ]}
    >
      <.icon name={@icon} class="h-4 w-4 shrink-0" />
      <span class="truncate hidden group-data-[expanded]/rail:inline">{@label}</span>
    </span>
    """
  end
end
