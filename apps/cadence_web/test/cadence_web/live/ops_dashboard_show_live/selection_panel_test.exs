defmodule CadenceWeb.OpsDashboardShowLive.SelectionPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.{EvidenceRef, Field, Frame, PlacementFrames}

  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel
  alias Phoenix.LiveView.Socket

  test "hydrates missing evidence from a query" do
    socket =
      socket(%{
        dashboard_engine_result: nil,
        dashboard_evidence_query: %{
          "selected_evidence_kind" => "frame",
          "selected_observable" => "HK.counter"
        }
      })

    socket = SelectionPanel.hydrate_evidence_from_query(socket)

    assert {:evidence, inspector} = socket.assigns.panel
    assert inspector.status == :missing
    assert inspector.kind == "frame"
    assert inspector.subject == "HK.counter"
  end

  test "open_evidence resolves frame interval evidence from dashboard engine result" do
    frame = %Frame{
      frame_id: "source-request-1:HK.counter",
      source: :telemetry,
      shape: :scalar,
      fields: [
        %Field{
          name: "HK.counter",
          kind: :number,
          values: [12.4],
          metadata: %{
            evidence: [
              %EvidenceRef{
                kind: :application_binding_interval,
                id: "application-binding-interval-1",
                source: :operational_event,
                confidence: :selected,
                observed_at: ~U[2026-06-21 20:30:00Z]
              }
            ]
          }
        }
      ],
      meta: %{
        observable_id: "HK.counter",
        evidence: [
          %EvidenceRef{
            kind: :source_binding_interval,
            id: "source-binding-interval-1",
            source: :telemetry,
            confidence: :selected,
            observed_at: ~U[2026-06-21 20:30:00Z]
          },
          %EvidenceRef{
            kind: :binding_set_interval,
            id: "binding-set-interval-1",
            source: :operational_event,
            confidence: :selected,
            observed_at: ~U[2026-06-21 20:30:00Z]
          }
        ],
        source_binding_interval: %{
          binding_id: "flight-telemetry",
          data_binding_event_id: "source-binding-event-1",
          data_source_id: "mission-questdb-v1",
          active_from: ~U[2026-06-21 20:00:00Z]
        }
      }
    }

    socket =
      socket(%{
        dashboard_engine_result: %{
          frames_by_placement: %{"placement-counter" => %PlacementFrames{primary: [frame]}}
        }
      })

    socket =
      SelectionPanel.open_evidence(
        socket,
        %{
          "kind" => "frame",
          "placement-id" => "placement-counter",
          "observable-id" => "HK.counter"
        },
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:evidence, inspector} = socket.assigns.panel
    assert inspector.kind == :frame
    assert inspector.subject == "source-request-1:HK.counter"

    assert %{
             kind_text: "source binding interval",
             source: :telemetry,
             confidence: :selected,
             observed_at_text: "2026-06-21T20:30:00Z"
           } =
             evidence_ref_summary(
               inspector.evidence,
               :source_binding_interval,
               "source-binding-interval-1"
             )

    assert %{
             kind_text: "binding set interval",
             source: :operational_event,
             confidence: :selected,
             observed_at_text: "2026-06-21T20:30:00Z"
           } =
             evidence_ref_summary(
               inspector.evidence,
               :binding_set_interval,
               "binding-set-interval-1"
             )

    assert %{
             kind_text: "application binding interval",
             source: :operational_event,
             confidence: :selected,
             observed_at_text: "2026-06-21T20:30:00Z"
           } =
             evidence_ref_summary(
               inspector.evidence,
               :application_binding_interval,
               "application-binding-interval-1"
             )

    assert %{value: "source-binding-event-1"} =
             Enum.find(inspector.detail_rows, &(&1.label == "Source binding interval"))

    assert socket.assigns.patched_query["panel"] == "evidence"
    assert socket.assigns.patched_query["selected_evidence_kind"] == "frame"
    assert socket.assigns.patched_query["selected_placement"] == "placement-counter"
    assert socket.assigns.patched_query["selected_observable"] == "HK.counter"
  end

  test "clears stale selected data while preserving the runtime query decision" do
    socket =
      socket(%{
        panel: {:data_link, %{status: :resolved}},
        data_link_action_outcome: %{action: :late_data_policy},
        dashboard_selected_data_ref: %{
          "target" => "telemetry_sample",
          "target_id" => "sample-1",
          "timestamp_ms" => 1_700_000_000_000,
          "realm" => "flight"
        },
        dashboard_selection_query: %{
          "selected_target" => "telemetry_sample",
          "selected_id" => "sample-1",
          "selected_time" => 1_700_000_000_000
        },
        dashboard_selection_state: "active",
        dashboard_evidence_query: nil
      })

    runtime_context = %{
      scope_kind: nil,
      scope_id: nil,
      spacecraft_id: nil,
      time_context: %{
        "mode" => "archive",
        "from" => DateTime.from_unix!(1_700_000_500, :second),
        "to" => DateTime.from_unix!(1_700_000_800, :second)
      },
      replay_run_id: nil,
      realm: "flight",
      data_view: nil,
      data_source_id: nil,
      source_binding_id: nil,
      limit_mode: nil,
      data_context: %{}
    }

    {socket, query} =
      SelectionPanel.stale_selection_checked_runtime_query(
        socket,
        %{"time_mode" => "archive"},
        runtime_context
      )

    assert socket.assigns.panel == nil
    assert socket.assigns.dashboard_selected_data_ref == nil
    assert socket.assigns.dashboard_selection_query == nil
    assert socket.assigns.dashboard_selection_state == "stale_context"
    assert socket.assigns.data_link_action_outcome == nil

    assert Map.take(query, ["selected_target", "selected_id", "selected_time"]) == %{
             "selected_target" => nil,
             "selected_id" => nil,
             "selected_time" => nil
           }
  end

  test "keeps selected data when it still matches runtime context" do
    selected_ref = %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "timestamp_ms" => 1_700_000_000_000,
      "realm" => "flight"
    }

    socket =
      socket(%{
        panel: {:data_link, %{status: :resolved}},
        dashboard_selected_data_ref: selected_ref,
        dashboard_selection_query: %{"selected_id" => "sample-1"},
        dashboard_selection_state: "active"
      })

    runtime_context = %{
      scope_kind: nil,
      scope_id: nil,
      spacecraft_id: nil,
      time_context: %{"mode" => "live"},
      replay_run_id: nil,
      realm: "flight",
      data_view: nil,
      data_source_id: nil,
      source_binding_id: nil,
      limit_mode: nil,
      data_context: %{}
    }

    {updated_socket, query} =
      SelectionPanel.stale_selection_checked_runtime_query(
        socket,
        %{"time_mode" => "live"},
        runtime_context
      )

    assert updated_socket.assigns.dashboard_selected_data_ref == selected_ref
    assert updated_socket.assigns.dashboard_selection_state == "active"
    assert query == %{"time_mode" => "live"}
  end

  test "extracts observable ids from atom-keyed and string-keyed selected refs" do
    assert SelectionPanel.selected_data_ref_observable_id(
             socket(%{dashboard_selected_data_ref: %{observable_id: "HK.counter"}})
           ) == "HK.counter"

    assert SelectionPanel.selected_data_ref_observable_id(
             socket(%{dashboard_selected_data_ref: %{"point_id" => "HK.voltage"}})
           ) == "HK.voltage"
  end

  test "data link index falls back to runtime result frames when cached assign is missing" do
    placement_frames = %PlacementFrames{}

    socket =
      socket(%{
        dashboard_engine_result: %{
          "frames_by_placement" => %{"placement-1" => placement_frames}
        },
        dashboard_engine_frames_by_placement: nil
      })

    assert SelectionPanel.data_link_index(socket).frames_by_placement == %{
             "placement-1" => placement_frames
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

  defp evidence_ref_summary(evidence, kind, id) do
    Enum.find(evidence, &(&1.kind == kind and &1.id == id))
  end
end
