defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenterRequestDefaultsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenter
  alias CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowRequestDefaults

  describe "request_form_defaults/1" do
    test "builds default request form values from dashboard context" do
      defaults =
        HistoricalWorkflowPresenter.request_form_defaults(%{
          realm: "backfill",
          data_source_id: "source-1",
          source_binding_id: "binding-1",
          point_id: "point-1",
          source_from: "2026-06-25T00:00:00Z",
          source_to: "2026-06-25T01:00:00Z",
          dashboard_time_mode: "replay_run",
          dashboard_replay_run_id: "replay-1",
          dashboard_data_view: "all_revisions",
          dashboard_limit_mode: "observed",
          comparison_review_scope_kind: "transport",
          comparison_review_scope_ids: "transport-alpha,transport-beta",
          comparison_review_contact_ids: "contact-alpha,contact-beta",
          comparison_review_resource_ids: "transport-alpha",
          comparison_review_transport_ids: "transport-alpha",
          comparison_review_source_endpoint_ids: "endpoint-alpha",
          comparison_review_ground_station_ids: "dss-14",
          comparison_review_scope_link_ids: "link-alpha"
        })

      assert %HistoricalWorkflowRequestDefaults{} = defaults
      assert defaults.workflow == "backfill"
      assert defaults.realm == "backfill"
      assert defaults.data_source_id == "source-1"
      assert defaults.source_binding_id == "binding-1"
      assert defaults.observable_id == "point-1"
      assert defaults.point_id == "point-1"
      assert defaults.point_ids == "point-1"
      assert defaults.source_from == "2026-06-25T00:00:00Z"
      assert defaults.source_to == "2026-06-25T01:00:00Z"
      assert defaults.dashboard_time_mode == "replay_run"
      assert defaults.dashboard_replay_run_id == "replay-1"
      assert defaults.dashboard_data_view == "all_revisions"
      assert defaults.dashboard_limit_mode == "observed"
      assert defaults.comparison_review_scope_kind == "transport"
      assert defaults.comparison_review_scope_ids == "transport-alpha,transport-beta"
      assert defaults.comparison_review_contact_ids == "contact-alpha,contact-beta"
      assert defaults.comparison_review_source_endpoint_ids == "endpoint-alpha"
      assert defaults.reason == "operator_requested_backfill"
      assert defaults.confirmed == ""
      assert String.starts_with?(defaults.run_id, "telemetry_backfill_run_")

      assert %{
               "workflow" => "backfill",
               "run_id" => run_id,
               "realm" => "backfill",
               "data_source_id" => "source-1",
               "source_binding_id" => "binding-1",
               "observable_id" => "point-1",
               "point_id" => "point-1",
               "point_ids" => "point-1",
               "source_from" => "2026-06-25T00:00:00Z",
               "source_to" => "2026-06-25T01:00:00Z",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "observed",
               "comparison_review_scope_kind" => "transport",
               "comparison_review_scope_ids" => "transport-alpha,transport-beta",
               "comparison_review_contact_ids" => "contact-alpha,contact-beta",
               "comparison_review_resource_ids" => "transport-alpha",
               "comparison_review_transport_ids" => "transport-alpha",
               "comparison_review_source_endpoint_ids" => "endpoint-alpha",
               "comparison_review_ground_station_ids" => "dss-14",
               "comparison_review_scope_link_ids" => "link-alpha",
               "reason" => "operator_requested_backfill",
               "confirmed" => ""
             } = HistoricalWorkflowRequestDefaults.form_params(defaults)

      assert run_id == defaults.run_id
    end

    test "uses empty dashboard context defaults" do
      defaults = HistoricalWorkflowPresenter.request_form_defaults()

      assert %HistoricalWorkflowRequestDefaults{
               realm: "backfill",
               data_source_id: "",
               source_binding_id: "",
               observable_id: "",
               point_id: "",
               point_ids: "",
               source_from: "",
               source_to: ""
             } = defaults
    end
  end
end
