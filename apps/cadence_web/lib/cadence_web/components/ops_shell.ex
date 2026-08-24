defmodule CadenceWeb.Components.OpsShell do
  @moduledoc """
  Chrome for the full-screen ops console layout: the top status bar and the
  collapsible left nav rail. Composed entirely from Tailwind utilities and
  existing HUD classes — no new CSS selectors.
  """

  use CadenceWeb, :html

  alias CadenceWeb.UI
  alias Phoenix.LiveView.JS

  attr :mission, :any, required: true
  attr :fleet_health, :any, required: true
  attr :current_scope, :any, required: true
  attr :unread_count, :integer, required: true
  attr :notifications, :list, required: true
  attr :memberships, :list, required: true
  attr :platform_admin?, :boolean, required: true

  def ops_status_bar(assigns) do
    assigns = assign(assigns, :presentation, ops_status_bar_presentation(assigns))

    ~H"""
    <.vue
      id="ops-status-bar-component"
      v-component="OpsStatusBar"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp ops_status_bar_presentation(assigns) do
    %{
      "header" => %{
        "class" =>
          "h-10 shrink-0 flex items-center gap-3 px-3 border-b border-primary/20 bg-base-200 hud-grid"
      },
      "mission" => mission_presentation(assigns.mission),
      "posture" =>
        posture_presentation(assigns.fleet_health)
        |> Map.merge(%{
          "id" => "ops-urgent-posture",
          "root_class" => "flex-1 flex items-center justify-center gap-2 min-w-0"
        }),
      "clock" => %{
        "component" => "UtcClock",
        "id" => "ops-utc-clock",
        "class" => "font-mono text-xs text-base-content/70 tabular-nums"
      },
      "connection" => connection_presentation(),
      "account" => account_presentation(assigns)
    }
  end

  defp mission_presentation(mission) do
    mission_path = ~p"/missions/#{mission.mission_id}"

    %{
      "class" => "flex items-center gap-2 min-w-0 text-base-content/60 hover:text-base-content",
      "attrs" => %{
        "href" => mission_path,
        "data-phx-link" => "redirect",
        "data-phx-link-state" => "push"
      },
      "icon_class" => "hero-arrow-left h-3.5 w-3.5 shrink-0",
      "name" => %{
        "class" => "text-sm font-bold text-base-content truncate",
        "text" => mission.display_name
      },
      "slug" => %{
        "class" => "font-mono text-xs text-base-content/60",
        "text" => mission.slug
      }
    }
  end

  defp posture_presentation(fleet_health) do
    cond do
      fleet_health && fleet_health.normalized_state_counts.red > 0 ->
        severity_posture(
          "critical",
          fleet_health.normalized_state_counts.red,
          "Critical",
          "bg-error/20 text-error"
        )

      fleet_health && fleet_health.normalized_state_counts.yellow > 0 ->
        severity_posture(
          "warning",
          fleet_health.normalized_state_counts.yellow,
          "Warning",
          "bg-warning/20 text-warning"
        )

      fleet_health ->
        %{
          "kind" => "nominal",
          "class" =>
            "inline-flex items-center gap-1.5 font-mono text-[0.6875rem] uppercase tracking-[0.14em] text-success",
          "dot_class" => "h-1.5 w-1.5 rounded-full bg-success",
          "label" => "Nominal"
        }

      true ->
        %{
          "kind" => "unavailable",
          "class" =>
            "font-mono text-[0.6875rem] uppercase tracking-[0.14em] text-base-content/45",
          "label" => "Posture unavailable"
        }
    end
  end

  defp severity_posture(kind, count, label, severity_class) do
    %{
      "kind" => kind,
      "class" =>
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium #{severity_class}",
      "dot_class" => "w-1.5 h-1.5 rounded-full bg-current",
      "count" => %{"class" => "font-mono", "text" => count},
      "label" => %{"class" => "uppercase text-[0.65rem]", "text" => label}
    }
  end

  defp connection_presentation do
    show = Jason.encode!(JS.show())
    hide = Jason.encode!(JS.hide())

    %{
      "ok" => %{
        "id" => "ops-conn-ok",
        "class" => "h-2 w-2 rounded-full bg-success",
        "title" => "Connected",
        "attrs" => %{"phx-connected" => show, "phx-disconnected" => hide}
      },
      "lost" => %{
        "id" => "ops-conn-lost",
        "class" => "hidden h-2 w-2 rounded-full bg-error motion-safe:animate-pulse",
        "title" => "Connection lost",
        "attrs" => %{"phx-disconnected" => show, "phx-connected" => hide}
      }
    }
  end

  defp account_presentation(assigns) do
    if assigns.current_scope && assigns.current_scope.user do
      %{
        "notifications_bell" => %{
          "component" => "NotificationsBell",
          "id" => "notifications-bell-ops",
          "class" => "contents",
          "presentation" =>
            UI.notifications_bell_presentation(%{
              id: "notifications-bell-ops",
              count: assigns.unread_count,
              notifications: assigns.notifications
            })
        },
        "user_menu" => %{
          "component" => "UserMenu",
          "id" => "user-menu-ops",
          "class" => "contents",
          "presentation" =>
            UI.user_menu_presentation(%{
              id: "user-menu-ops",
              scope: assigns.current_scope,
              memberships: assigns.memberships,
              platform_admin?: assigns.platform_admin?
            })
        }
      }
    end
  end

  attr :mission, :any, required: true
  attr :dashboard_navigation, :map, required: true
  attr :active_dashboard_id, :string, required: true
  attr :active_item, :atom, required: true
  attr :current_scope, :any, required: true
  attr :dashboard_author?, :boolean, required: true
  attr :operational_focus, :map, default: nil

  def ops_nav_rail(assigns) do
    assigns = assign(assigns, :ops_nav_props, ops_nav_props(assigns))

    ~H"""
    <.vue
      id="ops-nav-rail-component"
      v-component="OpsNavRail"
      groups={@ops_nav_props["groups"]}
      dashboard_groups={@ops_nav_props["dashboard_groups"]}
      empty_state={@ops_nav_props["empty_state"]}
      new_dashboard={@ops_nav_props["new_dashboard"]}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp ops_nav_props(assigns) do
    dashboard_groups = dashboard_groups(assigns)

    %{
      "groups" => navigation_groups(assigns),
      "dashboard_groups" => dashboard_groups,
      "empty_state" =>
        if(dashboard_groups == [],
          do: "Star dashboards or open one to keep it close.",
          else: nil
        ),
      "new_dashboard" => new_dashboard(assigns)
    }
  end

  defp navigation_groups(assigns) do
    mission_id = assigns.mission.mission_id

    [
      %{
        "key" => "observe",
        "label" => "Observe",
        "class" => "px-2 pt-2 space-y-0.5",
        "items" => [
          nav_item(
            assigns,
            :dashboards,
            "Dashboards",
            "hero-squares-2x2",
            ~p"/missions/#{mission_id}/ops/dashboards"
          ),
          nav_item(
            assigns,
            :explore,
            "Explore",
            "hero-magnifying-glass",
            ~p"/missions/#{mission_id}/ops/explore"
          ),
          nav_item(
            assigns,
            :alarms,
            "Alarms",
            "hero-bell-alert",
            ~p"/missions/#{mission_id}/ops/alarms"
          ),
          nav_item(
            assigns,
            :timeline,
            "Timeline",
            "hero-clock",
            ~p"/missions/#{mission_id}/ops/timeline"
          )
        ]
      },
      %{
        "key" => "act",
        "label" => "Act",
        "class" => "mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5",
        "items" =>
          [
            nav_item(
              assigns,
              :commands,
              "Commands",
              "hero-command-line",
              ~p"/missions/#{mission_id}/ops/commands"
            )
          ] ++
            activation_items(assigns)
      },
      %{
        "key" => "plan",
        "label" => "Plan",
        "class" => "mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5",
        "items" => [
          nav_item(
            assigns,
            :planning,
            "Planning",
            "hero-chart-bar-square",
            ~p"/missions/#{mission_id}/ops/planning"
          ),
          nav_item(
            assigns,
            :requirements,
            "Requirements",
            "hero-clipboard-document-list",
            ~p"/missions/#{mission_id}/ops/requirements"
          ),
          nav_item(
            assigns,
            :contacts,
            "Contacts",
            "hero-calendar-days",
            ~p"/missions/#{mission_id}/ops/contacts"
          )
        ]
      },
      %{
        "key" => "system",
        "label" => "System",
        "class" => "mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5",
        "items" => [
          nav_item(
            assigns,
            :data_sources,
            "Data Sources",
            "hero-circle-stack",
            ~p"/missions/#{mission_id}/ops/data-sources"
          ),
          nav_item(
            assigns,
            :data_operations,
            "Data Operations",
            "hero-arrow-path-rounded-square",
            ~p"/missions/#{mission_id}/ops/data-operations"
          )
        ]
      }
    ]
  end

  defp activation_items(assigns) do
    if activation_approver?(assigns.current_scope) do
      [
        nav_item(
          assigns,
          :activations,
          "Approvals",
          "hero-shield-check",
          ~p"/missions/#{assigns.mission.mission_id}/ops/activations"
        )
      ]
    else
      []
    end
  end

  defp nav_item(assigns, item, label, icon, href) do
    %{
      "key" => nav_key(label),
      "label" => label,
      "icon" => icon,
      "href" => with_operational_focus(href, assigns.operational_focus),
      "active" => assigns.active_item == item
    }
  end

  defp dashboard_groups(assigns) do
    [
      dashboard_group(
        assigns,
        "Starred",
        "hero-star-solid",
        assigns.dashboard_navigation.starred
      ),
      dashboard_group(assigns, "Recent", "hero-clock", assigns.dashboard_navigation.recent)
    ]
    |> Enum.reject(&(&1["items"] == []))
  end

  defp dashboard_group(assigns, label, icon, dashboards) do
    %{
      "key" => String.downcase(label),
      "label" => label,
      "icon" => icon,
      "items" => Enum.map(dashboards, &dashboard_item(assigns, &1))
    }
  end

  defp dashboard_item(assigns, dashboard) do
    mission_id = assigns.mission.mission_id

    %{
      "dashboard_id" => dashboard.dashboard_id,
      "label" => dashboard.name,
      "href" =>
        with_operational_focus(
          ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard.dashboard_id}",
          assigns.operational_focus
        ),
      "active" => dashboard.dashboard_id == assigns.active_dashboard_id
    }
  end

  defp new_dashboard(%{dashboard_author?: false}), do: nil

  defp new_dashboard(assigns) do
    mission_id = assigns.mission.mission_id

    %{
      "label" => "New Dashboard",
      "title" => "New dashboard",
      "icon" => "hero-plus",
      "href" =>
        with_operational_focus(
          ~p"/missions/#{mission_id}/ops/dashboards/new",
          assigns.operational_focus
        )
    }
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

  defp nav_key(label) do
    label
    |> String.downcase()
    |> String.replace(" ", "_")
  end
end
