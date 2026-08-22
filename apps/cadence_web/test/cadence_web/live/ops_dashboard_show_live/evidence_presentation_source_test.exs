defmodule CadenceWeb.OpsDashboardShowLive.EvidencePresentationSourceTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DashboardAction, DashboardResolveResult}
  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation

  test "source context evidence includes contact scope filter diagnostics" do
    assert %{
             kind: :source,
             status_text: "no_data",
             message:
               "Widget source returned no data for contact contact-1 after filtering telemetry to source endpoint endpoint-1.",
             detail_rows: detail_rows,
             actions: actions
           } =
             EvidencePresentation.evidence_inspector(nil, %{
               "kind" => "source",
               "source-evidence-mode" => "health",
               "source-evidence-state" => "no_data",
               "logical-source" => "telemetry",
               "scope-kind" => "spacecraft",
               "scope-id" => "spacecraft-1",
               "contact-id" => "contact-1",
               "source-endpoint-id" => "endpoint-1",
               "source-empty-reason" => "contact_scope_no_data",
               "data-source-id" => "flight-questdb",
               "source-binding-id" => "binding-flight",
               "realm" => "flight",
               "source-health-event-id" => "source-health-event-1",
               "source-health-reason" => "source_adapter_probe_unsupported",
               "source-health-probe-kind" => "adapter_unsupported",
               "source-health-probe-message" => "adapter does not support active probes",
               "source-health-probe-metadata" => "storage=questdb"
             })

    assert %{label: "Scope kind", value: "spacecraft"} in detail_rows
    assert %{label: "Scope", value: "spacecraft-1"} in detail_rows
    assert %{label: "Contact", value: "contact-1"} in detail_rows
    assert %{label: "Source endpoint", value: "endpoint-1"} in detail_rows
    assert %{label: "Source empty reason", value: "contact_scope_no_data"} in detail_rows
    assert %{label: "Source health event", value: "source-health-event-1"} in detail_rows

    assert %{label: "Source health reason", value: "source_adapter_probe_unsupported"} in detail_rows

    assert %{label: "Probe kind", value: "adapter_unsupported"} in detail_rows

    assert %{label: "Probe message", value: "adapter does not support active probes"} in detail_rows

    assert %{label: "Probe metadata", value: "storage=questdb"} in detail_rows

    assert [
             %DashboardAction{
               target: :source_health,
               query: %{
                 "data_source_id" => "flight-questdb",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry",
                 "realm" => "flight",
                 "scope_kind" => "spacecraft",
                 "scope_id" => "spacecraft-1",
                 "contact_id" => "contact-1",
                 "source_endpoint_id" => "endpoint-1",
                 "source_empty_reason" => "contact_scope_no_data"
               }
             },
             %DashboardAction{
               target: :source_inventory,
               query: %{
                 "data_source_id" => "flight-questdb",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry",
                 "realm" => "flight",
                 "scope_kind" => "spacecraft",
                 "scope_id" => "spacecraft-1",
                 "contact_id" => "contact-1",
                 "source_endpoint_id" => "endpoint-1",
                 "source_empty_reason" => "contact_scope_no_data"
               }
             }
           ] = actions
  end

  test "source context evidence explains partial source coverage" do
    assert %{
             kind: :source,
             status_text: "partial",
             message:
               "Widget source returned partial data for the selected context; inspect missing series, source scope, and source-health evidence before trusting this value.",
             detail_rows: detail_rows
           } =
             EvidencePresentation.evidence_inspector(nil, %{
               "kind" => "source",
               "source-evidence-mode" => "health",
               "source-evidence-state" => "partial",
               "logical-source" => "telemetry",
               "data-source-id" => "flight-questdb",
               "source-binding-id" => "binding-flight",
               "realm" => "flight"
             })

    assert %{label: "Widget source status", value: "partial"} in detail_rows
  end

  test "source context evidence explains degraded source health" do
    assert %{
             kind: :source,
             status_text: "degraded",
             message:
               "Widget source status is degraded; inspect source-health evidence before trusting this value.",
             detail_rows: detail_rows
           } =
             EvidencePresentation.evidence_inspector(nil, %{
               "kind" => "source",
               "source-evidence-mode" => "health",
               "source-evidence-state" => "degraded",
               "logical-source" => "telemetry",
               "data-source-id" => "flight-questdb",
               "source-binding-id" => "binding-flight",
               "realm" => "flight"
             })

    assert %{label: "Widget source status", value: "degraded"} in detail_rows
  end

  test "source evidence inspector surfaces context-only cache evidence details" do
    result = %DashboardResolveResult{}

    assert %{
             kind: :source,
             status_text: "context_only",
             subject: "missing-cache-source",
             subject_rows: subject_rows,
             detail_rows: detail_rows,
             evidence: [],
             links: [],
             actions: actions
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-evidence-state" => "context_only",
               "cache-evidence-layer" => "source",
               "cache-evidence-status" => "hit",
               "cache-evidence-reasons" => "operator_requested",
               "source-request-id" => "missing-cache-source",
               "logical-source" => "telemetry",
               "requested-source-binding-id" => "binding-flight"
             })

    assert %{value: "missing-cache-source"} =
             Enum.find(subject_rows, &(&1.label == "Source request"))

    assert %{value: "hit"} = Enum.find(detail_rows, &(&1.label == "Cache evidence status"))

    assert %{value: "binding-flight"} =
             Enum.find(detail_rows, &(&1.label == "Requested source binding"))

    assert [
             %DashboardAction{target: :source_health, query: %{"logical_source" => "telemetry"}},
             %DashboardAction{
               target: :source_inventory,
               query: %{"logical_source" => "telemetry"}
             }
           ] = actions

    refute EvidencePresentation.evidence_inspector(result, %{
             "kind" => "source",
             "source-request-id" => "missing-cache-source",
             "logical-source" => "telemetry"
           })
  end

  test "source evidence inspector surfaces capability posture context without an incident" do
    result = %DashboardResolveResult{}

    assert %{
             kind: :source,
             status_text: "context_only",
             subject: "req-telemetry",
             subject_rows: subject_rows,
             detail_rows: detail_rows,
             actions: actions
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-evidence-mode" => "execution",
               "source-capability-status" => "fallback",
               "source-request-id" => "req-telemetry",
               "logical-source" => "telemetry",
               "realm" => "flight",
               "data-source-id" => "questdb-flight",
               "source-binding-id" => "binding-flight",
               "requested-time-axis" => "generation_time",
               "executed-time-axis" => "receipt_time",
               "supported-time-axes" => "receipt_time",
               "source-capability-fallbacks" =>
                 "time_axis:generation_time:receipt_time:unsupported_time_axis"
             })

    assert %{value: "req-telemetry"} = Enum.find(subject_rows, &(&1.label == "Source request"))

    assert %{value: "fallback"} =
             Enum.find(detail_rows, &(&1.label == "Source capability status"))

    assert %{value: "generation_time"} =
             Enum.find(detail_rows, &(&1.label == "Requested time axis"))

    assert %{value: "receipt_time"} = Enum.find(detail_rows, &(&1.label == "Executed time axis"))

    assert [
             %DashboardAction{target: :source_health, query: %{"logical_source" => "telemetry"}},
             %DashboardAction{
               target: :source_inventory,
               query: %{"logical_source" => "telemetry"}
             }
           ] = actions
  end

  test "source evidence inspector summarizes widget source-status drilldowns without incidents" do
    result = %DashboardResolveResult{}

    assert %{
             kind: :source,
             title: "Telemetry Source Status",
             status_text: "stale",
             subject: "telemetry",
             message: stale_message,
             detail_rows: detail_rows,
             evidence: [],
             links: [],
             actions: actions
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-evidence-mode" => "health",
               "source-evidence-state" => "stale",
               "logical-source" => "telemetry",
               "data-source-id" => "questdb-flight",
               "source-binding-id" => "binding-flight",
               "time-mode" => "archive",
               "time-axis" => "packet_time"
             })

    assert stale_message =~ "Widget source status is stale"

    assert %{value: "stale"} =
             Enum.find(detail_rows, &(&1.label == "Widget source status"))

    assert %{value: "health"} =
             Enum.find(detail_rows, &(&1.label == "Widget evidence mode"))

    assert %{value: "archive"} = Enum.find(detail_rows, &(&1.label == "Time mode"))
    assert %{value: "packet_time"} = Enum.find(detail_rows, &(&1.label == "Time axis"))

    assert [
             %DashboardAction{
               target: :source_health,
               query: %{
                 "data_source_id" => "questdb-flight",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry"
               }
             },
             %DashboardAction{
               target: :source_inventory,
               query: %{
                 "data_source_id" => "questdb-flight",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry"
               }
             }
           ] = actions
  end
end
