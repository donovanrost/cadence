defmodule CadenceWeb.OpsDashboardShowLive.RenderSelectionModelTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery
  alias CadenceWeb.OpsDashboardShowLive.RenderSelectionModel
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  test "selection prepares active selection payload" do
    assert RenderSelectionModel.selection(assigns()) == %{
             state: "active",
             target: "telemetry_sample",
             source_binding: "rehearsal-binding",
             data_view: "canonical",
             series_role: "compare",
             compare_of: "HK.counter"
           }
  end

  test "selection prepares query-only and missing payloads" do
    assert RenderSelectionModel.selection(
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

    assert RenderSelectionModel.selection(
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
  end

  test "evidence prepares query and panel evidence payloads" do
    assert RenderSelectionModel.evidence(assigns()) == %{
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
             requested_realm: "simulation",
             requested_data_view: "all_revisions",
             requested_data_source_id: "questdb-sim",
             requested_source_binding_id: "binding-sim",
             requested_dataset: "sim-dataset",
             requested_validity_state: "valid"
           }

    assert RenderSelectionModel.evidence(
             assigns(%{
               panel:
                 {:evidence,
                  %{
                    kind: "source_health",
                    subject_rows: [
                      %{label: "Source request", value: "request-from-panel"},
                      %{label: "Logical source", value: "limits"}
                    ],
                    detail_rows: [
                      %{label: "Realm", value: "rehearsal"},
                      %{label: "Data source", value: "questdb-rehearsal"},
                      %{label: "Source binding", value: "binding-rehearsal"},
                      %{label: "Time mode", value: "archive"},
                      %{label: "Time axis", value: "source_time"},
                      %{label: "Replay run", value: "replay-panel"},
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
             state: "active",
             kind: "source_health",
             source_request: "request-from-panel",
             logical_source: "limits",
             realm: "rehearsal",
             data_source_id: "questdb-rehearsal",
             source_binding_id: "binding-rehearsal",
             time_mode: "archive",
             time_axis: "source_time",
             replay_run_id: "replay-panel",
             requested_realm: "flight",
             requested_data_view: "canonical",
             requested_data_source_id: "questdb-flight",
             requested_source_binding_id: "binding-flight",
             requested_dataset: "flight-dataset",
             requested_validity_state: "partial"
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
