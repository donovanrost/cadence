defmodule CadenceWeb.OpsDashboardShowLive.DataLinkSelectionEvidenceTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection
  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  describe "evidence query parsing" do
    test "builds evidence queries from URL params only when evidence kind is present" do
      query =
        DataLinkSelection.evidence_query_from_params(
          %{
            "selected_evidence_kind" => "source_warning",
            "selected_placement" => "placement-1",
            "selected_observable" => "HK.counter",
            "selected_realm" => "backfill"
          },
          :evidence
        )

      assert %EvidenceQuery{} = query

      assert EvidenceQuery.to_params(query) == %{
               "selected_evidence_kind" => "source_warning",
               "selected_placement" => "placement-1",
               "selected_observable" => "HK.counter",
               "selected_realm" => "backfill"
             }

      assert is_nil(
               DataLinkSelection.evidence_query_from_params(
                 %{"selected_observable" => "HK.counter"},
                 :evidence
               )
             )
    end

    test "round trips evidence event params through query params" do
      event_params = %{
        "kind" => "source_warning",
        "placement-id" => "placement-1",
        "observable-id" => "HK.counter",
        "warning-code" => "late_sample",
        "source-evidence-state" => "context_only",
        "cache-evidence-status" => "hit",
        "realm" => "backfill",
        "requested-source-binding-id" => "binding-1"
      }

      query = DataLinkSelection.evidence_query_from_event_params(event_params)

      assert %EvidenceQuery{} = query

      assert EvidenceQuery.to_params(query) == %{
               "selected_evidence_kind" => "source_warning",
               "selected_placement" => "placement-1",
               "selected_observable" => "HK.counter",
               "selected_warning_code" => "late_sample",
               "selected_source_evidence_state" => "context_only",
               "selected_cache_evidence_status" => "hit",
               "selected_realm" => "backfill",
               "selected_requested_source_binding" => "binding-1"
             }

      assert DataLinkSelection.event_params_from_evidence_query(query) == event_params
    end
  end

  describe "evidence presentation" do
    test "builds missing evidence inspectors from evidence queries" do
      inspector =
        DataLinkSelection.missing_evidence_inspector(%{
          "selected_evidence_kind" => "source_warning",
          "selected_placement" => "placement-1",
          "selected_observable" => "HK.counter",
          "selected_warning_code" => "late_sample",
          "selected_source_request" => "request-1",
          "selected_realm" => "backfill",
          "selected_requested_data_view" => "canonical"
        })

      assert inspector.kind == "source_warning"
      assert inspector.kind_text == "source_warning"
      assert inspector.subject == "late_sample"
      assert inspector.status == :missing
      assert inspector.status_text == "missing"
      assert inspector.title == "Missing Evidence"
      assert inspector.evidence == []
      assert inspector.links == []

      assert %{label: "Warning", value: "late_sample"} in inspector.subject_rows
      assert %{label: "Source request", value: "request-1"} in inspector.subject_rows
      assert %{label: "Realm", value: "backfill"} in inspector.detail_rows
      assert %{label: "Requested data view", value: "canonical"} in inspector.detail_rows
    end

    test "derives evidence metadata from panel before query state" do
      panel =
        {:evidence,
         %{
           kind: :source_warning,
           status: :missing,
           subject_rows: [%{label: "Source request", value: "request-from-panel"}],
           detail_rows: [
             %{label: "Logical source", value: "telemetry"},
             %{label: "Realm", value: "flight"},
             %{label: "Data source", value: "questdb-flight"},
             %{label: "Source binding", value: "binding-flight"},
             %{label: "Time mode", value: "replay_run"},
             %{label: "Time axis", value: "source_time"},
             %{label: "Replay run", value: "replay-1"},
             %{label: "Requested realm", value: "simulation"},
             %{label: "Requested data view", value: "all_revisions"},
             %{label: "Requested data source", value: "questdb-sim"},
             %{label: "Requested source binding", value: "binding-sim"},
             %{label: "Requested dataset", value: "sim-dataset"},
             %{label: "Requested validity", value: "valid"}
           ]
         }}

      query = %{
        "selected_evidence_kind" => "source_health",
        "selected_source_request" => "request-from-query",
        "selected_data_source" => "questdb-query",
        "selected_source_binding" => "binding-query"
      }

      assert DataLinkSelection.evidence_state(panel, query) == "missing"
      assert DataLinkSelection.evidence_kind(panel, query) == "source_warning"
      assert DataLinkSelection.evidence_source_request(panel, query) == "request-from-panel"
      assert DataLinkSelection.evidence_logical_source(panel, query) == "telemetry"
      assert DataLinkSelection.evidence_realm(panel, query) == "flight"
      assert DataLinkSelection.evidence_data_source_id(panel, query) == "questdb-flight"
      assert DataLinkSelection.evidence_source_binding_id(panel, query) == "binding-flight"
      assert DataLinkSelection.evidence_time_mode(panel, query) == "replay_run"
      assert DataLinkSelection.evidence_time_axis(panel, query) == "source_time"
      assert DataLinkSelection.evidence_replay_run_id(panel, query) == "replay-1"
      assert DataLinkSelection.evidence_requested_realm(panel, query) == "simulation"
      assert DataLinkSelection.evidence_requested_data_view(panel, query) == "all_revisions"
      assert DataLinkSelection.evidence_requested_data_source_id(panel, query) == "questdb-sim"
      assert DataLinkSelection.evidence_requested_source_binding_id(panel, query) == "binding-sim"
      assert DataLinkSelection.evidence_requested_dataset(panel, query) == "sim-dataset"
      assert DataLinkSelection.evidence_requested_validity_state(panel, query) == "valid"
    end

    test "derives query-only evidence metadata before panel hydration" do
      query = %{
        "selected_evidence_kind" => "source_health",
        "selected_source_request" => "request-1",
        "selected_logical_source" => "limits",
        "selected_realm" => "rehearsal",
        "selected_data_source" => "questdb-rehearsal",
        "selected_source_binding" => "binding-rehearsal",
        "selected_time_mode" => "replay_run",
        "selected_time_axis" => "receipt_time",
        "selected_replay_run_id" => "replay-1",
        "selected_requested_realm" => "simulation",
        "selected_requested_data_view" => "all_revisions",
        "selected_requested_data_source" => "questdb-sim",
        "selected_requested_source_binding" => "binding-sim",
        "selected_requested_dataset" => "sim-dataset",
        "selected_requested_validity_state" => "valid"
      }

      assert DataLinkSelection.evidence_state(nil, query) == "query_only"
      assert DataLinkSelection.evidence_kind(nil, query) == "source_health"
      assert DataLinkSelection.evidence_source_request(nil, query) == "request-1"
      assert DataLinkSelection.evidence_logical_source(nil, query) == "limits"
      assert DataLinkSelection.evidence_realm(nil, query) == "rehearsal"
      assert DataLinkSelection.evidence_data_source_id(nil, query) == "questdb-rehearsal"
      assert DataLinkSelection.evidence_source_binding_id(nil, query) == "binding-rehearsal"
      assert DataLinkSelection.evidence_time_mode(nil, query) == "replay_run"
      assert DataLinkSelection.evidence_time_axis(nil, query) == "receipt_time"
      assert DataLinkSelection.evidence_replay_run_id(nil, query) == "replay-1"
      assert DataLinkSelection.evidence_requested_realm(nil, query) == "simulation"
      assert DataLinkSelection.evidence_requested_data_view(nil, query) == "all_revisions"
      assert DataLinkSelection.evidence_requested_data_source_id(nil, query) == "questdb-sim"
      assert DataLinkSelection.evidence_requested_source_binding_id(nil, query) == "binding-sim"
      assert DataLinkSelection.evidence_requested_dataset(nil, query) == "sim-dataset"
      assert DataLinkSelection.evidence_requested_validity_state(nil, query) == "valid"
      assert DataLinkSelection.evidence_state(nil, nil) == "none"
    end
  end

  describe "evidence panel query helpers" do
    test "marks evidence as the active panel when evidence query is present" do
      query =
        base_query_attrs(%{
          selected_ref: %{
            "link_id" => "link-1",
            "target" => "telemetry_point",
            "target_id" => "HK.counter"
          },
          evidence_query: %{
            "selected_evidence_kind" => "source_warning",
            "selected_source_request" => "request-1"
          }
        })
        |> DataLinkSelection.current_query()
        |> DataLinkSelection.compact_query()

      assert query["selected_link"] == "link-1"
      assert query["selected_evidence_kind"] == "source_warning"
      assert query["selected_source_request"] == "request-1"
      assert query["panel"] == "evidence"
    end

    test "panel query clears the opposite panel state" do
      data_link_query =
        DataLinkSelection.panel_query(
          :data_link,
          SelectionQuery.new(%{"selected_target" => "telemetry_point"})
        )

      assert data_link_query["panel"] == "data_link"
      assert data_link_query["selected_target"] == "telemetry_point"
      assert Map.has_key?(data_link_query, "selected_evidence_kind")
      assert is_nil(data_link_query["selected_evidence_kind"])

      evidence_query =
        DataLinkSelection.panel_query(:evidence, %{"selected_evidence_kind" => "warning"})

      assert evidence_query["panel"] == "evidence"
      assert evidence_query["selected_evidence_kind"] == "warning"
      assert Map.has_key?(evidence_query, "selected_target")
      assert is_nil(evidence_query["selected_target"])
    end

    test "current panel query prefers evidence over data-link state" do
      assert DataLinkSelection.current_panel_query(
               SelectionQuery.new(%{"selected_id" => "point-1"}),
               %{}
             ) == %{
               "panel" => "data_link"
             }

      assert DataLinkSelection.current_panel_query(
               %{"selected_id" => "point-1"},
               %{"selected_evidence_kind" => "warning"}
             ) == %{"panel" => "evidence"}
    end
  end

  defp base_query_attrs(overrides) do
    Map.merge(
      %{
        selected_ref: nil,
        selection_query: nil,
        evidence_query: nil,
        scope_kind: nil,
        scope_id: nil,
        time_mode: "live",
        time_from: nil,
        time_to: nil,
        replay_run_id: nil,
        realm: "flight",
        default_realm: "flight",
        data_view: "canonical",
        default_data_view: "canonical",
        data_source_id: nil,
        source_binding_id: nil,
        default_source_binding_id: nil,
        limit_mode: "observed"
      },
      overrides
    )
  end
end
