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
        <.icon name="hero-arrow-left" class="h-3.5 w-3.5 shrink-0" />
        <span class="text-sm font-bold text-base-content truncate">{@mission.display_name}</span>
        <span class="font-mono text-xs text-base-content/60">{@mission.slug}</span>
      </.link>

      <div id="ops-urgent-posture" class="flex-1 flex items-center justify-center gap-2 min-w-0">
        <%= cond do %>
          <% @fleet_health && @fleet_health.normalized_state_counts.red > 0 -> %>
          <.severity_badge
            severity={:critical}
            count={@fleet_health.normalized_state_counts.red}
            label="Critical"
          />
          <% @fleet_health && @fleet_health.normalized_state_counts.yellow > 0 -> %>
          <.severity_badge
            severity={:warning}
            count={@fleet_health.normalized_state_counts.yellow}
            label="Warning"
          />
          <% @fleet_health -> %>
          <span class="inline-flex items-center gap-1.5 font-mono text-[0.6875rem] uppercase tracking-[0.14em] text-success">
            <span class="h-1.5 w-1.5 rounded-full bg-success"></span>
            Nominal
          </span>
          <% true -> %>
          <span class="font-mono text-[0.6875rem] uppercase tracking-[0.14em] text-base-content/45">
            Posture unavailable
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
  attr :dashboard_navigation, :map, required: true
  attr :active_dashboard_id, :string, required: true
  attr :active_item, :atom, required: true
  attr :current_scope, :any, required: true
  attr :dashboard_author?, :boolean, required: true
  attr :operational_focus, :map, default: nil

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
        <.icon name="hero-bars-3" class="h-4 w-4 pointer-events-none" />
      </button>

      <div data-ops-nav-group="observe" class="px-2 pt-2 space-y-0.5">
        <span class="hud-label px-1 hidden group-data-[expanded]/rail:block">Observe</span>
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/dashboards", @operational_focus)}
          icon="hero-squares-2x2"
          label="Dashboards"
          active={@active_item == :dashboards}
        />
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/explore", @operational_focus)}
          icon="hero-magnifying-glass"
          label="Explore"
          active={@active_item == :explore}
        />
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/alarms", @operational_focus)}
          icon="hero-bell-alert"
          label="Alarms"
          active={@active_item == :alarms}
        />
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/timeline", @operational_focus)}
          icon="hero-clock"
          label="Timeline"
          active={@active_item == :timeline}
        />
      </div>

      <div data-ops-nav-group="act" class="mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5">
        <span class="hud-label px-1 hidden group-data-[expanded]/rail:block">Act</span>
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/commands", @operational_focus)}
          icon="hero-command-line"
          label="Commands"
          active={@active_item == :commands}
        />
        <.rail_link
          :if={activation_approver?(@current_scope)}
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/activations", @operational_focus)}
          icon="hero-shield-check"
          label="Approvals"
          active={@active_item == :activations}
        />
      </div>

      <div data-ops-nav-group="plan" class="mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5">
        <span class="hud-label px-1 hidden group-data-[expanded]/rail:block">Plan</span>
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/planning", @operational_focus)}
          icon="hero-chart-bar-square"
          label="Planning"
          active={@active_item == :planning}
        />
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/requirements", @operational_focus)}
          icon="hero-clipboard-document-list"
          label="Requirements"
          active={@active_item == :requirements}
        />
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/contacts", @operational_focus)}
          icon="hero-calendar-days"
          label="Contacts"
          active={@active_item == :contacts}
        />
      </div>

      <div data-ops-nav-group="system" class="mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5">
        <span class="hud-label px-1 hidden group-data-[expanded]/rail:block">System</span>
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/data-sources", @operational_focus)}
          icon="hero-circle-stack"
          label="Data Sources"
          active={@active_item == :data_sources}
        />
        <.rail_link
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/data-operations", @operational_focus)}
          icon="hero-arrow-path-rounded-square"
          label="Data Operations"
          active={@active_item == :data_operations}
        />
      </div>

      <div class="mt-3 border-t border-primary/20 px-2 pt-2 space-y-1 min-h-0">
        <.dashboard_nav_group
          title="Starred"
          dashboards={@dashboard_navigation.starred}
          mission={@mission}
          active_dashboard_id={@active_dashboard_id}
          operational_focus={@operational_focus}
          icon="hero-star-solid"
        />
        <.dashboard_nav_group
          title="Recent"
          dashboards={@dashboard_navigation.recent}
          mission={@mission}
          active_dashboard_id={@active_dashboard_id}
          operational_focus={@operational_focus}
          icon="hero-clock"
        />
        <p
          :if={@dashboard_navigation.starred == [] and @dashboard_navigation.recent == []}
          class="hidden px-2 py-1 text-[0.6875rem] leading-4 text-base-content/45 group-data-[expanded]/rail:block"
        >
          Star dashboards or open one to keep it close.
        </p>
        <.link
          :if={@dashboard_author?}
          navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/dashboards/new", @operational_focus)}
          title="New dashboard"
          class="flex items-center gap-2 px-2 py-1.5 text-xs text-base-content/60 hover:text-primary"
        >
          <.icon name="hero-plus" class="h-3.5 w-3.5 shrink-0" />
          <span class="hidden group-data-[expanded]/rail:inline">New Dashboard</span>
        </.link>
      </div>
    </nav>
    """
  end

  attr :title, :string, required: true
  attr :dashboards, :list, required: true
  attr :mission, :any, required: true
  attr :active_dashboard_id, :string, required: true
  attr :operational_focus, :map, default: nil
  attr :icon, :string, required: true

  defp dashboard_nav_group(assigns) do
    ~H"""
    <div :if={@dashboards != []} data-ops-dashboard-nav-group={String.downcase(@title)}>
      <span class="hud-label px-1 hidden group-data-[expanded]/rail:block">{@title}</span>
      <.link
        :for={dashboard <- @dashboards}
        navigate={with_operational_focus(~p"/missions/#{@mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}", @operational_focus)}
        title={dashboard.name}
        data-ops-dashboard-nav-item={dashboard.dashboard_id}
        class={[
          "flex items-center gap-2 px-2 py-1.5 text-xs truncate",
          dashboard.dashboard_id == @active_dashboard_id &&
            "bg-primary/10 text-primary border-l-2 border-primary",
          dashboard.dashboard_id != @active_dashboard_id &&
            "text-base-content/70 hover:text-base-content"
        ]}
      >
        <.icon name={@icon} class="h-3.5 w-3.5 shrink-0" />
        <span class="truncate hidden group-data-[expanded]/rail:inline">{dashboard.name}</span>
      </.link>
    </div>
    """
  end

  defp activation_approver?(scope) do
    MapSet.member?(scope.capabilities, :organization_admin) or
      MapSet.member?(scope.capabilities, :platform_admin)
  end

  defp with_operational_focus(path, %{kind: :command, id: command_request_id})
       when is_binary(command_request_id) and command_request_id != "" do
    uri = URI.parse(path)

    query =
      uri.query
      |> then(&URI.decode_query(&1 || ""))
      |> Map.put("focus_command_id", command_request_id)
      |> URI.encode_query()

    %{uri | query: query} |> URI.to_string()
  end

  defp with_operational_focus(path, _operational_focus), do: path

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true

  defp rail_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      title={@label}
      data-ops-nav-item={nav_key(@label)}
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

  defp nav_key(label) do
    label
    |> String.downcase()
    |> String.replace(" ", "_")
  end
end
