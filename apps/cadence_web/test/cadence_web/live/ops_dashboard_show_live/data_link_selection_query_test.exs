defmodule CadenceWeb.OpsDashboardShowLive.DataLinkSelectionQueryTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  describe "selection query parsing" do
    test "builds selection queries from URL params" do
      nav_trail =
        Jason.encode!([
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "previous-event-1",
            "relationship_kind" => "source_event"
          }
        ])

      query =
        DataLinkSelection.selection_query_from_params(
          %{
            "selected_link" => " link-1 ",
            "selected_target" => "telemetry_point",
            "selected_id" => "HK.counter",
            "selected_placement" => "placement-1",
            "selected_time" => "12345",
            "selected_data_view" => "canonical",
            "selected_series_role" => "compare",
            "selected_compare_of" => "HK.counter",
            "realm" => "rehearsal",
            "data_source_id" => "questdb-rehearsal",
            "source_binding_id" => "binding-1",
            "time_mode" => "archive",
            "time_axis" => "receipt_time",
            "replay_run_id" => "replay-1",
            "nav_from_link_id" => "source-link-1",
            "nav_from_target" => "telemetry_backfill_lifecycle_event",
            "nav_from_target_id" => "source-event-1",
            "nav_from_label" => "Source event",
            "nav_from_relationship_kind" => "retry_event",
            "nav_from_relationship_label" => "Retry event HK.counter",
            "nav_trail" => nav_trail
          },
          :data_link
        )

      assert %SelectionQuery{} = query

      assert SelectionQuery.to_params(query) == %{
               "selected_link" => "link-1",
               "selected_target" => "telemetry_point",
               "selected_id" => "HK.counter",
               "selected_placement" => "placement-1",
               "selected_time" => 12_345,
               "selected_data_view" => "canonical",
               "selected_series_role" => "compare",
               "selected_compare_of" => "HK.counter",
               "realm" => "rehearsal",
               "data_source_id" => "questdb-rehearsal",
               "source_binding_id" => "binding-1",
               "time_mode" => "archive",
               "time_axis" => "receipt_time",
               "replay_run_id" => "replay-1",
               "nav_from_link_id" => "source-link-1",
               "nav_from_target" => "telemetry_backfill_lifecycle_event",
               "nav_from_target_id" => "source-event-1",
               "nav_from_label" => "Source event",
               "nav_from_relationship_kind" => "retry_event",
               "nav_from_relationship_label" => "Retry event HK.counter",
               "nav_trail" => nav_trail
             }
    end

    test "drops invalid target-only queries without a link id" do
      assert is_nil(
               DataLinkSelection.selection_query_from_params(
                 %{"selected_target" => "not_a_resolvable_target", "selected_id" => "id-1"},
                 :data_link
               )
             )
    end

    test "does not parse data-link selection while evidence panel is active" do
      assert is_nil(
               DataLinkSelection.selection_query_from_params(
                 %{"selected_link" => "link-1"},
                 :evidence
               )
             )
    end

    test "does not parse data-link selection while versions panel is active" do
      assert DataLinkSelection.panel_from_params(%{"panel" => "versions"}) == :versions

      assert is_nil(
               DataLinkSelection.selection_query_from_params(
                 %{
                   "panel" => "versions",
                   "selected_link" => "link-1",
                   "selected_target" => "telemetry_sample",
                   "selected_id" => "sample-1"
                 },
                 :versions
               )
             )
    end

    test "round trips comparison source metadata through query and event params" do
      query =
        DataLinkSelection.selection_query_from_params(
          %{
            "selected_target" => "comparison_finding",
            "selected_id" => "placement-ops",
            "selected_widget" => "widget-ops",
            "selected_widget_title" => "Transport State",
            "selected_widget_type" => "status_matrix",
            "selected_widget_source" => "operational_observables",
            "selected_primary_kind" => "status_matrix",
            "selected_compare_kind" => "status_matrix",
            "selected_primary_observables" => "comms.transport.connection_state:transport-alpha",
            "selected_compare_observables" => "comms.transport.connection_state:transport-alpha",
            "selected_contact_ids" => "contact-alpha,contact-beta"
          },
          :data_link
        )

      assert %SelectionQuery{} = query

      assert SelectionQuery.to_params(query) == %{
               "selected_target" => "comparison_finding",
               "selected_id" => "placement-ops",
               "selected_widget" => "widget-ops",
               "selected_widget_title" => "Transport State",
               "selected_widget_type" => "status_matrix",
               "selected_widget_source" => "operational_observables",
               "selected_primary_kind" => "status_matrix",
               "selected_compare_kind" => "status_matrix",
               "selected_primary_observables" =>
                 "comms.transport.connection_state:transport-alpha",
               "selected_compare_observables" =>
                 "comms.transport.connection_state:transport-alpha",
               "selected_contact_ids" => "contact-alpha,contact-beta"
             }

      assert DataLinkSelection.event_params_from_selection_query(query) == %{
               "widget-id" => "widget-ops",
               "widget-title" => "Transport State",
               "widget-type" => "status_matrix",
               "widget-source" => "operational_observables",
               "primary-kind" => "status_matrix",
               "compare-kind" => "status_matrix",
               "primary-observables" => "comms.transport.connection_state:transport-alpha",
               "compare-observables" => "comms.transport.connection_state:transport-alpha",
               "contact-ids" => "contact-alpha,contact-beta"
             }
    end

    test "builds selection queries from selected refs" do
      nav_trail =
        Jason.encode!([
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "previous-event-1",
            "relationship_kind" => "source_event"
          }
        ])

      selected_ref = %{
        "link_id" => "link-1",
        "target" => "telemetry_point",
        "target_id" => "HK.counter",
        "placement_id" => "placement-1",
        "timestamp_ms" => 12_345,
        "data_view" => "canonical",
        "series_role" => "compare",
        "compare_of" => "HK.counter",
        "primary_data_management" => "recomputed_analysis",
        "compare_data_management" => "degraded",
        "contact_ids" => "contact-alpha,contact-beta",
        "realm" => "rehearsal",
        "data_source_id" => "questdb-rehearsal",
        "source_binding_id" => "binding-1",
        "time_mode" => "archive",
        "time_axis" => "receipt_time",
        "replay_run_id" => "replay-1",
        "nav_from_link_id" => "source-link-1",
        "nav_from_target" => "telemetry_backfill_lifecycle_event",
        "nav_from_target_id" => "source-event-1",
        "nav_from_label" => "Source event",
        "nav_from_relationship_kind" => "retry_event",
        "nav_from_relationship_label" => "Retry event HK.counter",
        "nav_trail" => nav_trail
      }

      query = DataLinkSelection.selection_query_from_ref(selected_ref)

      assert %SelectionQuery{} = query

      assert SelectionQuery.to_params(query) == %{
               "selected_link" => "link-1",
               "selected_target" => "telemetry_point",
               "selected_id" => "HK.counter",
               "selected_placement" => "placement-1",
               "selected_time" => 12_345,
               "selected_data_view" => "canonical",
               "selected_series_role" => "compare",
               "selected_compare_of" => "HK.counter",
               "selected_primary_data_management" => "recomputed_analysis",
               "selected_compare_data_management" => "degraded",
               "selected_contact_ids" => "contact-alpha,contact-beta",
               "realm" => "rehearsal",
               "data_source_id" => "questdb-rehearsal",
               "source_binding_id" => "binding-1",
               "time_mode" => "archive",
               "time_axis" => "receipt_time",
               "replay_run_id" => "replay-1",
               "nav_from_link_id" => "source-link-1",
               "nav_from_target" => "telemetry_backfill_lifecycle_event",
               "nav_from_target_id" => "source-event-1",
               "nav_from_label" => "Source event",
               "nav_from_relationship_kind" => "retry_event",
               "nav_from_relationship_label" => "Retry event HK.counter",
               "nav_trail" => nav_trail
             }
    end
  end
end
