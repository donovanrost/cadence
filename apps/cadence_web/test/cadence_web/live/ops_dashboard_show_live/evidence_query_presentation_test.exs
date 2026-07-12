defmodule CadenceWeb.OpsDashboardShowLive.EvidenceQueryPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery

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
