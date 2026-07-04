defmodule CadenceWeb.OpsDashboardShowLive.EvidenceAttrsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.EvidenceAttrs

  describe "source evidence attrs" do
    test "builds source health attrs with normalized values" do
      assert EvidenceAttrs.source_health(%{
               request_id: "request-1",
               logical_source: :telemetry,
               realm: :flight,
               data_source_id: "questdb-flight",
               source_binding_id: "binding-flight",
               source_health_event_id: "source-health-event-1",
               source_health_reason: :source_adapter_probe_unsupported,
               source_health_probe_kind: "adapter_unsupported",
               source_health_probe_message: "adapter does not support active probes",
               source_health_probe_metadata_text: "storage=questdb"
             }) == %{
               "phx-value-kind" => "source",
               "phx-value-source-evidence-mode" => "health",
               "phx-value-source-request-id" => "request-1",
               "phx-value-logical-source" => "telemetry",
               "phx-value-realm" => "flight",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-source-binding-id" => "binding-flight",
               "phx-value-source-health-event-id" => "source-health-event-1",
               "phx-value-source-health-reason" => "source_adapter_probe_unsupported",
               "phx-value-source-health-probe-kind" => "adapter_unsupported",
               "phx-value-source-health-probe-message" =>
                 "adapter does not support active probes",
               "phx-value-source-health-probe-metadata" => "storage=questdb"
             }
    end

    test "builds source status attrs with source and time context" do
      assert EvidenceAttrs.source_status(%{
               state: :stale,
               logical_sources: [:telemetry],
               source_request_ids: ["request-1"],
               realms: [:flight],
               data_source_ids: ["questdb-flight"],
               source_binding_ids: ["binding-flight"],
               time_modes: [:archive],
               time_axes: [:receipt_time],
               replay_run_ids: ["replay-1"],
               scope_kinds: [:spacecraft],
               scope_ids: ["spacecraft-1"],
               contact_ids: ["contact-1"],
               source_endpoint_ids: ["endpoint-1"],
               empty_reason: :contact_scope_no_data
             }) == %{
               "phx-value-kind" => "source",
               "phx-value-source-evidence-mode" => "health",
               "phx-value-source-evidence-state" => "stale",
               "phx-value-source-request-id" => "request-1",
               "phx-value-logical-source" => "telemetry",
               "phx-value-realm" => "flight",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-source-binding-id" => "binding-flight",
               "phx-value-time-mode" => "archive",
               "phx-value-time-axis" => "receipt_time",
               "phx-value-replay-run-id" => "replay-1",
               "phx-value-scope-kind" => "spacecraft",
               "phx-value-scope-id" => "spacecraft-1",
               "phx-value-contact-id" => "contact-1",
               "phx-value-source-endpoint-id" => "endpoint-1",
               "phx-value-source-empty-reason" => "contact_scope_no_data"
             }
    end

    test "builds execution source status attrs for unavailable sources" do
      assert %{
               "phx-value-source-evidence-mode" => "execution",
               "phx-value-source-evidence-state" => "unavailable"
             } =
               EvidenceAttrs.source_status(%{
                 state: :unavailable,
                 logical_sources: [:telemetry]
               })
    end

    test "builds degraded source attrs" do
      assert EvidenceAttrs.degraded_source(%{
               request_id: "request-1",
               logical_source: "telemetry",
               realm: "flight",
               data_source_id: "questdb-flight",
               source_binding_id: "binding-flight"
             }) == %{
               "phx-value-kind" => "source",
               "phx-value-source-evidence-mode" => "execution",
               "phx-value-source-request-id" => "request-1",
               "phx-value-logical-source" => "telemetry",
               "phx-value-realm" => "flight",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-source-binding-id" => "binding-flight"
             }
    end

    test "builds source capability posture attrs with execution context" do
      assert EvidenceAttrs.source_capability_posture(%{
               request_id: "request-1",
               logical_source: :telemetry,
               realm: :flight,
               data_source_id: "questdb-flight",
               source_binding_id: "binding-flight",
               status: :fallback,
               requested_time_axis: :generation_time,
               executed_time_axis: :receipt_time,
               supported_time_axes: "receipt_time",
               requested_sampling: :latest,
               supported_sampling: "latest",
               requested_products: "link_rf_metric_history",
               supported_products: "transport_bitrate_history",
               fallbacks: "time_axis:generation_time:receipt_time:unsupported_time_axis",
               unsupported: "generation_time"
             }) == %{
               "phx-value-kind" => "source",
               "phx-value-source-evidence-mode" => "execution",
               "phx-value-source-capability-status" => "fallback",
               "phx-value-source-request-id" => "request-1",
               "phx-value-logical-source" => "telemetry",
               "phx-value-realm" => "flight",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-source-binding-id" => "binding-flight",
               "phx-value-requested-time-axis" => "generation_time",
               "phx-value-executed-time-axis" => "receipt_time",
               "phx-value-supported-time-axes" => "receipt_time",
               "phx-value-requested-sampling" => "latest",
               "phx-value-supported-sampling" => "latest",
               "phx-value-requested-products" => "link_rf_metric_history",
               "phx-value-supported-products" => "transport_bitrate_history",
               "phx-value-source-capability-fallbacks" =>
                 "time_axis:generation_time:receipt_time:unsupported_time_axis",
               "phx-value-source-capability-unsupported" => "generation_time"
             }
    end
  end

  describe "frame and warning evidence attrs" do
    test "builds widget frame attrs" do
      assert EvidenceAttrs.frame("placement-1", "HK.counter") == %{
               "phx-value-kind" => "frame",
               "phx-value-placement-id" => "placement-1",
               "phx-value-observable-id" => "HK.counter"
             }
    end

    test "builds widget frame attrs from row-backed data source context" do
      assert EvidenceAttrs.widget_frame("placement-1", nil, %{
               rows: [
                 %{
                   observable_id: "link.rf_lock_state",
                   source_request_id: "request-1",
                   logical_source: :operational_observables,
                   realm: :replay,
                   data_source_id: "managed_operational_observables",
                   source_binding_id: "replay_operational_observables",
                   replay_run_id: "replay-run-1",
                   dataset: "operational_observables_replay"
                 }
               ]
             }) == %{
               "phx-value-kind" => "frame",
               "phx-value-placement-id" => "placement-1",
               "phx-value-observable-id" => "link.rf_lock_state",
               "phx-value-source-request-id" => "request-1",
               "phx-value-logical-source" => "operational_observables",
               "phx-value-realm" => "replay",
               "phx-value-data-source-id" => "managed_operational_observables",
               "phx-value-source-binding-id" => "replay_operational_observables",
               "phx-value-replay-run-id" => "replay-run-1",
               "phx-value-requested-dataset" => "operational_observables_replay"
             }
    end

    test "builds widget frame attrs from chart-backed source context" do
      assert EvidenceAttrs.widget_frame("placement-rf", "link.snr_db", %{
               engine_backed?: true,
               source_request_id: "request-rf",
               logical_source: :operational_observables,
               realm: :replay,
               data_source_id: "managed_operational_observables",
               source_binding_id: "replay_operational_observables",
               replay_run_id: "replay-run-1",
               dataset: "operational_observables_replay",
               links: []
             }) == %{
               "phx-value-kind" => "frame",
               "phx-value-placement-id" => "placement-rf",
               "phx-value-observable-id" => "link.snr_db",
               "phx-value-source-request-id" => "request-rf",
               "phx-value-logical-source" => "operational_observables",
               "phx-value-realm" => "replay",
               "phx-value-data-source-id" => "managed_operational_observables",
               "phx-value-source-binding-id" => "replay_operational_observables",
               "phx-value-replay-run-id" => "replay-run-1",
               "phx-value-requested-dataset" => "operational_observables_replay"
             }
    end

    test "builds widget frame attrs from query scope context without source identity" do
      assert EvidenceAttrs.widget_frame("placement-source-endpoint", "command_queue_depth", %{
               engine_backed?: true,
               query_scope_kind: "source_endpoint",
               query_scope_id: "endpoint-alpha",
               query_scope_ids: ["endpoint-alpha", "endpoint-beta"],
               links: []
             }) == %{
               "phx-value-kind" => "frame",
               "phx-value-placement-id" => "placement-source-endpoint",
               "phx-value-observable-id" => "command_queue_depth",
               "phx-value-scope-kind" => "source_endpoint",
               "phx-value-scope-id" => "endpoint-alpha",
               "phx-value-scope-ids" => "endpoint-alpha,endpoint-beta"
             }
    end

    test "keeps plain widget frame attrs when widget data has no source context" do
      assert EvidenceAttrs.widget_frame("placement-1", "HK.counter", %{
               engine_backed?: true,
               links: []
             }) == %{
               "phx-value-kind" => "frame",
               "phx-value-placement-id" => "placement-1",
               "phx-value-observable-id" => "HK.counter"
             }
    end

    test "builds row frame attrs with source context" do
      assert EvidenceAttrs.row_frame("placement-1", %{
               observable_id: "HK.counter",
               source_request_id: "request-1",
               logical_source: :telemetry,
               realm: :flight,
               data_source_id: "questdb-flight",
               source_binding_id: "binding-flight",
               dataset: :latest
             }) == %{
               "phx-value-kind" => "frame",
               "phx-value-placement-id" => "placement-1",
               "phx-value-observable-id" => "HK.counter",
               "phx-value-source-request-id" => "request-1",
               "phx-value-logical-source" => "telemetry",
               "phx-value-realm" => "flight",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-source-binding-id" => "binding-flight",
               "phx-value-requested-dataset" => "latest"
             }
    end

    test "builds row frame attrs with query scope context" do
      assert EvidenceAttrs.row_frame("placement-connection", %{
               observable_id: "comms.transport.connection_state",
               source_request_id: "request-transport",
               logical_source: :operational_observables,
               query_scope_kind: "transport",
               query_scope_id: "transport-alpha",
               query_scope_ids: ["transport-alpha", "transport-beta"]
             }) == %{
               "phx-value-kind" => "frame",
               "phx-value-placement-id" => "placement-connection",
               "phx-value-observable-id" => "comms.transport.connection_state",
               "phx-value-source-request-id" => "request-transport",
               "phx-value-logical-source" => "operational_observables",
               "phx-value-scope-kind" => "transport",
               "phx-value-scope-id" => "transport-alpha",
               "phx-value-scope-ids" => "transport-alpha,transport-beta"
             }
    end

    test "builds warning attrs with source context when present" do
      assert EvidenceAttrs.warning(
               %{
                 code_text: "missing_source_binding",
                 details: %{
                   source_request_id: "request-1",
                   logical_source: :telemetry,
                   realm: :flight,
                   data_source_id: "questdb-flight",
                   source_binding_id: "binding-flight"
                 }
               },
               "placement-1"
             ) == %{
               "phx-value-kind" => "warning",
               "phx-value-warning-code" => "missing_source_binding",
               "phx-value-placement-id" => "placement-1",
               "phx-value-source-request-id" => "request-1",
               "phx-value-logical-source" => "telemetry",
               "phx-value-realm" => "flight",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-source-binding-id" => "binding-flight"
             }
    end
  end

  describe "cache evidence attrs" do
    test "builds execution cache attrs and drops placeholder values" do
      assert EvidenceAttrs.cache(%{
               evidence_state: "context_only",
               layer: "source",
               status: "hit",
               reasons: "operator_requested",
               request_id: "request-1",
               logical_source: "telemetry",
               realm: "-",
               data_source_id: "questdb-flight",
               source_binding_id: "binding-flight",
               incident_status_text: "source_degraded"
             }) == %{
               "phx-value-kind" => "source",
               "phx-value-source-evidence-mode" => "execution",
               "phx-value-source-evidence-state" => "context_only",
               "phx-value-cache-evidence-layer" => "source",
               "phx-value-cache-evidence-status" => "hit",
               "phx-value-cache-evidence-reasons" => "operator_requested",
               "phx-value-source-request-id" => "request-1",
               "phx-value-logical-source" => "telemetry",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-source-binding-id" => "binding-flight",
               "phx-value-requested-data-source-id" => "questdb-flight",
               "phx-value-requested-source-binding-id" => "binding-flight"
             }
    end
  end
end
