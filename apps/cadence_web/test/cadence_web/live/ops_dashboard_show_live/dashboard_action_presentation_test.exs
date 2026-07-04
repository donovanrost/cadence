defmodule CadenceWeb.OpsDashboardShowLive.DashboardActionPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DashboardAction, Document}
  alias CadenceWeb.OpsDashboardShowLive.DashboardActionPresentation

  test "for_inspector hydrates evidence telemetry explore actions" do
    [action] =
      DashboardActionPresentation.for_inspector(
        %{actions: [telemetry_explore_action()]},
        "mission-1",
        :evidence_panel,
        dashboard_document()
      )

    uri = URI.parse(action.route)
    query = URI.decode_query(uri.query)

    assert action.action_id == "dashboard-evidence-explore"
    assert action.kind == :navigate
    assert action.source == :evidence_panel
    assert uri.path == "/missions/mission-1/ops/telemetry/explore"

    assert query == %{
             "point_id" => "HK.counter",
             "sample_id" => "sample-1",
             "source_dashboard_id" => "dashboard-1"
           }
  end

  test "for_inspector hydrates data-link telemetry explore actions" do
    [action] =
      DashboardActionPresentation.for_inspector(
        %{actions: [telemetry_explore_action()]},
        "mission-1",
        :data_link_panel,
        dashboard_document()
      )

    assert action.action_id == "dashboard-data-link-explore"
    assert action.source == :data_link_panel
  end

  test "for_inspector hydrates evidence source actions" do
    [action] =
      DashboardActionPresentation.for_inspector(
        %{actions: [source_inventory_action()]},
        "mission-1",
        :evidence_panel,
        dashboard_document()
      )

    uri = URI.parse(action.route)
    query = URI.decode_query(uri.query)

    assert action.action_id == "dashboard-evidence-source-inventory"
    assert action.kind == :navigate
    assert action.source == :evidence_panel
    assert uri.path == "/missions/mission-1/ops/data-sources"

    assert query == %{
             "realm" => "flight",
             "data_source_id" => "questdb-flight",
             "source_dashboard_id" => "dashboard-1"
           }
  end

  test "for_inspector keeps explicit source action dashboard return context" do
    [action] =
      DashboardActionPresentation.for_inspector(
        %{actions: [source_inventory_action(%{"source_dashboard_id" => "explicit-dashboard"})]},
        "mission-1",
        :evidence_panel,
        dashboard_document()
      )

    uri = URI.parse(action.route)
    query = URI.decode_query(uri.query)

    assert query["source_dashboard_id"] == "explicit-dashboard"
  end

  test "for_inspector hydrates operational data-link source actions" do
    [action] =
      DashboardActionPresentation.for_inspector(
        %{actions: [operational_source_inventory_action()]},
        "mission-1",
        :data_link_panel,
        dashboard_document()
      )

    uri = URI.parse(action.route)
    query = URI.decode_query(uri.query)

    assert action.action_id == "source-inventory"
    assert action.kind == :navigate
    assert action.source == :data_link_panel
    assert uri.path == "/missions/mission-1/ops/data-sources"

    assert query == %{
             "selected_target" => "transport",
             "selected_id" => "transport-alpha",
             "transport_id" => "transport-alpha",
             "source_endpoint_id" => "endpoint-alpha",
             "ground_station_id" => "dss-14",
             "link_id" => "link-alpha",
             "realm" => "flight",
             "data_source_id" => "managed-operational",
             "source_binding_id" => "ops-binding",
             "logical_source" => "operational_observables",
             "source_dashboard_id" => "dashboard-1"
           }
  end

  test "for_inspector hydrates routing rule setup actions" do
    [action] =
      DashboardActionPresentation.for_inspector(
        %{actions: [routing_rule_action()]},
        "mission-1",
        :data_link_panel,
        dashboard_document()
      )

    assert action.kind == :navigate
    assert action.source == :data_link_panel
    assert action.route == "/missions/mission-1/comms/routing/routing-rule-1"
  end

  test "for_inspector de-duplicates hydrated actions by rendered action id" do
    actions =
      DashboardActionPresentation.for_inspector(
        %{actions: [telemetry_explore_action(), telemetry_explore_action()]},
        "mission-1",
        :evidence_panel,
        dashboard_document()
      )

    assert [%DashboardAction{action_id: "dashboard-evidence-explore"}] = actions
  end

  test "visible returns only actions with concrete routes" do
    routed = %DashboardAction{
      action_id: "routed",
      label: "Routed",
      target: :command,
      kind: :navigate,
      route: "/ready"
    }

    missing_route = %DashboardAction{
      action_id: "missing-route",
      label: "Missing route",
      target: :command,
      kind: :invoke
    }

    assert DashboardActionPresentation.visible([routed, missing_route]) == [routed]
  end

  test "icon returns target-specific action icons" do
    assert DashboardActionPresentation.icon(%DashboardAction{
             target: :telemetry_explore,
             label: "Explore",
             kind: :navigate
           }) == "hero-chart-bar-square"

    assert DashboardActionPresentation.icon(%DashboardAction{
             target: :source_inventory,
             label: "Sources",
             kind: :navigate
           }) == "hero-circle-stack"

    assert DashboardActionPresentation.icon(%DashboardAction{
             target: :routing_rule,
             label: "Routing",
             kind: :navigate
           }) == "hero-signal"

    assert DashboardActionPresentation.icon(%DashboardAction{
             target: :command,
             label: "Command",
             kind: :navigate
           }) == "hero-arrow-top-right-on-square"
  end

  defp telemetry_explore_action do
    %DashboardAction{
      action_id: "explore",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{
        "point_id" => "HK.counter",
        "sample_id" => "sample-1",
        "empty" => nil
      },
      source: :frame
    }
  end

  defp source_inventory_action(extra_query \\ %{}) do
    %DashboardAction{
      action_id: "source-inventory",
      label: "Source inventory",
      target: :source_inventory,
      kind: :invoke,
      query:
        Map.merge(
          %{
            "realm" => "flight",
            "data_source_id" => "questdb-flight",
            "blank" => ""
          },
          extra_query
        ),
      source: :frame
    }
  end

  defp operational_source_inventory_action do
    %DashboardAction{
      action_id: "source-inventory",
      label: "View source inventory",
      target: :source_inventory,
      kind: :invoke,
      query: %{
        "selected_target" => "transport",
        "selected_id" => "transport-alpha",
        "transport_id" => "transport-alpha",
        "source_endpoint_id" => "endpoint-alpha",
        "ground_station_id" => "dss-14",
        "link_id" => "link-alpha",
        "realm" => "flight",
        "data_source_id" => "managed-operational",
        "source_binding_id" => "ops-binding",
        "logical_source" => "operational_observables"
      },
      source: :data_link_panel
    }
  end

  defp routing_rule_action do
    %DashboardAction{
      action_id: "dashboard-link-routing-rule",
      label: "View routing rule",
      target: :routing_rule,
      kind: :invoke,
      query: %{"routing_rule_id" => "routing-rule-1"},
      source: :data_link_panel
    }
  end

  defp dashboard_document do
    %Document{dashboard_id: "dashboard-1", mission_id: "mission-1", name: "Dashboard"}
  end
end
