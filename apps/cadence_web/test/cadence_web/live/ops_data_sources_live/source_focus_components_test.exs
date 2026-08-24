defmodule CadenceWeb.OpsDataSourcesLive.SourceFocusPageTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Phoenix.LiveView.JS

  alias CadenceWeb.OpsDataSourcesLive.{
    Page,
    SourceFocus
  }

  test "resource panel links resolved operational context to verified mission routes" do
    focus =
      SourceFocus.from_params(%{
        "selected_target" => "source_endpoint",
        "selected_id" => "endpoint-1",
        "transport_id" => "transport-1",
        "source_endpoint_id" => "endpoint-1",
        "ground_station_id" => "station-1",
        "link_id" => "link-1"
      })

    resources = %{
      transport: %{
        transport_id: "transport-1",
        display_name: "Primary UDP",
        transport_kind: :udp
      },
      source_endpoint: %{
        source_endpoint_id: "endpoint-1",
        display_name: "Goldstone ingress",
        source_ref: "provider/goldstone"
      },
      link_assignment: %{
        link_assignment_id: "link-1",
        spacecraft_id: "spacecraft-1",
        direction: :uplink
      },
      routing_rule: %{routing_rule_id: "routing-1"},
      ground_station: %{
        ground_station_id: "station-1",
        display_name: "Goldstone",
        status: :resolved
      }
    }

    page =
      focus
      |> render_ops_data_sources(source_focus_resources: resources)
      |> then(& &1.props["page"])

    assert resource_href(page, "transport_id") ==
             "/missions/mission-1/comms/transports/transport-1"

    assert resource_href(page, "source_endpoint_id") ==
             "/missions/mission-1/comms?source_endpoint_id=endpoint-1"

    assert resource_href(page, "ground_station_id") ==
             "/missions/mission-1/comms/ground-stations/station-1"

    assert resource_href(page, "link_id") ==
             "/missions/mission-1/comms/routing/routing-1"
  end

  test "remediation panel preserves dashboard return defaults" do
    focus =
      SourceFocus.from_params(%{
        "logical_source" => "telemetry",
        "realm" => "flight",
        "source_empty_reason" => "missing_source_binding",
        "source_dashboard_id" => "dashboard-1"
      })

    vue = render_ops_data_sources(focus, data_sources: [])
    remediation = vue.props["page"]["focus"]["remediation"]
    action = remediation["action"]

    assert action["id"] == "source-focus-register-source"
    assert action["event"] == "open_register_source"
    assert action["payload"] == %{}
    assert vue.handlers["open-register-source"] == JS.push("open_register_source")

    return_link = remediation["dashboard_return"]
    assert return_link["id"] == "source-focus-dashboard-return"
    href = return_link["href"]
    assert URI.parse(href).path == "/missions/mission-1/ops/dashboards/dashboard-1"

    assert URI.decode_query(URI.parse(href).query) == %{
             "activity_filter" => "publish_readiness",
             "panel" => "versions",
             "refresh_readiness" => "source_return"
           }
  end

  test "evidence panel renders selected evidence and explicit return activity" do
    focus =
      SourceFocus.from_params(%{
        "data_source_id" => "source-1",
        "source_empty_reason" => "stale_data",
        "selected_evidence_kind" => "source",
        "selected_source_evidence_mode" => "health",
        "selected_source_evidence_state" => "stale",
        "source_dashboard_id" => "dashboard-1",
        "source_return_panel" => "activity",
        "source_return_activity_filter" => "deployments",
        "source_return_activity_event" => "deployment-failed"
      })

    evidence =
      focus
      |> render_ops_data_sources()
      |> then(& &1.props["page"]["focus"]["evidence"])

    assert evidence["id"] == "source-focus-evidence"
    assert evidence["state"] == "stale"

    return_link = evidence["dashboard_return"]
    assert return_link["id"] == "source-focus-evidence-dashboard-return"
    assert return_link["panel"] == "activity"
    assert return_link["activity_filter"] == "deployments"
    assert return_link["activity_event"] == "deployment-failed"
  end

  defp render_ops_data_sources(focus, opts \\ []) do
    render_component(&Page.render/1,
      flash: %{},
      current_scope: %{capabilities: MapSet.new([:organization_admin])},
      current_mission: %{mission_id: "mission-1"},
      source_admin?: true,
      source_focus: focus,
      source_focus_resources:
        Keyword.get(opts, :source_focus_resources, %{
          transport: nil,
          source_endpoint: nil,
          link_assignment: nil,
          routing_rule: nil,
          ground_station: nil
        }),
      data_sources: Keyword.get(opts, :data_sources, []),
      data_bindings: [],
      source_health_statuses: [],
      source_readiness_policy: %{
        policy_id: "test-readiness-policy",
        block_source_health: "block",
        block_freshness: "block",
        block_connection_test: "ignore"
      },
      binding_groups: [],
      source_rows: [],
      deployment_run_rows: [],
      binding_event_rows: [],
      source_event_rows: [],
      source_health_event_rows: [],
      register_source?: false,
      change_binding: nil
    )
    |> LiveVue.Test.get_vue(id: "ops-data-sources-component")
  end

  defp resource_href(page, key) do
    page["focus"]["resource"]["rows"]
    |> Enum.find(&(&1["key"] == key))
    |> Map.fetch!("href")
  end
end
