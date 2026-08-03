defmodule CadenceWeb.OpsDashboardShowLive.RenderToolbarAssignsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{ComparisonReviewQueue, DataBinding, Document, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.RenderToolbarAssigns
  alias Phoenix.LiveView.Socket

  test "projects toolbar render context from sockets and assigns maps" do
    expected = %{
      dashboard_document: document(),
      dashboard_lifecycle_status: %{publish_available?: true},
      dashboard_lifecycle_events: [%{event_type: :comparison_review_requested}],
      dashboard_comparison_review_queue: %{count: 1, requests: [%{event_id: "review-1"}]},
      dashboard_publish_validation: nil,
      dashboard_publish_validation_freshness: nil,
      edit_mode?: true,
      editor_route?: false,
      editor_dirty?: false,
      editor_conflict: nil,
      dashboard_author?: false,
      show_context?: true,
      current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
      spacecraft: [%{spacecraft_id: "SC-1"}],
      source_endpoints: [%{source_endpoint_id: "endpoint-1"}],
      transports: [%{transport_id: "transport-1"}],
      ground_stations: [%{ground_station_id: "ground-1"}],
      link_assignments: [%{link_assignment_id: "link-1"}],
      scheduled_contacts: [%{scheduled_contact_id: "contact-scheduled-1"}],
      realized_contacts: [%{realized_contact_id: "contact-realized-1"}],
      context_spacecraft_id: "SC-1",
      context_scope_kind: "spacecraft",
      context_scope_id: "SC-1",
      context_scope_ids: ["SC-1"],
      time_mode: "archive",
      time_axis: nil,
      time_from: "2026-06-25T11:55:00Z",
      time_to: "2026-06-25T12:00:00Z",
      replay_run_id: "replay-1",
      time_validation: "valid",
      data_realm: "rehearsal",
      data_realms: ["flight", "rehearsal"],
      data_view: "raw",
      compare_data_view: "canonical",
      data_source_id: "questdb-rehearsal",
      source_binding_id: "rehearsal-binding",
      data_bindings: [data_binding()],
      replay_runs: [%{replay_run_id: "replay-1"}],
      limit_mode: "effective",
      limit_mode_fallback: %{
        "requested_mode" => "projected",
        "applied_mode" => "observed",
        "reason" => "unsupported_limit_semantics_mode"
      },
      hidden_marker_categories: [],
      selected_data_ref: selected_data_ref(),
      time_quick_query: "",
      time_recent_ranges: [],
      query: "temp"
    }

    assert RenderToolbarAssigns.toolbar_context(%Socket{assigns: assigns()}) == expected
    assert RenderToolbarAssigns.toolbar_context(assigns()) == expected
  end

  test "projects toolbar defaults" do
    assert RenderToolbarAssigns.toolbar_context(%{}) == %{
             dashboard_document: nil,
             dashboard_lifecycle_status: nil,
             dashboard_lifecycle_events: [],
             dashboard_comparison_review_queue: empty_review_queue(),
             dashboard_publish_validation: nil,
             dashboard_publish_validation_freshness: nil,
             edit_mode?: false,
             editor_route?: false,
             editor_dirty?: false,
             editor_conflict: nil,
             dashboard_author?: false,
             show_context?: false,
             current_mission: nil,
             spacecraft: [],
             source_endpoints: [],
             transports: [],
             ground_stations: [],
             link_assignments: [],
             scheduled_contacts: [],
             realized_contacts: [],
             context_spacecraft_id: nil,
             context_scope_kind: nil,
             context_scope_id: nil,
             context_scope_ids: [],
             time_mode: nil,
             time_axis: nil,
             time_from: nil,
             time_to: nil,
             replay_run_id: nil,
             time_validation: nil,
             data_realm: nil,
             data_realms: [],
             data_view: nil,
             compare_data_view: nil,
             data_source_id: nil,
             source_binding_id: nil,
             data_bindings: [],
             replay_runs: [],
             limit_mode: nil,
             limit_mode_fallback: nil,
             hidden_marker_categories: [],
             selected_data_ref: nil,
             time_quick_query: "",
             time_recent_ranges: [],
             query: ""
           }
  end

  defp assigns(overrides \\ %{}) do
    Map.merge(
      %{
        dashboard_document: document(),
        dashboard_lifecycle_status: %{publish_available?: true},
        dashboard_lifecycle_events: [%{event_type: :comparison_review_requested}],
        dashboard_comparison_review_queue: %{count: 1, requests: [%{event_id: "review-1"}]},
        dashboard_render_items: [render_item("placement-1")],
        dashboard_selected_data_ref: selected_data_ref(),
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        source_endpoints: [%{source_endpoint_id: "endpoint-1"}],
        transports: [%{transport_id: "transport-1"}],
        ground_stations: [%{ground_station_id: "ground-1"}],
        link_assignments: [%{link_assignment_id: "link-1"}],
        scheduled_contacts: [%{scheduled_contact_id: "contact-scheduled-1"}],
        realized_contacts: [%{realized_contact_id: "contact-realized-1"}],
        context_spacecraft_id: "SC-1",
        context_scope_kind: "spacecraft",
        context_scope_id: "SC-1",
        context_scope_ids: ["SC-1"],
        context_query: "temp",
        dashboard_time_mode: "archive",
        dashboard_time_from: "2026-06-25T11:55:00Z",
        dashboard_time_to: "2026-06-25T12:00:00Z",
        dashboard_replay_run_id: "replay-1",
        dashboard_time_validation: "valid",
        dashboard_data_realm: "rehearsal",
        dashboard_data_realms: ["flight", "rehearsal"],
        dashboard_data_view: "raw",
        dashboard_compare_data_view: "canonical",
        dashboard_data_source_id: "questdb-rehearsal",
        dashboard_source_binding_id: "rehearsal-binding",
        dashboard_data_bindings: [data_binding()],
        dashboard_replay_runs: [%{replay_run_id: "replay-1"}],
        dashboard_limit_mode: "effective",
        dashboard_limit_mode_fallback: %{
          "requested_mode" => "projected",
          "applied_mode" => "observed",
          "reason" => "unsupported_limit_semantics_mode"
        },
        edit_mode?: true,
        spacecraft: [%{spacecraft_id: "SC-1"}]
      },
      overrides
    )
  end

  defp document do
    %Document{dashboard_id: "dashboard-1"}
  end

  defp selected_data_ref do
    %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "source_binding_id" => "rehearsal-binding"
    }
  end

  defp render_item(placement_id) do
    %{
      placement_id: placement_id,
      widget: %RenderWidget{
        widget_id: "widget-1",
        type: :value_tile,
        title: "Temperature",
        binding: %{source: :telemetry, mode: :context}
      }
    }
  end

  defp data_binding do
    %DataBinding{
      binding_id: "rehearsal-binding",
      data_source_id: "questdb-rehearsal",
      dataset: "rehearsal",
      realm: :rehearsal,
      logical_source: :telemetry,
      priority: 0,
      status: :active
    }
  end

  defp empty_review_queue do
    ComparisonReviewQueue.open_summary([])
  end
end
