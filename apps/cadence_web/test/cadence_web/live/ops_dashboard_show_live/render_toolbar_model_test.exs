defmodule CadenceWeb.OpsDashboardShowLive.RenderToolbarModelTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document, RenderWidget, ValidationResult}

  alias Cadence.DataSources.DataBinding

  alias CadenceWeb.OpsDashboardShowLive.RenderToolbarModel

  test "props prepares toolbar render payload" do
    document = document()
    data_bindings = [data_binding()]
    selected_ref = selected_data_ref()
    replay_runs = [replay_run()]

    props =
      assigns(%{
        dashboard_document: document,
        dashboard_data_bindings: data_bindings,
        dashboard_replay_runs: replay_runs,
        dashboard_selected_data_ref: selected_ref
      })
      |> RenderToolbarModel.props()

    assert props.dashboard_document == document
    assert props.dashboard_lifecycle_status == %{publish_available?: true}
    assert props.dashboard_lifecycle_events == [%{event_type: :comparison_review_requested}]

    assert props.dashboard_comparison_review_queue == %{
             count: 1,
             requests: [%{event_id: "review-1"}]
           }

    assert props.dashboard_publish_readiness.status == "blocked"
    assert props.dashboard_publish_readiness.label == "blocked"
    assert props.edit_mode? == true
    assert props.show_context? == true
    assert props.current_mission == %{mission_id: "mission-1", display_name: "Lunar Demo"}
    assert props.spacecraft == [%{spacecraft_id: "SC-1"}]
    assert props.source_endpoints == [%{source_endpoint_id: "endpoint-1"}]
    assert props.transports == [%{transport_id: "transport-1"}]
    assert props.ground_stations == [%{ground_station_id: "ground-1"}]
    assert props.link_assignments == [%{link_assignment_id: "link-1"}]
    assert props.scheduled_contacts == [%{scheduled_contact_id: "contact-scheduled-1"}]
    assert props.realized_contacts == [%{realized_contact_id: "contact-realized-1"}]
    assert props.context_spacecraft_id == "SC-1"
    assert props.context_scope_kind == "spacecraft"
    assert props.context_scope_id == "SC-1"
    assert props.context_scope_ids == ["SC-1"]
    assert props.time_mode == "archive"
    assert props.time_axis == nil
    assert props.time_from == "2026-06-25T11:55:00Z"
    assert props.time_to == "2026-06-25T12:00:00Z"
    assert props.replay_run_id == "replay-1"
    assert props.time_validation == "ok"
    assert props.data_realm == "rehearsal"
    assert props.data_realms == ["flight", "rehearsal"]
    assert props.data_view == "raw"
    assert props.compare_data_view == "canonical"
    assert props.data_source_id == "questdb-rehearsal"
    assert props.source_binding_id == "rehearsal-binding"
    assert props.data_bindings == data_bindings
    assert props.replay_runs == replay_runs
    assert props.selected_replay_run == replay_run()
    assert props.limit_mode == "effective"

    assert props.limit_mode_fallback == %{
             "requested_mode" => "projected",
             "applied_mode" => "observed",
             "reason" => "unsupported_limit_semantics_mode"
           }

    assert props.selected_data_ref == selected_ref
    assert props.query == "sc"
  end

  test "props marks publish validation stale when freshness is stale" do
    props =
      assigns(%{
        dashboard_publish_validation_freshness: %{state: "stale"}
      })
      |> RenderToolbarModel.props()

    assert props.dashboard_publish_readiness.status == "stale"
    assert props.dashboard_publish_readiness.label == "needs re-check"
    assert props.dashboard_publish_readiness.freshness == %{state: "stale"}
  end

  test "props prepares toolbar defaults" do
    assert RenderToolbarModel.props(%{}) == %{
             dashboard_document: nil,
             dashboard_lifecycle_status: nil,
             dashboard_lifecycle_events: [],
             dashboard_comparison_review_queue: empty_review_queue(),
             dashboard_publish_readiness: nil,
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
             selected_replay_run: nil,
             limit_mode: nil,
             limit_mode_fallback: nil,
             hidden_marker_categories: [],
             selected_data_ref: nil,
             time_quick_query: "",
             time_recent_ranges: [],
             query: ""
           }
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        dashboard_document: document(),
        dashboard_lifecycle_status: %{publish_available?: true},
        dashboard_lifecycle_events: [%{event_type: :comparison_review_requested}],
        dashboard_comparison_review_queue: %{count: 1, requests: [%{event_id: "review-1"}]},
        dashboard_publish_validation: %ValidationResult{
          valid?: false,
          errors: [%{code: :invalid_grid, details: %{field: :columns}}]
        },
        edit_mode?: true,
        dashboard_render_items: [render_item("placement-1")],
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
        dashboard_time_mode: "archive",
        dashboard_time_from: "2026-06-25T11:55:00Z",
        dashboard_time_to: "2026-06-25T12:00:00Z",
        dashboard_replay_run_id: "replay-1",
        dashboard_time_validation: "ok",
        dashboard_data_realm: "rehearsal",
        dashboard_data_realms: ["flight", "rehearsal"],
        dashboard_data_view: "raw",
        dashboard_compare_data_view: "canonical",
        dashboard_data_source_id: "questdb-rehearsal",
        dashboard_source_binding_id: "rehearsal-binding",
        dashboard_data_bindings: [data_binding()],
        dashboard_replay_runs: [replay_run()],
        dashboard_limit_mode: "effective",
        dashboard_limit_mode_fallback: %{
          "requested_mode" => "projected",
          "applied_mode" => "observed",
          "reason" => "unsupported_limit_semantics_mode"
        },
        dashboard_selected_data_ref: selected_data_ref(),
        context_query: "sc"
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

  defp replay_run do
    %{
      replay_run_id: "replay-1",
      status: :completed,
      replayed_sample_count: 12,
      started_at: ~U[2026-06-25 11:58:00Z],
      completed_at: ~U[2026-06-25 12:01:00Z]
    }
  end

  defp empty_review_queue do
    ComparisonReviewQueue.open_summary([])
  end
end
