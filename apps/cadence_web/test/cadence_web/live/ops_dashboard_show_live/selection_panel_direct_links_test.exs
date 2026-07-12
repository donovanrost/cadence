defmodule CadenceWeb.OpsDashboardShowLive.SelectionPanelDirectLinksTest do
  use Cadence.DataCase, async: false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.{DataBinding, DataLink, Document, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel
  alias Phoenix.LiveView.Socket

  test "open_data_link resolves direct source-watermark event links from event params" do
    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: document(),
        dashboard_data_realms: ["flight"],
        dashboard_data_bindings: [data_binding()],
        dashboard_engine_result: %{frames_by_placement: %{}},
        dashboard_time_mode: "archive",
        dashboard_time_context: %{"mode" => "archive", "axis" => "occurred_at"},
        dashboard_data_realm: "flight",
        dashboard_data_source_id: "events-projection",
        dashboard_source_binding_id: "events-binding",
        dashboard_data_context: %{
          "realm" => "flight",
          "data_source_id" => "events-projection",
          "source_binding_id" => "events-binding"
        }
      })

    socket =
      SelectionPanel.open_data_link(
        socket,
        "direct:source_watermark_event:watermark-event-1",
        %{
          "target" => "source_watermark_event",
          "target-id" => "watermark-event-1",
          "placement-id" => "data-management",
          "timestamp-ms" => "1781697600000",
          "time-mode" => "archive",
          "time-axis" => "occurred_at",
          "realm" => "flight",
          "data-source-id" => "events-projection",
          "source-binding-id" => "events-binding"
        },
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.target == :source_watermark_event
    assert inspector.target_id == "watermark-event-1"

    assert socket.assigns.dashboard_selected_data_ref == %{
             "link_id" => "direct:source_watermark_event:watermark-event-1",
             "target" => "source_watermark_event",
             "target_id" => "watermark-event-1",
             "target_text" => "source watermark event",
             "timestamp_ms" => 1_781_697_600_000,
             "placement_id" => "data-management",
             "source" => "annotation",
             "realm" => "flight",
             "time_mode" => "archive",
             "time_axis" => "occurred_at",
             "data_source_id" => "events-projection",
             "source_binding_id" => "events-binding"
           }

    assert Map.take(socket.assigns.patched_query, [
             "panel",
             "selected_link",
             "selected_target",
             "selected_id",
             "selected_placement",
             "selected_time",
             "time_mode",
             "time_axis",
             "realm",
             "data_source_id",
             "source_binding_id"
           ]) == %{
             "panel" => "data_link",
             "selected_link" => "direct:source_watermark_event:watermark-event-1",
             "selected_target" => "source_watermark_event",
             "selected_id" => "watermark-event-1",
             "selected_placement" => "data-management",
             "selected_time" => 1_781_697_600_000,
             "time_mode" => "archive",
             "time_axis" => "occurred_at",
             "realm" => "flight",
             "data_source_id" => "events-projection",
             "source_binding_id" => "events-binding"
           }
  end

  test "open_data_link opens operational resource links from chart point metadata" do
    link = %DataLink{
      link_id: "transport:transport-alpha:ops-request-1",
      label: "Transport",
      target: :transport,
      target_id: "transport-alpha",
      source: :frame,
      context: %{
        organization_id: "org-1",
        mission_id: "mission-1",
        source_request_id: "ops-request-1",
        logical_source: :operational_observables,
        observable_id: "link.snr_db",
        scope: %{primary: %{kind: "link", mode: "one", ids: ["link-alpha"]}},
        data: %{
          realm: "flight",
          data_source_id: "managed-operational",
          source_binding_id: "ops-binding"
        },
        operational_resource: %{
          resource_id: "link-alpha",
          scope_kind: :link,
          transport_id: "transport-alpha",
          source_endpoint_id: "endpoint-alpha",
          ground_station_id: "dss-14",
          link_id: "link-alpha",
          adapter_key: :rf_adapter
        }
      }
    }

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_engine_result: %{
          frames_by_placement: %{
            "placement-rf" =>
              PlacementFrames.new(%{
                primary: [
                  Frame.new(%{
                    source: :operational_observables,
                    shape: :wide,
                    meta: %{links: [link]}
                  })
                ]
              })
          }
        },
        dashboard_data_realm: "flight",
        dashboard_data_source_id: "managed-operational",
        dashboard_source_binding_id: "ops-binding",
        dashboard_data_context: %{
          "realm" => "flight",
          "data_source_id" => "managed-operational",
          "source_binding_id" => "ops-binding"
        }
      })

    socket =
      SelectionPanel.open_data_link(
        socket,
        link.link_id,
        %{
          "target" => "transport",
          "target-id" => "transport-alpha",
          "placement-id" => "placement-rf",
          "timestamp-ms" => "1781697720000",
          "series-role" => "primary",
          "time-mode" => "archive",
          "time-axis" => "occurred_at",
          "realm" => "flight",
          "data-source-id" => "managed-operational",
          "source-binding-id" => "ops-binding"
        },
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.target == :transport
    assert inspector.target_id == "transport-alpha"

    assert socket.assigns.dashboard_selected_data_ref == %{
             "link_id" => "transport:transport-alpha:ops-request-1",
             "target" => "transport",
             "target_id" => "transport-alpha",
             "target_text" => "transport",
             "timestamp_ms" => 1_781_697_720_000,
             "placement_id" => "placement-rf",
             "source" => "frame",
             "scope_kind" => "link",
             "scope_id" => "link-alpha",
             "realm" => "flight",
             "time_mode" => "archive",
             "time_axis" => "occurred_at",
             "series_role" => "primary",
             "data_source_id" => "managed-operational",
             "source_binding_id" => "ops-binding",
             "transport_id" => "transport-alpha",
             "source_endpoint_id" => "endpoint-alpha",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-alpha",
             "observable_id" => "link.snr_db"
           }

    assert Map.take(socket.assigns.patched_query, [
             "panel",
             "selected_link",
             "selected_target",
             "selected_id",
             "selected_placement",
             "selected_time",
             "selected_series_role",
             "selected_scope_kind",
             "selected_scope_id",
             "selected_transport_id",
             "selected_source_endpoint_id",
             "selected_ground_station_id",
             "selected_scope_link_id",
             "time_mode",
             "time_axis",
             "realm",
             "data_source_id",
             "source_binding_id"
           ]) == %{
             "panel" => "data_link",
             "selected_link" => "transport:transport-alpha:ops-request-1",
             "selected_target" => "transport",
             "selected_id" => "transport-alpha",
             "selected_placement" => "placement-rf",
             "selected_time" => 1_781_697_720_000,
             "selected_series_role" => "primary",
             "selected_scope_kind" => "link",
             "selected_scope_id" => "link-alpha",
             "selected_transport_id" => "transport-alpha",
             "selected_source_endpoint_id" => "endpoint-alpha",
             "selected_ground_station_id" => "dss-14",
             "selected_scope_link_id" => "link-alpha",
             "time_mode" => "archive",
             "time_axis" => "occurred_at",
             "realm" => "flight",
             "data_source_id" => "managed-operational",
             "source_binding_id" => "ops-binding"
           }
  end

  test "open_data_link preserves replay metric sample operational-event context from event params" do
    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_engine_result: %{frames_by_placement: %{}},
        dashboard_time_mode: "replay_run",
        dashboard_time_context: %{"mode" => "replay_run"},
        dashboard_data_realm: "replay",
        dashboard_data_source_id: "managed-operational-replay",
        dashboard_source_binding_id: "ops-replay-binding",
        dashboard_data_context: %{
          "realm" => "replay",
          "data_source_id" => "managed-operational-replay",
          "source_binding_id" => "ops-replay-binding",
          "replay_run_id" => "replay-run-1"
        },
        context_scope_kind: "link",
        context_scope_id: "link-alpha"
      })

    socket =
      SelectionPanel.open_data_link(
        socket,
        "metric-sample-operational-event:metric-sample-event-1",
        %{
          "link-id" => "metric-sample-operational-event:metric-sample-event-1",
          "target" => "operational_event",
          "target-id" => "metric-sample-event-1",
          "timestamp-ms" => "1781697840000",
          "realm" => "replay",
          "time-mode" => "replay_run",
          "replay-run-id" => "replay-run-1",
          "data-source-id" => "managed-operational-replay",
          "source-binding-id" => "ops-replay-binding",
          "scope-kind" => "link",
          "scope-id" => "link-alpha",
          "resource-id" => "link-alpha",
          "transport-id" => "transport-alpha",
          "scope-link-id" => "link-alpha"
        },
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.target == :operational_event
    assert inspector.target_id == "metric-sample-event-1"

    assert socket.assigns.dashboard_selected_data_ref == %{
             "link_id" => "direct:operational_event:metric-sample-event-1",
             "target" => "operational_event",
             "target_id" => "metric-sample-event-1",
             "target_text" => "operational event",
             "timestamp_ms" => 1_781_697_840_000,
             "source" => "annotation",
             "scope_kind" => "link",
             "scope_id" => "link-alpha",
             "resource_id" => "link-alpha",
             "realm" => "replay",
             "time_mode" => "replay_run",
             "replay_run_id" => "replay-run-1",
             "data_source_id" => "managed-operational-replay",
             "source_binding_id" => "ops-replay-binding",
             "transport_id" => "transport-alpha",
             "scope_link_id" => "link-alpha"
           }

    assert Map.take(socket.assigns.patched_query, [
             "panel",
             "selected_link",
             "selected_target",
             "selected_id",
             "selected_time",
             "selected_scope_kind",
             "selected_scope_id",
             "selected_resource_id",
             "selected_transport_id",
             "selected_scope_link_id",
             "time_mode",
             "realm",
             "replay_run_id",
             "data_source_id",
             "source_binding_id"
           ]) == %{
             "panel" => "data_link",
             "selected_link" => "direct:operational_event:metric-sample-event-1",
             "selected_target" => "operational_event",
             "selected_id" => "metric-sample-event-1",
             "selected_time" => 1_781_697_840_000,
             "selected_scope_kind" => "link",
             "selected_scope_id" => "link-alpha",
             "selected_resource_id" => "link-alpha",
             "selected_transport_id" => "transport-alpha",
             "selected_scope_link_id" => "link-alpha",
             "time_mode" => "replay_run",
             "realm" => "replay",
             "replay_run_id" => "replay-run-1",
             "data_source_id" => "managed-operational-replay",
             "source_binding_id" => "ops-replay-binding"
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
