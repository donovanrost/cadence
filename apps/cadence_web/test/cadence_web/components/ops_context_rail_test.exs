defmodule CadenceWeb.Components.OpsContextRailTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.Components.OpsContextRail

  test "ops context rail emits stable section metadata and filters hidden sections" do
    html =
      render_component(&OpsContextRail.ops_context_rail/1,
        id: "test-context-rail",
        sections: [
          section("dashboard_health", "Dashboard health", :critical, 2),
          section("source_status", "Source status", :warning, 1),
          section("hidden", "Hidden", :info, 4, visible: false)
        ]
      )

    vue = LiveVue.Test.get_vue(html, id: "test-context-rail-component")
    sections = vue.props["sections"]

    assert vue.component == "OpsContextRail"

    assert vue.props["rail"]["storage_key"] == "cadence-ops-context-rail"

    assert vue.props["rail"]["default_expanded"] == false

    assert vue.props["rail"]["toggle_label"] == "Toggle context panel"

    assert Enum.map(sections, & &1["key"]) == ["dashboard_health", "source_status"]

    assert hd(sections)["status"] == "critical"

    assert hd(sections)["count"] == 2

    refute Enum.any?(sections, &(&1["key"] == "hidden"))
  end

  test "mission context rail derives fleet-health badge status and count" do
    html =
      render_component(&OpsContextRail.mission_context_rail/1,
        ops_context: %{
          mission_id: "mission-1",
          observed_at: ~U[2026-08-01 12:00:00Z],
          pinned_focus: nil,
          modules: [
            %{
              key: "fleet_health",
              title: "Fleet health",
              icon: "hero-rocket-launch",
              status: :warning,
              count: 3,
              freshness: :current,
              observed_at: ~U[2026-08-01 12:00:00Z],
              destination: "/missions/mission-1",
              data: %{
                normalized_state_counts: %{red: 0, yellow: 2, blue: 1, green: 8},
                violating_points: 3
              }
            }
          ]
        }
      )

    vue = LiveVue.Test.get_vue(html, id: "ops-context-rail-component")
    [section] = vue.props["sections"]

    assert section["key"] == "fleet_health"

    assert section["status"] == "warning"

    assert section["count"] == 3

    assert section["freshness"] == "current"

    assert section["destination"] == "/missions/mission-1"
  end

  test "mission context rail emits one non-SSR JSON-safe LiveVue host" do
    html =
      render_component(&OpsContextRail.mission_context_rail/1,
        ops_context: %{
          mission_id: "mission-1",
          observed_at: ~U[2026-08-01 12:00:00Z],
          pinned_focus: nil,
          modules: [
            context_module("alarms", "Alarms", "hero-bell-alert", :critical, 2),
            context_module("commands", "Commands", "hero-command-line", :warning, 1),
            fleet_health_module()
          ]
        }
      )

    vue = LiveVue.Test.get_vue(html, id: "ops-context-rail-component")
    [alarms, commands, fleet_health] = vue.props["sections"]

    assert vue.component == "OpsContextRail"
    assert vue.id == "ops-context-rail-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}

    assert Enum.map(vue.props["sections"], & &1["key"]) == [
             "alarms",
             "commands",
             "fleet_health"
           ]

    assert alarms["freshness_label"] == "Live"
    assert alarms["observed_at_label"] == "12:00:00 UTC"

    assert Enum.map(alarms["content"]["badges"], & &1["label"]) == [
             "Critical",
             "Warning",
             "Info"
           ]

    assert Enum.map(commands["content"]["counts"], & &1["label"]) == [
             "Queued",
             "Release pending",
             "In flight",
             "Failed"
           ]

    assert fleet_health["content"]["violating_points_label"] == "3 violating points"
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
  end

  defp section(key, title, status, count, opts \\ []) do
    %{
      key: key,
      title: title,
      icon: "hero-squares-2x2",
      status: status,
      count: count,
      visible: Keyword.get(opts, :visible, true),
      content: %{"kind" => "empty"}
    }
  end

  defp context_module(key, title, icon, status, count) do
    data =
      case key do
        "alarms" ->
          %{
            active_count: 2,
            critical_count: 1,
            warning_count: 1,
            info_count: 0,
            latest_transition_at: ~U[2026-08-01 11:59:00Z]
          }

        "commands" ->
          %{
            queued_count: 1,
            release_pending_count: 0,
            in_flight_count: 0,
            failed_count: 0,
            indeterminate_count: 0,
            followed_command: nil
          }
      end

    %{
      key: key,
      title: title,
      icon: icon,
      status: status,
      count: count,
      freshness: :current,
      observed_at: ~U[2026-08-01 12:00:00Z],
      destination: "/missions/mission-1/ops/#{key}",
      data: data
    }
  end

  defp fleet_health_module do
    %{
      key: "fleet_health",
      title: "Fleet health",
      icon: "hero-rocket-launch",
      status: :warning,
      count: 3,
      freshness: :current,
      observed_at: ~U[2026-08-01 12:00:00Z],
      destination: "/missions/mission-1",
      data: %{
        normalized_state_counts: %{red: 0, yellow: 2, blue: 1, green: 8},
        violating_points: 3
      }
    }
  end
end
