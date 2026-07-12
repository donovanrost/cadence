defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyParamsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyParams

  describe "from_event/1" do
    test "unwraps and normalizes late-data policy form params" do
      params =
        LateDataPolicyParams.from_event(%{
          "late_data_policy" => %{
            "decision" => " accept ",
            "execution_mode" => " sample_execution ",
            "sample_count" => "3",
            "dashboard_time_mode" => " replay_run ",
            "dashboard_replay_run_id" => " replay-1 ",
            "dashboard_data_view" => " all_revisions ",
            "dashboard_limit_mode" => " compare ",
            "confirmed" => "confirmed"
          }
        })

      assert %LateDataPolicyParams{
               decision: "accept",
               execution_mode: "sample_execution",
               sample_count: 3,
               dashboard_time_mode: "replay_run",
               dashboard_replay_run_id: "replay-1",
               dashboard_data_view: "all_revisions",
               dashboard_limit_mode: "compare",
               confirmed: "confirmed"
             } = params

      assert LateDataPolicyParams.confirmed?(params)
    end

    test "accepts atom-key params without dynamic atom creation" do
      assert %LateDataPolicyParams{
               decision: "reject",
               execution_mode: "event_only",
               run_id: "run-1"
             } =
               LateDataPolicyParams.from_event(%{
                 decision: :reject,
                 execution_mode: "event_only",
                 run_id: "run-1"
               })
    end
  end

  describe "attrs/3" do
    test "builds command attrs from typed params" do
      params =
        LateDataPolicyParams.from_event(%{
          "decision" => "accept",
          "execution_mode" => "sample_execution",
          "run_id" => "run-1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-1",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "recomputed",
          "realm" => "flight",
          "data_source_id" => "source-1",
          "source_binding_id" => "binding-1",
          "observable_id" => "HK.counter",
          "point_id" => "HK.counter",
          "sample_count" => "5",
          "authority" => "authoritative",
          "reason" => "operator_accepts_late_data",
          "source_event_id" => "event-1",
          "source_event_type" => "backfill_completed"
        })

      assert LateDataPolicyParams.attrs(
               params,
               %{organization_id: "org-1", user: %{id: "operator-1"}},
               %{mission_id: "mission-1"}
             ) == %{
               backfill_run_id: "run-1",
               execution_mode: "sample_execution",
               payload: %{
                 "dashboard_context" => %{
                   "dashboard_time_mode" => "replay_run",
                   "dashboard_replay_run_id" => "replay-1",
                   "dashboard_data_view" => "all_revisions",
                   "dashboard_limit_mode" => "recomputed"
                 }
               },
               organization_id: "org-1",
               mission_id: "mission-1",
               realm: "flight",
               data_source_id: "source-1",
               binding_id: "binding-1",
               observable_id: "HK.counter",
               point_id: "HK.counter",
               source_from: nil,
               source_to: nil,
               receipt_from: nil,
               receipt_to: nil,
               sample_count: 5,
               authority: "authoritative",
               reason: "operator_accepts_late_data",
               actor_id: "operator-1",
               actor_kind: "operator",
               source_event_id: "event-1",
               source_event_type: "backfill_completed",
               requested_by: "dashboard_data_link_inspector"
             }
    end
  end
end
