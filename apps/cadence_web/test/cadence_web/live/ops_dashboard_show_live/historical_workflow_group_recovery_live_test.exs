defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views =
      Process.get(:ops_dashboard_historical_workflow_group_recovery_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_group_recovery_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_group_recovery_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  describe "historical workflow group recovery surfaces" do
    test "group workflow actions advance corrected replacement request items" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      requested_events =
        for {point_id, index} <- [{"HK.counter", 1}, {"HK.voltage", 2}, {"HK.current", 3}] do
          run_id = "dashboard-workflow-run-effective-00#{index}"

          assert {:ok, event} =
                   Cadence.record_telemetry_historical_data_workflow_event(
                     "backfill",
                     "requested",
                     %{
                       backfill_run_id: run_id,
                       organization_id: org.organization_id,
                       mission_id: mission.mission_id,
                       realm: :backfill,
                       data_source_id: "managed_questdb_backfill",
                       binding_id: "backfill_telemetry",
                       observable_id: point_id,
                       point_id: point_id,
                       source_from: ~U[2026-06-22 10:00:00Z],
                       source_to: ~U[2026-06-22 11:00:00Z],
                       authority: :advisory,
                       reason: "operator_requested_effective_group",
                       actor_id: "operator",
                       actor_kind: "operator",
                       payload: %{
                         "request_source" => "dashboard_direct_request",
                         "request_mode" => "bulk_points",
                         "request_group_id" => "dashboard-workflow-run-effective",
                         "request_item_index" => index,
                         "request_item_count" => 3,
                         "request_item_run_id" => run_id
                       }
                     },
                     dashboard_runtime_invalidation?: false
                   )

          event
        end

      original_voltage_request = Enum.at(requested_events, 1)
      original_current_request = Enum.at(requested_events, 2)

      assert {:ok, failed_voltage_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: original_voltage_request.backfill_run_id,
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.voltage",
                   point_id: "HK.voltage",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 2,
                     "request_item_count" => 3,
                     "request_item_run_id" => original_voltage_request.backfill_run_id,
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:voltage",
                         "retryable" => false,
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, failed_current_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: original_current_request.backfill_run_id,
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 3,
                     "request_item_count" => 3,
                     "request_item_run_id" => original_current_request.backfill_run_id,
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:point_id",
                         "retryable" => false,
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, corrected_current_request} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "requested",
                 %{
                   backfill_run_id: "dashboard-workflow-run-effective-003-corrected",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "operator_corrected_effective_group_item",
                   actor_id: "operator",
                   actor_kind: "operator",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => original_current_request.backfill_run_id,
                     "corrects_event_id" => failed_current_event.backfill_lifecycle_event_id,
                     "corrects_job_id" => "dashboard-workflow-effective-job-current",
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 3,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-effective-003-corrected"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, corrected_voltage_request} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "requested",
                 %{
                   backfill_run_id: "dashboard-workflow-run-effective-002-corrected",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.voltage",
                   point_id: "HK.voltage",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "operator_corrected_effective_group_item",
                   actor_id: "operator",
                   actor_kind: "operator",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => original_voltage_request.backfill_run_id,
                     "corrects_event_id" => failed_voltage_event.backfill_lifecycle_event_id,
                     "corrects_job_id" => "dashboard-workflow-effective-job-voltage",
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 2,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-effective-002-corrected"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, _corrected_voltage_approved} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "approved",
                 %{
                   backfill_run_id: "dashboard-workflow-run-effective-002-corrected",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.voltage",
                   point_id: "HK.voltage",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "operator_preapproved_corrected_effective_group_item",
                   actor_id: "operator",
                   actor_kind: "operator",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => original_voltage_request.backfill_run_id,
                     "corrects_event_id" => failed_voltage_event.backfill_lifecycle_event_id,
                     "requested_event_id" =>
                       corrected_voltage_request.backfill_lifecycle_event_id,
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 2,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-effective-002-corrected"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{corrected_current_request.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      approved_correction_task =
        "HK.current dashboard-workflow-run-effective-003 replacement dashboard-workflow-run-effective-003-corrected stage requested next approve"

      started_correction_task =
        "HK.current dashboard-workflow-run-effective-003 replacement dashboard-workflow-run-effective-003-corrected stage approved next start"

      completed_correction_task =
        "HK.current dashboard-workflow-run-effective-003 replacement dashboard-workflow-run-effective-003-corrected stage started next complete"

      voltage_started_correction_task =
        "HK.voltage dashboard-workflow-run-effective-002 replacement dashboard-workflow-run-effective-002-corrected stage approved next start"

      voltage_completed_correction_task =
        "HK.voltage dashboard-workflow-run-effective-002 replacement dashboard-workflow-run-effective-002-corrected stage started next complete"

      started_correction_tasks =
        "#{voltage_started_correction_task}; #{started_correction_task}"

      completed_correction_tasks =
        "#{voltage_completed_correction_task}; #{completed_correction_task}"

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-remaining-work[data-historical-workflow-group-recovery-remaining-work-count="2"][data-historical-workflow-group-recovery-remaining-work-pending-count="2"][data-historical-workflow-group-recovery-remaining-work-completed-count="0"][data-historical-workflow-group-recovery-remaining-work-next-actions*="approve"][data-historical-workflow-group-recovery-remaining-work-next-actions*="start"][data-historical-workflow-group-recovery-remaining-work-pending-runs*="dashboard-workflow-run-effective-002-corrected"][data-historical-workflow-group-recovery-remaining-work-pending-runs*="dashboard-workflow-run-effective-003-corrected"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-closure-readiness[data-historical-workflow-group-recovery-closure-status="inspect_job_state"][data-historical-workflow-group-recovery-closure-action="inspect_missing_replacement_jobs"][data-historical-workflow-group-recovery-closure-unresolved="0"][data-historical-workflow-group-recovery-closure-pending-replacements="2"][data-historical-workflow-group-recovery-closure-blocked-jobs="3"][data-historical-workflow-group-recovery-closure-failed-jobs="0"][data-historical-workflow-group-recovery-closure-missing-jobs="2"][data-historical-workflow-group-recovery-closure-stale-jobs="0"])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-group-recovery-remaining-work-replacement-run="dashboard-workflow-run-effective-002-corrected"][data-historical-workflow-group-recovery-remaining-work-stage="approved"][data-historical-workflow-group-recovery-remaining-work-next-action="start"][data-historical-workflow-group-recovery-remaining-work-status="pending"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected-form[data-historical-workflow-group-recovery-advance-stage="approved"][data-historical-workflow-group-recovery-advance-eligible="true"][data-historical-workflow-group-recovery-advance-count="1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected[data-workflow-action-stage="approved"][data-workflow-action-correction-tasks="#{approved_correction_task}"])
             )

      view
      |> element("#dashboard-historical-workflow-group-recovery-advance-corrected-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-effective",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "approved",
          "reason" => "dashboard_recovery_replacement_approved",
          "group_transition_scope" => "replacement_corrections",
          "group_correction_tasks" => approved_correction_task,
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected-form[data-historical-workflow-group-recovery-advance-stage="started"][data-historical-workflow-group-recovery-advance-eligible="true"][data-historical-workflow-group-recovery-advance-count="2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected[data-workflow-action-stage="started"][data-workflow-action-correction-tasks="#{started_correction_tasks}"])
             )

      view
      |> element("#dashboard-historical-workflow-group-recovery-advance-corrected-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-effective",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "started",
          "reason" => "dashboard_recovery_replacement_started",
          "group_transition_scope" => "replacement_corrections",
          "group_correction_tasks" => started_correction_tasks,
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected-form[data-historical-workflow-group-recovery-advance-stage="completed"][data-historical-workflow-group-recovery-advance-eligible="true"][data-historical-workflow-group-recovery-advance-count="2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected[data-workflow-action-stage="completed"][data-workflow-action-correction-tasks="#{completed_correction_tasks}"])
             )

      view
      |> element("#dashboard-historical-workflow-group-recovery-advance-corrected-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-effective",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "completed",
          "reason" => "dashboard_recovery_replacement_completed",
          "group_transition_scope" => "replacement_corrections",
          "group_correction_tasks" => completed_correction_tasks,
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-stage="completed"][data-workflow-latest-action-request-group-id="dashboard-workflow-run-effective"][data-workflow-latest-action-count="2"][data-workflow-latest-action-result-event-ids])
             )
    end
  end
end
