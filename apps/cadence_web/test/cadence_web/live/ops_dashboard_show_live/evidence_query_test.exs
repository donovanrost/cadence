defmodule CadenceWeb.OpsDashboardShowLive.EvidenceQueryTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery

  describe "route params" do
    test "requires evidence kind for URL-restored evidence queries" do
      query =
        EvidenceQuery.from_params(
          %{
            "selected_evidence_kind" => " source ",
            "selected_cache_evidence_status" => " hit ",
            "selected_requested_source_binding" => " binding-1 "
          },
          :evidence
        )

      assert %EvidenceQuery{} = query

      assert EvidenceQuery.to_params(query) == %{
               "selected_evidence_kind" => "source",
               "selected_cache_evidence_status" => "hit",
               "selected_requested_source_binding" => "binding-1"
             }

      assert is_nil(
               EvidenceQuery.from_params(
                 %{"selected_cache_evidence_status" => "hit"},
                 :evidence
               )
             )
    end

    test "does not parse evidence while data-link panel is active" do
      assert is_nil(
               EvidenceQuery.from_params(
                 %{"selected_evidence_kind" => "source"},
                 :data_link
               )
             )
    end

    test "does not parse evidence while versions panel is active" do
      assert is_nil(
               EvidenceQuery.from_params(
                 %{
                   "panel" => "versions",
                   "selected_evidence_kind" => "source",
                   "selected_cache_evidence_status" => "hit"
                 },
                 :versions
               )
             )
    end
  end

  describe "event params" do
    test "round trips all source and cache evidence fields through query params" do
      event_params = %{
        "kind" => "source",
        "placement-id" => "placement-1",
        "observable-id" => "HK.counter",
        "warning-code" => "late_sample",
        "revision-state" => "corrected",
        "dependency-fingerprint" => "telemetry-revision:abc123",
        "source-evidence-mode" => "health",
        "source-evidence-state" => "context_only",
        "source-capability-status" => "fallback",
        "cache-evidence-layer" => "source",
        "cache-evidence-status" => "hit",
        "cache-evidence-reasons" => "operator_requested",
        "source-request-id" => "request-1",
        "logical-source" => "telemetry",
        "realm" => "flight",
        "data-source-id" => "managed_questdb_primary",
        "source-binding-id" => "default_flight_telemetry",
        "time-mode" => "live",
        "time-axis" => "observed_at",
        "requested-time-axis" => "generation_time",
        "executed-time-axis" => "receipt_time",
        "supported-time-axes" => "receipt_time",
        "requested-sampling" => "latest",
        "supported-sampling" => "latest",
        "requested-products" => "link_rf_metric_history",
        "supported-products" => "operational_metric_history",
        "source-capability-fallbacks" =>
          "time_axis:generation_time:receipt_time:unsupported_time_axis",
        "source-capability-unsupported" => "generation_time",
        "replay-run-id" => "replay-1",
        "scope-kind" => "contact",
        "scope-id" => "spacecraft-1",
        "contact-id" => "contact-1",
        "source-endpoint-id" => "endpoint-1",
        "source-empty-reason" => "contact_scope_no_data",
        "requested-realm" => "flight",
        "requested-data-view" => "canonical",
        "requested-data-source-id" => "managed_questdb_primary",
        "requested-source-binding-id" => "default_flight_telemetry",
        "requested-dataset" => "latest",
        "requested-validity-state" => "valid"
      }

      query = EvidenceQuery.from_event_params(event_params)

      assert %EvidenceQuery{} = query

      assert EvidenceQuery.to_params(query) == %{
               "selected_evidence_kind" => "source",
               "selected_placement" => "placement-1",
               "selected_observable" => "HK.counter",
               "selected_warning_code" => "late_sample",
               "selected_revision_state" => "corrected",
               "selected_dependency_fingerprint" => "telemetry-revision:abc123",
               "selected_source_evidence_mode" => "health",
               "selected_source_evidence_state" => "context_only",
               "selected_source_capability_status" => "fallback",
               "selected_cache_evidence_layer" => "source",
               "selected_cache_evidence_status" => "hit",
               "selected_cache_evidence_reasons" => "operator_requested",
               "selected_source_request" => "request-1",
               "selected_logical_source" => "telemetry",
               "selected_realm" => "flight",
               "selected_data_source" => "managed_questdb_primary",
               "selected_source_binding" => "default_flight_telemetry",
               "selected_time_mode" => "live",
               "selected_time_axis" => "observed_at",
               "selected_requested_time_axis" => "generation_time",
               "selected_executed_time_axis" => "receipt_time",
               "selected_supported_time_axes" => "receipt_time",
               "selected_requested_sampling" => "latest",
               "selected_supported_sampling" => "latest",
               "selected_requested_products" => "link_rf_metric_history",
               "selected_supported_products" => "operational_metric_history",
               "selected_source_capability_fallbacks" =>
                 "time_axis:generation_time:receipt_time:unsupported_time_axis",
               "selected_source_capability_unsupported" => "generation_time",
               "selected_replay_run_id" => "replay-1",
               "selected_scope_kind" => "contact",
               "selected_scope_id" => "spacecraft-1",
               "selected_contact_id" => "contact-1",
               "selected_source_endpoint_id" => "endpoint-1",
               "selected_source_empty_reason" => "contact_scope_no_data",
               "selected_requested_realm" => "flight",
               "selected_requested_data_view" => "canonical",
               "selected_requested_data_source" => "managed_questdb_primary",
               "selected_requested_source_binding" => "default_flight_telemetry",
               "selected_requested_dataset" => "latest",
               "selected_requested_validity_state" => "valid"
             }

      assert EvidenceQuery.to_event_params(query) == event_params
    end

    test "projects supported event params into phx value attributes" do
      assert EvidenceQuery.phx_value_attrs(%{
               "kind" => "source",
               "source-request-id" => "request-1",
               "logical-source" => "",
               "unsupported" => "ignored"
             }) == %{
               "phx-value-kind" => "source",
               "phx-value-source-request-id" => "request-1"
             }
    end

    test "round trips widget query evidence fields" do
      event_params = %{
        "kind" => "query",
        "placement-id" => "placement-1",
        "widget-title" => "Counter Trend",
        "requested-data-view" => "all_revisions",
        "compare-data-view" => "canonical",
        "binding-source" => "telemetry",
        "binding-mode" => "fixed",
        "observables" => "HK.counter",
        "sampling" => "latest",
        "window-seconds" => "300",
        "source-evidence-state" => "stale",
        "data-state" => "no_data",
        "source-request-id" => "source-req-1",
        "logical-source" => "telemetry",
        "realm" => "flight",
        "data-source-id" => "questdb-flight",
        "source-binding-id" => "binding-flight",
        "time-mode" => "live",
        "time-axis" => "receipt_time",
        "scope-kind" => "spacecraft",
        "scope-id" => "spacecraft-1",
        "contact-id" => "contact-1",
        "source-endpoint-id" => "endpoint-1",
        "source-empty-reason" => "contact_scope_no_data",
        "widget-warning-codes" => "stale_data"
      }

      query = EvidenceQuery.from_event_params(event_params)

      assert EvidenceQuery.to_params(query) == %{
               "selected_evidence_kind" => "query",
               "selected_placement" => "placement-1",
               "selected_widget_title" => "Counter Trend",
               "selected_requested_data_view" => "all_revisions",
               "selected_compare_data_view" => "canonical",
               "selected_binding_source" => "telemetry",
               "selected_binding_mode" => "fixed",
               "selected_observables" => "HK.counter",
               "selected_sampling" => "latest",
               "selected_window_seconds" => "300",
               "selected_source_evidence_state" => "stale",
               "selected_widget_data_state" => "no_data",
               "selected_source_request" => "source-req-1",
               "selected_logical_source" => "telemetry",
               "selected_realm" => "flight",
               "selected_data_source" => "questdb-flight",
               "selected_source_binding" => "binding-flight",
               "selected_time_mode" => "live",
               "selected_time_axis" => "receipt_time",
               "selected_scope_kind" => "spacecraft",
               "selected_scope_id" => "spacecraft-1",
               "selected_contact_id" => "contact-1",
               "selected_source_endpoint_id" => "endpoint-1",
               "selected_source_empty_reason" => "contact_scope_no_data",
               "selected_widget_warning_codes" => "stale_data"
             }

      assert EvidenceQuery.to_event_params(query) == event_params
    end

    test "infers source endpoint evidence identity from source-endpoint scoped query evidence" do
      query =
        EvidenceQuery.from_event_params(%{
          "kind" => "query",
          "widget-title" => "Ingress Latency History",
          "scope-kind" => "source_endpoint",
          "scope-id" => "endpoint-alpha",
          "scope-ids" => "endpoint-alpha,endpoint-beta",
          "source-endpoint-id" => "nil"
        })

      assert EvidenceQuery.to_params(query) == %{
               "selected_evidence_kind" => "query",
               "selected_widget_title" => "Ingress Latency History",
               "selected_scope_kind" => "source_endpoint",
               "selected_scope_id" => "endpoint-alpha",
               "selected_scope_ids" => "endpoint-alpha,endpoint-beta",
               "selected_source_endpoint_id" => "endpoint-alpha"
             }
    end

    test "round trips dashboard health evidence fields" do
      event_params = %{
        "kind" => "dashboard_health",
        "dashboard-health-schema" => "dashboard_health_snapshot.v1",
        "dashboard-health-snapshot-id" => "dashboard_health_snapshot_abc123",
        "dashboard-health-state" => "blocked",
        "dashboard-health-severity" => "error",
        "dashboard-health-widgets" => "4",
        "dashboard-health-ready" => "1",
        "dashboard-health-degraded" => "1",
        "dashboard-health-stale" => "1",
        "dashboard-health-blocked" => "1",
        "dashboard-health-affected" => "3",
        "dashboard-health-states" => "ready,degraded,stale,blocked",
        "dashboard-health-affected-placements" =>
          "degraded-placement,stale-placement,blocked-placement",
        "dashboard-health-blocked-placements" => "blocked-placement",
        "dashboard-health-stale-placements" => "stale-placement",
        "dashboard-health-degraded-placements" => "degraded-placement"
      }

      query = EvidenceQuery.from_event_params(event_params)

      assert EvidenceQuery.to_params(query) == %{
               "selected_evidence_kind" => "dashboard_health",
               "selected_dashboard_health_schema" => "dashboard_health_snapshot.v1",
               "selected_dashboard_health_snapshot_id" => "dashboard_health_snapshot_abc123",
               "selected_dashboard_health_state" => "blocked",
               "selected_dashboard_health_severity" => "error",
               "selected_dashboard_health_widgets" => "4",
               "selected_dashboard_health_ready" => "1",
               "selected_dashboard_health_degraded" => "1",
               "selected_dashboard_health_stale" => "1",
               "selected_dashboard_health_blocked" => "1",
               "selected_dashboard_health_affected" => "3",
               "selected_dashboard_health_states" => "ready,degraded,stale,blocked",
               "selected_dashboard_health_affected_placements" =>
                 "degraded-placement,stale-placement,blocked-placement",
               "selected_dashboard_health_blocked_placements" => "blocked-placement",
               "selected_dashboard_health_stale_placements" => "stale-placement",
               "selected_dashboard_health_degraded_placements" => "degraded-placement"
             }

      assert EvidenceQuery.to_event_params(query) == event_params
    end
  end

  describe "presentation rows" do
    test "uses the shared contract for missing evidence subject and detail rows" do
      query = %{
        "selected_evidence_kind" => "source",
        "selected_source_evidence_state" => "context_only",
        "selected_cache_evidence_status" => "hit",
        "selected_source_request" => "request-1",
        "selected_requested_data_view" => "canonical"
      }

      formatter = &to_string/1

      assert EvidenceQuery.subject(query) == "request-1"

      assert %{label: "Source evidence state", value: "context_only"} in EvidenceQuery.subject_rows(
               query,
               formatter
             )

      assert %{label: "Cache evidence status", value: "hit"} in EvidenceQuery.subject_rows(
               query,
               formatter
             )

      assert %{label: "Requested data view", value: "canonical"} in EvidenceQuery.detail_rows(
               query,
               formatter
             )
    end

    test "projects event params into source request detail rows" do
      params = %{
        "time-mode" => "live",
        "scope-kind" => "contact",
        "contact-id" => "contact-1",
        "source-endpoint-id" => "endpoint-1",
        "source-empty-reason" => "contact_scope_no_data",
        "source-evidence-state" => "context_only",
        "cache-evidence-status" => "hit",
        "source-capability-status" => "fallback",
        "requested-time-axis" => "generation_time",
        "executed-time-axis" => "receipt_time",
        "requested-products" => "link_rf_metric_history",
        "supported-products" => "operational_metric_history",
        "requested-source-binding-id" => "binding-flight"
      }

      assert EvidenceQuery.source_request_detail_rows(params, &to_string/1) == [
               %{label: "Time mode", value: "live"},
               %{label: "Scope kind", value: "contact"},
               %{label: "Contact", value: "contact-1"},
               %{label: "Source endpoint", value: "endpoint-1"},
               %{label: "Source empty reason", value: "contact_scope_no_data"},
               %{label: "Source evidence state", value: "context_only"},
               %{label: "Cache evidence status", value: "hit"},
               %{label: "Source capability status", value: "fallback"},
               %{label: "Requested time axis", value: "generation_time"},
               %{label: "Executed time axis", value: "receipt_time"},
               %{label: "Requested products", value: "link_rf_metric_history"},
               %{label: "Supported products", value: "operational_metric_history"},
               %{label: "Requested source binding", value: "binding-flight"}
             ]
    end

    test "detects source context-only evidence from event and query params" do
      event_params = %{
        "logical-source" => "telemetry",
        "cache-evidence-status" => "hit"
      }

      assert EvidenceQuery.source_context_event_query?(event_params)

      assert EvidenceQuery.source_context_event_query?(%{
               "logical-source" => "telemetry",
               "source-capability-status" => "fallback"
             })

      refute EvidenceQuery.source_context_event_query?(%{
               "logical-source" => "telemetry"
             })

      assert EvidenceQuery.source_context_query?(%{
               "selected_logical_source" => "telemetry",
               "selected_cache_evidence_status" => "hit"
             })

      assert EvidenceQuery.source_context_query?(%{
               "selected_logical_source" => "telemetry",
               "selected_source_capability_status" => "fallback"
             })

      refute EvidenceQuery.source_context_query?(%{
               "selected_cache_evidence_status" => "hit"
             })
    end

    test "projects source identity rows from event params and source summaries" do
      event_params = %{
        "logical-source" => "telemetry",
        "realm" => "flight",
        "source-request-id" => "request-1",
        "data-source-id" => "questdb-flight",
        "source-binding-id" => "binding-flight"
      }

      assert EvidenceQuery.source_subject_from_event_params(event_params) == "request-1"

      assert EvidenceQuery.source_identity_rows_from_event_params(event_params, &to_string/1) == [
               %{label: "Logical source", value: "telemetry"},
               %{label: "Realm", value: "flight"},
               %{label: "Source request", value: "request-1"},
               %{label: "Data source", value: "questdb-flight"},
               %{label: "Source binding", value: "binding-flight"}
             ]

      source_summary = %{
        logical_source: :telemetry,
        realm: :flight,
        state: :fresh,
        request_id: "request-1",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight"
      }

      assert EvidenceQuery.source_identity_rows_from_source(source_summary, &to_string/1) == [
               %{label: "Logical source", value: "telemetry"},
               %{label: "Realm", value: "flight"},
               %{label: "Freshness", value: "fresh"},
               %{label: "Source request", value: "request-1"},
               %{label: "Data source", value: "questdb-flight"},
               %{label: "Source binding", value: "binding-flight"}
             ]
    end

    test "clear query emits every selected evidence key with nil values" do
      clear_query = EvidenceQuery.clear_query()

      assert clear_query["selected_evidence_kind"] == nil
      assert clear_query["selected_cache_evidence_status"] == nil
      assert clear_query["selected_requested_validity_state"] == nil
      assert Enum.all?(clear_query, fn {_key, value} -> is_nil(value) end)
    end
  end
end
