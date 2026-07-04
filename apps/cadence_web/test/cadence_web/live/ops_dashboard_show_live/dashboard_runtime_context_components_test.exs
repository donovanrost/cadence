defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponents

  test "context_selector exposes mission, spacecraft, contact, source, ground, transport, and link results" do
    html =
      render_component(&DashboardRuntimeContextComponents.context_selector/1,
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        spacecraft: [
          %{spacecraft_id: "spacecraft-1", display_name: "Alpha", scid: 101}
        ],
        source_endpoints: [
          %{
            source_endpoint_id: "source-endpoint-alpha",
            display_name: "Alpha Ground",
            source_ref: "gs-alpha",
            spacecraft_id: "spacecraft-1",
            metadata: %{"ground_station_id" => "dss-14"}
          }
        ],
        transports: [
          %{
            transport_id: "transport-alpha",
            display_name: "Alpha TCP",
            transport_kind: :tcp_socket,
            direction_capability: :bidirectional,
            configuration: %{
              "source_endpoint_id" => "source-endpoint-alpha",
              "ground_station_id" => "dss-14"
            }
          }
        ],
        ground_stations: [
          %{
            ground_station_id: "dss-14",
            display_name: "Alpha DSS-14",
            provider: "DSN",
            region: "goldstone"
          }
        ],
        link_assignments: [
          %{
            link_assignment_id: "link-alpha",
            spacecraft_id: "spacecraft-1",
            source_endpoint_ref: "gs-alpha",
            direction: :downlink,
            path_template_id: "path-alpha"
          }
        ],
        scheduled_contacts: [
          %{
            scheduled_contact_id: "contact-scheduled-1",
            source_endpoint_refs: ["gs-alpha"]
          }
        ],
        realized_contacts: [
          %{
            realized_contact_id: "contact-realized-1",
            scheduled_contact_id: "contact-scheduled-1",
            source_endpoint_refs: ["gs-alpha"]
          }
        ],
        context_spacecraft_id: nil,
        context_scope_kind: "contact",
        context_scope_id: "contact-realized-1",
        query: "alpha"
      )

    document = LazyHTML.from_fragment(html)

    assert html =~ "realized / contact-realized-1 / gs-alpha"

    assert ["spacecraft"] =
             document
             |> LazyHTML.query(~s(button[phx-value-scope-kind="spacecraft"]))
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["contact-scheduled-1"] =
             document
             |> LazyHTML.query(
               ~s(button[data-dashboard-context-contact-id="contact-scheduled-1"])
             )
             |> LazyHTML.attribute("phx-value-scope-id")

    assert ["contact-realized-1"] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-context-contact-kind="realized"]))
             |> LazyHTML.attribute("phx-value-scope-id")

    assert ["source_endpoint"] =
             document
             |> LazyHTML.query(
               ~s(button[data-dashboard-context-source-endpoint-id="source-endpoint-alpha"])
             )
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["ground_station"] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-context-ground-station-id="dss-14"]))
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert html =~ "Alpha DSS-14"

    assert ["transport"] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-context-transport-id="transport-alpha"]))
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["link"] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-context-link-id="link-alpha"]))
             |> LazyHTML.attribute("phx-value-scope-kind")
  end

  test "context_selector labels multi-select scope ids" do
    html =
      render_component(&DashboardRuntimeContextComponents.context_selector/1,
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        spacecraft: [],
        source_endpoints: [],
        transports: [],
        ground_stations: [],
        link_assignments: [],
        scheduled_contacts: [],
        realized_contacts: [],
        context_spacecraft_id: nil,
        context_scope_kind: "source_endpoint",
        context_scope_id: "endpoint-alpha",
        context_scope_ids: ["endpoint-alpha", "endpoint-beta"],
        query: ""
      )

    assert html =~ "2 source endpoints"
  end
end
