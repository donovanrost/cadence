defmodule CadenceWeb.OpsDashboardShowLive.SelectionPanelDataLinkContextTest do
  use Cadence.DataCase, async: false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.{DataLink, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery
  alias Phoenix.LiveView.Socket

  test "hydrate_selection_from_query preserves outcomes scoped to the same selection" do
    link = data_link()

    query =
      SelectionQuery.new(%{
        "selected_link" => link.link_id,
        "selected_target" => "telemetry_point",
        "selected_id" => "HK.counter",
        "realm" => "flight"
      })

    outcome = %{action: :stage_transition, target_event_id: "event-1"}

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_selection_query: query,
        data_link_action_outcome: outcome,
        data_link_action_outcome_query: SelectionQuery.to_params(query),
        dashboard_engine_result: %{
          frames_by_placement: %{
            "placement-1" =>
              PlacementFrames.new(%{
                primary: [
                  Frame.new(%{
                    source: :telemetry,
                    shape: :scalar,
                    meta: %{links: [link]}
                  })
                ]
              })
          }
        },
        dashboard_time_mode: "live",
        dashboard_time_context: %{"mode" => "live"},
        dashboard_data_realm: "flight"
      })

    socket = SelectionPanel.hydrate_selection_from_query(socket, [])

    assert {:data_link, _inspector} = socket.assigns.panel
    assert socket.assigns.data_link_action_outcome == outcome
  end

  test "hydrate_selection_from_query resolves copied selected-link URLs after frames arrive" do
    link = data_link()

    query =
      SelectionQuery.new(%{
        "selected_link" => link.link_id,
        "selected_placement" => "placement-1",
        "selected_time" => 1_781_697_600_000,
        "time_mode" => "live",
        "time_axis" => "generation_time",
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "source_binding_id" => "binding-flight"
      })

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_selection_query: query,
        dashboard_engine_result: %{frames_by_placement: %{}},
        dashboard_time_mode: "live",
        dashboard_time_context: %{"mode" => "live", "axis" => "generation_time"},
        dashboard_data_realm: "flight",
        dashboard_data_source_id: "questdb-flight",
        dashboard_source_binding_id: "binding-flight",
        dashboard_data_context: %{
          "realm" => "flight",
          "data_source_id" => "questdb-flight",
          "source_binding_id" => "binding-flight"
        }
      })

    missing_socket = SelectionPanel.hydrate_selection_from_query(socket, [])

    assert {:data_link, missing_inspector} = missing_socket.assigns.panel
    assert missing_inspector.status == :missing
    assert missing_inspector.link_id == link.link_id
    assert missing_socket.assigns.dashboard_selected_data_ref == nil
    assert missing_socket.assigns.dashboard_selection_state == "query_only"

    hydrated_socket =
      missing_socket
      |> assign(:dashboard_engine_result, %{
        frames_by_placement: %{
          "placement-1" =>
            PlacementFrames.new(%{
              primary: [
                Frame.new(%{
                  source: :telemetry,
                  shape: :scalar,
                  meta: %{links: [link]}
                })
              ]
            })
        }
      })
      |> SelectionPanel.hydrate_selection_from_query([])

    assert {:data_link, inspector} = hydrated_socket.assigns.panel
    assert inspector.status == :context_only
    assert hydrated_socket.assigns.dashboard_selection_state == "active"

    assert hydrated_socket.assigns.dashboard_selected_data_ref == %{
             "link_id" => link.link_id,
             "target" => "telemetry_point",
             "target_id" => "HK.counter",
             "target_text" => "telemetry point",
             "timestamp_ms" => 1_781_697_600_000,
             "placement_id" => "placement-1",
             "source" => "frame",
             "scope_kind" => "spacecraft",
             "scope_id" => "sc-1",
             "spacecraft_id" => "sc-1",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "limit_mode" => "observed",
             "observable_id" => "HK.counter"
           }
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            panel: nil,
            dashboard_selected_data_ref: nil,
            dashboard_selection_query: nil,
            dashboard_selection_state: "none",
            dashboard_evidence_query: nil,
            dashboard_engine_result: nil,
            dashboard_engine_frames_by_placement: nil,
            dashboard_data_realms: [],
            dashboard_data_bindings: [],
            dashboard_document: nil,
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"},
            context_scope_kind: nil,
            context_scope_id: nil,
            context_spacecraft_id: nil,
            dashboard_scope_context: %{},
            dashboard_time_mode: "live",
            dashboard_time_from: nil,
            dashboard_time_to: nil,
            dashboard_replay_run_id: nil,
            dashboard_time_context: %{},
            dashboard_data_realm: nil,
            dashboard_data_view: nil,
            dashboard_compare_data_view: nil,
            dashboard_data_source_id: nil,
            dashboard_source_binding_id: nil,
            dashboard_data_context: %{},
            dashboard_limit_mode: nil,
            dashboard_limit_context: %{},
            data_link_action_outcome: nil,
            data_link_action_outcome_query: nil
          },
          assigns
        )
    }
  end

  defp data_link do
    %DataLink{
      link_id: "telemetry_point:HK.counter:request-1",
      label: "Telemetry point",
      target: :telemetry_point,
      target_id: "HK.counter",
      source: :frame,
      context: %{
        organization_id: "org-1",
        mission_id: "mission-1",
        source_request_id: "request-1",
        logical_source: :telemetry,
        observable_id: "HK.counter",
        scope: %{
          primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
        },
        time: %{mode: "live", axis: "generation_time"},
        data: %{
          realm: "flight",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        limit: %{semantics_mode: "observed"}
      }
    }
  end
end
