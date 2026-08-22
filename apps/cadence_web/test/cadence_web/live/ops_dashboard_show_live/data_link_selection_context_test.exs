defmodule CadenceWeb.OpsDashboardShowLive.DataLinkSelectionContextTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DataLink
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection

  describe "synthetic links and context" do
    test "builds synthetic links from query params with compact context" do
      assert %DataLink{
               link_id: "direct:telemetry_point:HK.counter",
               label: "telemetry point",
               target: :telemetry_point,
               target_id: "HK.counter",
               context: %{
                 time: %{mode: "fixed", axis: "receipt_time", replay_run_id: "replay-1"},
                 data: %{realm: "backfill", replay_run_id: "replay-1"},
                 scope: %{
                   scope_kind: "contact",
                   scope_id: "contact-alpha",
                   contact_ids: ["contact-alpha", "contact-beta"]
                 },
                 selection: %{placement_id: "placement-1", timestamp_ms: 12_345}
               },
               presentation: :side_panel,
               source: :annotation
             } =
               DataLinkSelection.synthetic_link_from_query(%{
                 "selected_target" => "telemetry_point",
                 "selected_id" => "HK.counter",
                 "time_mode" => "fixed",
                 "time_axis" => "receipt_time",
                 "replay_run_id" => "replay-1",
                 "realm" => "backfill",
                 "selected_scope_kind" => "contact",
                 "selected_scope_id" => "contact-alpha",
                 "selected_contact_ids" => "contact-alpha,contact-beta",
                 "selected_placement" => "placement-1",
                 "selected_time" => 12_345
               })
    end

    test "builds source-watermark event synthetic links with source context" do
      assert %DataLink{
               link_id: "direct:source_watermark_event:watermark-event-1",
               label: "source watermark event",
               target: :source_watermark_event,
               target_id: "watermark-event-1",
               context: %{
                 time: %{mode: "archive", axis: "occurred_at", replay_run_id: "replay-1"},
                 data: %{
                   realm: "flight",
                   data_source_id: "events-projection",
                   source_binding_id: "events-binding",
                   replay_run_id: "replay-1"
                 },
                 selection: %{placement_id: "placement-1", timestamp_ms: 12_345}
               },
               presentation: :side_panel,
               source: :annotation
             } =
               DataLinkSelection.synthetic_link_from_query(%{
                 "selected_target" => "source_watermark_event",
                 "selected_id" => "watermark-event-1",
                 "time_mode" => "archive",
                 "time_axis" => "occurred_at",
                 "replay_run_id" => "replay-1",
                 "realm" => "flight",
                 "data_source_id" => "events-projection",
                 "source_binding_id" => "events-binding",
                 "selected_placement" => "placement-1",
                 "selected_time" => 12_345
               })
    end

    test "adds selection context and lets link context override runtime context" do
      link = %DataLink{
        target: :telemetry_point,
        target_id: "HK.counter",
        context: %{data: %{realm: "link-realm"}}
      }

      link =
        link
        |> DataLinkSelection.with_selection_context(%{
          "placement-id" => "placement-1",
          "timestamp-ms" => "12345",
          "series-role" => "compare",
          "compare-of" => "HK.counter",
          "time-mode" => "archive",
          "time-axis" => "receipt_time",
          "data-view" => "canonical",
          "comparison-state" => "increased",
          "comparison-delta" => "+2",
          "primary-data-management" => "recomputed_analysis",
          "compare-data-management" => "degraded"
        })
        |> DataLinkSelection.with_runtime_context(%{
          data: %{realm: "runtime-realm", view: "canonical"},
          limit: %{semantics_mode: "observed"}
        })

      assert link.context == %{
               data: %{realm: "link-realm", view: "canonical"},
               time: %{mode: "archive", axis: "receipt_time"},
               limit: %{semantics_mode: "observed"},
               selection: %{
                 placement_id: "placement-1",
                 timestamp_ms: 12_345,
                 series_role: "compare",
                 compare_of: "HK.counter"
               },
               comparison: %{
                 state: "increased",
                 delta: "+2",
                 primary_data_management: "recomputed_analysis",
                 compare_data_management: "degraded"
               }
             }
    end

    test "adds navigation breadcrumb context from related-link event params" do
      nav_trail =
        Jason.encode!([
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "dropped-event-1",
            "relationship_kind" => "source_event"
          },
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "previous-event-1",
            "label" => "Previous event",
            "relationship_kind" => "source_event"
          },
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "source-event-1",
            "label" => "Source event",
            "relationship_kind" => "retry_event"
          },
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "target-event-1",
            "label" => "Target event",
            "relationship_kind" => "correction_request",
            "realm" => "flight",
            "data_view" => "canonical",
            "data_source_id" => "questdb-flight",
            "source_binding_id" => "binding-flight",
            "time_mode" => "archive",
            "time_axis" => "receipt_time",
            "replay_run_id" => "replay-1"
          }
        ])

      link = %DataLink{
        link_id: "target-link-1",
        target: :telemetry_backfill_lifecycle_event,
        target_id: "target-event-1"
      }

      link =
        DataLinkSelection.with_selection_context(link, %{
          "nav-from-link-id" => "source-link-1",
          "nav-from-target" => "telemetry_backfill_lifecycle_event",
          "nav-from-target-id" => "source-event-1",
          "nav-from-label" => "Source event",
          "nav-from-relationship-kind" => "retry_event",
          "nav-from-relationship-label" => "Retry event HK.counter",
          "nav-trail" => nav_trail
        })

      assert link.context.navigation.from == %{
               link_id: "source-link-1",
               target: "telemetry_backfill_lifecycle_event",
               target_id: "source-event-1",
               label: "Source event",
               relationship_kind: "retry_event",
               relationship_label: "Retry event HK.counter"
             }

      assert [
               %{target_id: "previous-event-1"},
               %{target_id: "source-event-1"},
               %{
                 target_id: "target-event-1",
                 realm: "flight",
                 data_view: "canonical",
                 data_source_id: "questdb-flight",
                 source_binding_id: "binding-flight",
                 time_mode: "archive",
                 time_axis: "receipt_time",
                 replay_run_id: "replay-1"
               }
             ] = link.context.navigation.trail

      selected_ref = DataLinkSelection.selected_ref(link, %{})

      assert Map.drop(selected_ref, ["nav_trail"]) == %{
               "link_id" => "target-link-1",
               "target" => "telemetry_backfill_lifecycle_event",
               "target_id" => "target-event-1",
               "target_text" => "telemetry backfill lifecycle event",
               "source" => "field",
               "nav_from_link_id" => "source-link-1",
               "nav_from_target" => "telemetry_backfill_lifecycle_event",
               "nav_from_target_id" => "source-event-1",
               "nav_from_label" => "Source event",
               "nav_from_relationship_kind" => "retry_event",
               "nav_from_relationship_label" => "Retry event HK.counter"
             }

      assert [
               %{"target_id" => "previous-event-1"},
               %{"target_id" => "source-event-1"},
               %{
                 "target_id" => "target-event-1",
                 "realm" => "flight",
                 "data_view" => "canonical",
                 "data_source_id" => "questdb-flight",
                 "source_binding_id" => "binding-flight",
                 "time_mode" => "archive",
                 "time_axis" => "receipt_time",
                 "replay_run_id" => "replay-1"
               }
             ] = Jason.decode!(selected_ref["nav_trail"])
    end

    test "preserves explicit marker data context into selected refs" do
      link = %DataLink{
        link_id: "link-1",
        target: :telemetry_point,
        target_id: "HK.counter",
        source: :annotation,
        context: %{
          data: %{realm: "flight", view: "canonical", data_source_id: "runtime-source"},
          time: %{mode: "live", axis: "generation_time"}
        }
      }

      event_params = %{
        "placement-id" => "placement-1",
        "timestamp-ms" => "12345",
        "realm" => "replay",
        "data-view" => "all_revisions",
        "data-source-id" => "marker-source",
        "source-binding-id" => "marker-binding",
        "time-mode" => "replay_run",
        "time-axis" => "generation_time",
        "replay-run-id" => "replay-run-1"
      }

      selected_ref =
        link
        |> DataLinkSelection.with_selection_context(event_params)
        |> DataLinkSelection.with_runtime_context(%{
          data: %{realm: "flight", view: "canonical", data_source_id: "runtime-source"},
          time: %{mode: "live", axis: "generation_time"}
        })
        |> DataLinkSelection.selected_ref(event_params)

      assert selected_ref == %{
               "link_id" => "link-1",
               "target" => "telemetry_point",
               "target_id" => "HK.counter",
               "target_text" => "telemetry point",
               "timestamp_ms" => 12_345,
               "placement_id" => "placement-1",
               "source" => "annotation",
               "realm" => "replay",
               "time_mode" => "replay_run",
               "time_axis" => "generation_time",
               "data_view" => "all_revisions",
               "replay_run_id" => "replay-run-1",
               "data_source_id" => "marker-source",
               "source_binding_id" => "marker-binding"
             }
    end
  end
end
