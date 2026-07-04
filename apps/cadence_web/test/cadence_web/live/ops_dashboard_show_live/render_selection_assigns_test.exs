defmodule CadenceWeb.OpsDashboardShowLive.RenderSelectionAssignsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery
  alias CadenceWeb.OpsDashboardShowLive.RenderSelectionAssigns
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery
  alias Phoenix.LiveView.Socket

  test "projects active selection context from sockets and assigns maps" do
    expected = %{
      state: "active",
      target: "telemetry_sample",
      source_binding: "rehearsal-binding",
      data_view: "canonical",
      series_role: "compare",
      compare_of: "HK.counter"
    }

    assert RenderSelectionAssigns.selection_context(%Socket{assigns: assigns()}) == expected
    assert RenderSelectionAssigns.selection_context(assigns()) == expected
  end

  test "projects missing, query-only, stale, and empty selection states" do
    assert RenderSelectionAssigns.selection_context(
             assigns(%{
               dashboard_selected_data_ref: nil,
               panel: {:data_link, %{status: :missing}}
             })
           ) == %{
             state: "missing_target",
             target: nil,
             source_binding: nil,
             data_view: nil,
             series_role: nil,
             compare_of: nil
           }

    assert RenderSelectionAssigns.selection_context(
             assigns(%{
               dashboard_selected_data_ref: nil,
               dashboard_selection_query:
                 SelectionQuery.new(%{"selected_target" => "limit_event"})
             })
           ) == %{
             state: "query_only",
             target: "limit_event",
             source_binding: nil,
             data_view: nil,
             series_role: nil,
             compare_of: nil
           }

    assert RenderSelectionAssigns.selection_context(
             assigns(%{
               dashboard_selected_data_ref: nil,
               dashboard_selection_state: "stale_context"
             })
           ).state == "stale_context"

    assert RenderSelectionAssigns.selection_context(
             assigns(%{
               dashboard_selected_data_ref: nil,
               dashboard_selection_query: nil
             })
           ).state == "none"
  end

  test "projects evidence context from query and active or missing panels" do
    assert RenderSelectionAssigns.evidence_context(%Socket{assigns: assigns()}) == %{
             state: "query_only",
             kind: "source",
             source_request: "request-1",
             logical_source: "telemetry",
             realm: "flight",
             data_source_id: "questdb-flight",
             source_binding_id: "binding-flight",
             time_mode: "replay_run",
             time_axis: "receipt_time",
             replay_run_id: "replay-1",
             scope_kind: nil,
             scope_id: nil,
             scope_ids: nil,
             contact_id: nil,
             source_endpoint_id: nil,
             source_empty_reason: nil,
             requested_realm: "simulation",
             requested_data_view: "all_revisions",
             requested_data_source_id: "questdb-sim",
             requested_source_binding_id: "binding-sim",
             requested_dataset: "sim-dataset",
             requested_validity_state: "valid"
           }

    assert RenderSelectionAssigns.evidence_context(
             assigns(%{
               panel:
                 {:evidence,
                  %{
                    status: :missing,
                    kind: :source_warning,
                    subject_rows: [%{label: "Logical source", value: "limits"}],
                    detail_rows: [
                      %{label: "Realm", value: "rehearsal"},
                      %{label: "Data source", value: "questdb-rehearsal"},
                      %{label: "Source binding", value: "binding-rehearsal"},
                      %{label: "Time mode", value: "archive"},
                      %{label: "Time axis", value: "source_time"},
                      %{label: "Replay run", value: "replay-panel"},
                      %{label: "Scope kind", value: "contact"},
                      %{label: "Scope", value: "spacecraft-1"},
                      %{label: "Contact", value: "contact-1"},
                      %{label: "Source endpoint", value: "endpoint-1"},
                      %{label: "Source empty reason", value: "contact_scope_no_data"},
                      %{label: "Requested realm", value: "flight"},
                      %{label: "Requested data view", value: "canonical"},
                      %{label: "Requested data source", value: "questdb-flight"},
                      %{label: "Requested source binding", value: "binding-flight"},
                      %{label: "Requested dataset", value: "flight-dataset"},
                      %{label: "Requested validity", value: "partial"}
                    ]
                  }},
               dashboard_evidence_query: nil
             })
           ) == %{
             state: "missing",
             kind: "source_warning",
             source_request: nil,
             logical_source: "limits",
             realm: "rehearsal",
             data_source_id: "questdb-rehearsal",
             source_binding_id: "binding-rehearsal",
             time_mode: "archive",
             time_axis: "source_time",
             replay_run_id: "replay-panel",
             scope_kind: "contact",
             scope_id: "spacecraft-1",
             scope_ids: nil,
             contact_id: "contact-1",
             source_endpoint_id: "endpoint-1",
             source_empty_reason: "contact_scope_no_data",
             requested_realm: "flight",
             requested_data_view: "canonical",
             requested_data_source_id: "questdb-flight",
             requested_source_binding_id: "binding-flight",
             requested_dataset: "flight-dataset",
             requested_validity_state: "partial"
           }

    assert RenderSelectionAssigns.evidence_context(
             assigns(%{
               panel: {:evidence, %{kind: "source_health", subject_rows: [], detail_rows: []}},
               dashboard_evidence_query: nil
             })
           ) == %{
             state: "active",
             kind: "source_health",
             source_request: nil,
             logical_source: nil,
             realm: nil,
             data_source_id: nil,
             source_binding_id: nil,
             time_mode: nil,
             time_axis: nil,
             replay_run_id: nil,
             scope_kind: nil,
             scope_id: nil,
             scope_ids: nil,
             contact_id: nil,
             source_endpoint_id: nil,
             source_empty_reason: nil,
             requested_realm: nil,
             requested_data_view: nil,
             requested_data_source_id: nil,
             requested_source_binding_id: nil,
             requested_dataset: nil,
             requested_validity_state: nil
           }

    assert RenderSelectionAssigns.evidence_context(assigns(%{dashboard_evidence_query: nil})) ==
             %{
               state: "none",
               kind: nil,
               source_request: nil,
               logical_source: nil,
               realm: nil,
               data_source_id: nil,
               source_binding_id: nil,
               time_mode: nil,
               time_axis: nil,
               replay_run_id: nil,
               scope_kind: nil,
               scope_id: nil,
               scope_ids: nil,
               contact_id: nil,
               source_endpoint_id: nil,
               source_empty_reason: nil,
               requested_realm: nil,
               requested_data_view: nil,
               requested_data_source_id: nil,
               requested_source_binding_id: nil,
               requested_dataset: nil,
               requested_validity_state: nil
             }
  end

  defp assigns(overrides \\ %{}) do
    Map.merge(
      %{
        dashboard_selected_data_ref: %{
          "target" => "telemetry_sample",
          "target_id" => "sample-1",
          "source_binding_id" => "rehearsal-binding",
          "data_view" => "canonical",
          "series_role" => "compare",
          "compare_of" => "HK.counter"
        },
        dashboard_selection_query: nil,
        dashboard_selection_state: nil,
        dashboard_evidence_query:
          EvidenceQuery.new(%{
            "selected_evidence_kind" => "source",
            "selected_source_request" => "request-1",
            "selected_logical_source" => "telemetry",
            "selected_realm" => "flight",
            "selected_data_source" => "questdb-flight",
            "selected_source_binding" => "binding-flight",
            "selected_time_mode" => "replay_run",
            "selected_time_axis" => "receipt_time",
            "selected_replay_run_id" => "replay-1",
            "selected_requested_realm" => "simulation",
            "selected_requested_data_view" => "all_revisions",
            "selected_requested_data_source" => "questdb-sim",
            "selected_requested_source_binding" => "binding-sim",
            "selected_requested_dataset" => "sim-dataset",
            "selected_requested_validity_state" => "valid"
          }),
        panel: nil
      },
      overrides
    )
  end
end
