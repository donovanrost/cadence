defmodule CadenceWeb.OpsDataSourcesLive.SourceFocusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDataSourcesLive.{
    SourceFocus,
    SourceFocusComponents
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

    document =
      render_component(&SourceFocusComponents.resource_panel/1,
        focus: focus,
        resources: resources,
        mission_id: "mission-1"
      )
      |> LazyHTML.from_fragment()

    assert resource_href(document, "transport_id") ==
             "/missions/mission-1/comms/transports/transport-1"

    assert resource_href(document, "source_endpoint_id") ==
             "/missions/mission-1/comms?source_endpoint_id=endpoint-1"

    assert resource_href(document, "ground_station_id") ==
             "/missions/mission-1/comms/ground-stations/station-1"

    assert resource_href(document, "link_id") ==
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

    document =
      render_component(&SourceFocusComponents.remediation_panel/1,
        focus: focus,
        data_sources: [],
        mission_id: "mission-1"
      )
      |> LazyHTML.from_fragment()

    assert ["open_register_source"] =
             document
             |> LazyHTML.query("#source-focus-register-source")
             |> LazyHTML.attribute("phx-click")

    return_link = LazyHTML.query(document, "#source-focus-dashboard-return")
    assert [href] = LazyHTML.attribute(return_link, "href")
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

    document =
      render_component(&SourceFocusComponents.evidence_panel/1,
        focus: focus,
        mission_id: "mission-1"
      )
      |> LazyHTML.from_fragment()

    assert ["stale"] =
             document
             |> LazyHTML.query("#source-focus-evidence")
             |> LazyHTML.attribute("data-source-evidence-state")

    return_link = LazyHTML.query(document, "#source-focus-evidence-dashboard-return")

    assert ["activity"] =
             LazyHTML.attribute(return_link, "data-source-focus-dashboard-return-panel")

    assert ["deployments"] =
             LazyHTML.attribute(return_link, "data-source-focus-dashboard-return-activity-filter")

    assert ["deployment-failed"] =
             LazyHTML.attribute(return_link, "data-source-focus-dashboard-return-activity-event")
  end

  defp resource_href(document, key) do
    document
    |> LazyHTML.query(~s([data-source-resource-link="#{key}"]))
    |> LazyHTML.attribute("href")
    |> List.first()
  end
end
