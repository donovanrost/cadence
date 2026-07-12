defmodule CadenceWeb.OpsDashboardShowLive.SelectionPanelDataLinkOpenTest do
  use Cadence.DataCase, async: false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.{DataBinding, DataLink, Document, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel
  alias Phoenix.LiveView.Socket

  test "open_data_link preserves resolved source context into selected refs and route query" do
    link = data_link()

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: document(),
        dashboard_data_realms: ["flight"],
        dashboard_data_bindings: [data_binding()],
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
        context_scope_kind: "spacecraft",
        context_scope_id: "sc-1",
        context_spacecraft_id: "sc-1",
        dashboard_scope_context: %{
          "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc-1"]}
        },
        dashboard_time_mode: "live",
        dashboard_time_context: %{"mode" => "live", "axis" => "generation_time"},
        dashboard_data_realm: "flight",
        dashboard_data_source_id: "questdb-flight",
        dashboard_source_binding_id: "binding-flight",
        dashboard_data_context: %{
          "realm" => "flight",
          "data_source_id" => "questdb-flight",
          "source_binding_id" => "binding-flight"
        },
        dashboard_limit_mode: "observed",
        dashboard_limit_context: %{"semantics_mode" => "observed"},
        data_link_action_outcome: %{action: :revision_decision}
      })

    socket =
      SelectionPanel.open_data_link(
        socket,
        link.link_id,
        %{
          "placement-id" => "placement-1",
          "timestamp-ms" => "1781697600000",
          "series-role" => "primary",
          "time-mode" => "archive",
          "time-axis" => "receipt_time"
        },
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.context_rows
    assert %{label: "Data source", value: "questdb-flight"} in inspector.context_rows
    assert %{label: "Source binding", value: "binding-flight"} in inspector.context_rows

    assert socket.assigns.dashboard_selection_state == "active"
    assert socket.assigns.data_link_action_outcome == nil

    assert socket.assigns.dashboard_selected_data_ref == %{
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
             "time_mode" => "archive",
             "time_axis" => "receipt_time",
             "series_role" => "primary",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "limit_mode" => "observed",
             "observable_id" => "HK.counter"
           }

    assert Map.take(socket.assigns.patched_query, [
             "panel",
             "selected_link",
             "selected_target",
             "selected_id",
             "selected_placement",
             "selected_time",
             "selected_series_role",
             "time_mode",
             "time_axis"
           ]) == %{
             "panel" => "data_link",
             "selected_link" => link.link_id,
             "selected_target" => "telemetry_point",
             "selected_id" => "HK.counter",
             "selected_placement" => "placement-1",
             "selected_time" => 1_781_697_600_000,
             "selected_series_role" => "primary",
             "time_mode" => "archive",
             "time_axis" => "receipt_time"
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

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
      defaults: %{
        "data" => %{
          "realm" => "flight",
          "source_contexts" => %{
            "telemetry" => %{"source_binding_id" => "binding-flight"}
          }
        }
      }
    }
  end

  defp data_binding do
    %DataBinding{
      binding_id: "binding-flight",
      logical_source: :telemetry,
      data_source_id: "questdb-flight",
      dataset: "flight",
      realm: :flight,
      priority: 0
    }
  end
end
