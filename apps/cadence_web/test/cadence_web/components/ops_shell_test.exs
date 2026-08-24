defmodule CadenceWeb.Components.OpsShellTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.Components.OpsShell

  defp render_status_bar(overrides \\ []) do
    [
      mission: %{mission_id: "mission-123", display_name: "Ops Mission", slug: "ops"},
      fleet_health: nil,
      current_scope: nil,
      unread_count: 0,
      notifications: [],
      memberships: [],
      platform_admin?: false
    ]
    |> Keyword.merge(overrides)
    |> then(&render_component(&OpsShell.ops_status_bar/1, &1))
    |> LiveVue.Test.get_vue(id: "ops-status-bar-component")
  end

  defp fleet_health(red, yellow) do
    %{normalized_state_counts: %{red: red, yellow: yellow}}
  end

  defp scope(user, organization \\ nil) do
    %{
      user: user,
      organization: organization,
      admin_mode?: false
    }
  end

  defp hidden_fields(form) do
    Map.new(form["hidden_fields"], fn %{"attrs" => attrs} -> {attrs["name"], attrs} end)
  end

  test "renders one JSON-safe non-SSR parent with the exact header and mission link presentation" do
    vue = render_status_bar()
    presentation = vue.props["presentation"]

    assert vue.component == "OpsStatusBar"
    assert vue.id == "ops-status-bar-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.props == %{"presentation" => presentation}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert presentation |> Map.keys() |> Enum.sort() ==
             ~w(account clock connection header mission posture)

    assert presentation["header"] == %{
             "class" =>
               "h-10 shrink-0 flex items-center gap-3 px-3 border-b border-primary/20 bg-base-200 hud-grid"
           }

    assert presentation["mission"] == %{
             "class" =>
               "flex items-center gap-2 min-w-0 text-base-content/60 hover:text-base-content",
             "attrs" => %{
               "href" => "/missions/mission-123",
               "data-phx-link" => "redirect",
               "data-phx-link-state" => "push"
             },
             "icon_class" => "hero-arrow-left h-3.5 w-3.5 shrink-0",
             "name" => %{
               "class" => "text-sm font-bold text-base-content truncate",
               "text" => "Ops Mission"
             },
             "slug" => %{
               "class" => "font-mono text-xs text-base-content/60",
               "text" => "ops"
             }
           }

    assert presentation["clock"] == %{
             "component" => "UtcClock",
             "id" => "ops-utc-clock",
             "class" => "font-mono text-xs text-base-content/70 tabular-nums"
           }
  end

  test "critical posture has red precedence and preserves the severity badge topology" do
    posture = render_status_bar(fleet_health: fleet_health(3, 8)).props["presentation"]["posture"]

    assert posture == %{
             "id" => "ops-urgent-posture",
             "root_class" => "flex-1 flex items-center justify-center gap-2 min-w-0",
             "kind" => "critical",
             "class" =>
               "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium bg-error/20 text-error",
             "dot_class" => "w-1.5 h-1.5 rounded-full bg-current",
             "count" => %{"class" => "font-mono", "text" => 3},
             "label" => %{"class" => "uppercase text-[0.65rem]", "text" => "Critical"}
           }
  end

  test "mission identity text preserves nil, false, and numeric values through JSON" do
    vue =
      render_status_bar(mission: %{mission_id: "mission-edge", display_name: nil, slug: false})

    mission = vue.props["presentation"]["mission"]

    assert mission["attrs"]["href"] == "/missions/mission-edge"
    assert mission["name"]["text"] == nil
    assert mission["slug"]["text"] == false
    assert mission == Jason.decode!(Jason.encode!(mission))

    numeric_vue =
      render_status_bar(mission: %{mission_id: "mission-numeric", display_name: 0, slug: 7})

    numeric_mission = numeric_vue.props["presentation"]["mission"]

    assert numeric_mission["name"]["text"] == 0
    assert numeric_mission["slug"]["text"] == 7
    assert numeric_mission == Jason.decode!(Jason.encode!(numeric_mission))
  end

  test "warning posture preserves the yellow count and severity badge presentation" do
    posture = render_status_bar(fleet_health: fleet_health(0, 2)).props["presentation"]["posture"]

    assert posture == %{
             "id" => "ops-urgent-posture",
             "root_class" => "flex-1 flex items-center justify-center gap-2 min-w-0",
             "kind" => "warning",
             "class" =>
               "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium bg-warning/20 text-warning",
             "dot_class" => "w-1.5 h-1.5 rounded-full bg-current",
             "count" => %{"class" => "font-mono", "text" => 2},
             "label" => %{"class" => "uppercase text-[0.65rem]", "text" => "Warning"}
           }
  end

  test "nominal posture preserves the exact status presentation" do
    posture = render_status_bar(fleet_health: fleet_health(0, 0)).props["presentation"]["posture"]

    assert posture == %{
             "id" => "ops-urgent-posture",
             "root_class" => "flex-1 flex items-center justify-center gap-2 min-w-0",
             "kind" => "nominal",
             "class" =>
               "inline-flex items-center gap-1.5 font-mono text-[0.6875rem] uppercase tracking-[0.14em] text-success",
             "dot_class" => "h-1.5 w-1.5 rounded-full bg-success",
             "label" => "Nominal"
           }
  end

  test "unavailable posture preserves the exact fallback presentation" do
    nil_posture = render_status_bar(fleet_health: nil).props["presentation"]["posture"]
    false_posture = render_status_bar(fleet_health: false).props["presentation"]["posture"]

    expected = %{
      "id" => "ops-urgent-posture",
      "root_class" => "flex-1 flex items-center justify-center gap-2 min-w-0",
      "kind" => "unavailable",
      "class" => "font-mono text-[0.6875rem] uppercase tracking-[0.14em] text-base-content/45",
      "label" => "Posture unavailable"
    }

    assert nil_posture == expected
    assert false_posture == expected
  end

  test "connection indicators preserve exact IDs, classes, titles, and serialized JS commands" do
    connection = render_status_bar().props["presentation"]["connection"]

    assert connection["ok"] == %{
             "id" => "ops-conn-ok",
             "class" => "h-2 w-2 rounded-full bg-success",
             "title" => "Connected",
             "attrs" => %{
               "phx-connected" => ~s([["show",{}]]),
               "phx-disconnected" => ~s([["hide",{}]])
             }
           }

    assert connection["lost"] == %{
             "id" => "ops-conn-lost",
             "class" => "hidden h-2 w-2 rounded-full bg-error motion-safe:animate-pulse",
             "title" => "Connection lost",
             "attrs" => %{
               "phx-disconnected" => ~s([["show",{}]]),
               "phx-connected" => ~s([["hide",{}]])
             }
           }
  end

  test "account children are absent unless current_scope has a user" do
    assert render_status_bar(current_scope: nil).props["presentation"]["account"] == nil

    assert render_status_bar(current_scope: %{user: nil}).props["presentation"]["account"] ==
             nil

    assert render_status_bar(current_scope: %{user: false}).props["presentation"]["account"] ==
             nil
  end

  test "authenticated account composes the shared notification and user-menu DTOs exactly" do
    user = %{email: "operator@example.com", display_name: "Mission Operator"}
    current_org = %{organization_id: "org-current", display_name: "Current Org"}
    other_org = %{organization_id: "org-other", display_name: "Other Org"}
    current_scope = scope(user, current_org)

    notification = %{
      notification_id: "notification-1",
      title: "Contact ready",
      body: "Pass AOS in 5 minutes",
      read_at: nil
    }

    account =
      render_status_bar(
        current_scope: current_scope,
        unread_count: 12,
        notifications: [notification],
        memberships: [
          %{membership: %{}, organization: current_org},
          %{membership: %{}, organization: other_org}
        ],
        platform_admin?: true
      ).props["presentation"]["account"]

    notifications_bell = account["notifications_bell"]
    notifications = notifications_bell["presentation"]

    assert notifications_bell["component"] == "NotificationsBell"
    assert notifications_bell["id"] == "notifications-bell-ops"
    assert notifications_bell["class"] == "contents"
    assert notifications["trigger"]["attrs"]["aria-controls"] == "notifications-bell-ops-menu"
    assert notifications["trigger"]["attrs"]["data-dropdown-trigger"] == ""
    assert notifications["trigger"]["badge"]["text"] == "9+"
    assert notifications["menu"]["title"]["unread_label"] == "(12 unread)"

    assert notifications["menu"]["notifications"] |> hd() |> get_in(["title", "text"]) ==
             "Contact ready"

    assert notifications["menu"]["footer"]["attrs"] == %{
             "href" => "/notifications",
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push"
           }

    user_menu = account["user_menu"]
    menu = user_menu["presentation"]["menu"]
    switch_org = menu["organization"]["switcher"]["organizations"] |> hd()
    switch_fields = hidden_fields(switch_org["form"])
    sign_out_fields = hidden_fields(menu["sign_out"])

    assert user_menu["component"] == "UserMenu"
    assert user_menu["id"] == "user-menu-ops"
    assert user_menu["class"] == "contents"
    assert user_menu["presentation"]["trigger"]["label"]["text"] == "Mission Operator"
    assert menu["admin_action"]["attrs"]["href"] == "/admin-mode"
    assert menu["admin_action"]["attrs"]["data-phx-link"] == "redirect"

    assert switch_org["form"]["attrs"] == %{
             "action" => "/session/organization",
             "method" => "post"
           }

    assert switch_fields["_method"]["value"] == "put"
    assert switch_fields["organization_id"]["value"] == "org-other"
    assert is_binary(switch_fields["_csrf_token"]["value"])
    assert switch_fields["_csrf_token"]["value"] != ""
    assert menu["sign_out"]["attrs"] == %{"action" => "/session", "method" => "post"}
    assert sign_out_fields["_method"]["value"] == "delete"
    assert is_binary(sign_out_fields["_csrf_token"]["value"])
    assert sign_out_fields["_csrf_token"]["value"] != ""
    assert account == Jason.decode!(Jason.encode!(account))
  end
end
