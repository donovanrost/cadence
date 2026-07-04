defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextPresentation

  test "build prepares selected context label and grouped resource search results" do
    presentation =
      sample_assigns()
      |> Map.merge(%{
        context_scope_kind: "contact",
        context_scope_id: "contact-realized-1",
        query: "alpha"
      })
      |> DashboardRuntimeContextPresentation.build()

    assert presentation.selected_label == "realized / contact-realized-1 / gs-alpha"
    assert [spacecraft] = presentation.spacecraft
    assert spacecraft.spacecraft_id == "spacecraft-1"

    assert [%{id: "contact-scheduled-1"}, %{id: "contact-realized-1"}] =
             presentation.contacts

    assert [%{id: "source-endpoint-alpha"}] = presentation.source_endpoints
    assert [%{id: "dss-14"}] = presentation.ground_stations
    assert [%{id: "transport-alpha"}] = presentation.transports
    assert [%{id: "link-alpha"}] = presentation.links
    refute Map.get(presentation, :no_matches?)
  end

  test "build exposes mission result and multi-select selected label" do
    presentation =
      sample_assigns()
      |> Map.merge(%{
        context_scope_kind: "source_endpoint",
        context_scope_id: "endpoint-alpha",
        context_scope_ids: ["endpoint-alpha", "endpoint-beta"],
        query: "lunar"
      })
      |> DashboardRuntimeContextPresentation.build()

    assert presentation.selected_label == "2 source endpoints"
    assert presentation.mission == %{id: "mission-1", label: "Lunar Demo"}
  end

  test "build marks empty search results" do
    presentation =
      sample_assigns()
      |> Map.put(:query, "no-match")
      |> DashboardRuntimeContextPresentation.build()

    assert Map.get(presentation, :no_matches?)
  end

  defp sample_assigns do
    %{
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
      context_scope_kind: nil,
      context_scope_id: nil,
      context_scope_ids: [],
      query: ""
    }
  end
end
