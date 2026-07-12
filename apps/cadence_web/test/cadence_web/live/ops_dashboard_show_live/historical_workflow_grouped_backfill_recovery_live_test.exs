defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupedBackfillRecoveryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Telemetry.Storage
  alias CadenceWeb.TestFixtures

  @request_group_id "dashboard-workflow-run-bulk-recovery"

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
      Process.get(
        :ops_dashboard_historical_workflow_grouped_backfill_recovery_views,
        MapSet.new()
      )

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_grouped_backfill_recovery_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_grouped_backfill_recovery_view, pid}, fn ->
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

  defp run_id(index), do: "#{@request_group_id}-00#{index}"

  defp record_group_event(stage, org, mission, point_id, index, payload_overrides \\ %{}) do
    run_id = run_id(index)

    Cadence.record_telemetry_historical_data_workflow_event(
      "backfill",
      stage,
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
        authority: :authoritative,
        reason: "historical_data_job_#{stage}",
        actor_id: "system",
        actor_kind: "system",
        payload:
          Map.merge(
            %{
              "request_source" => "dashboard_direct_request",
              "request_mode" => "bulk_points",
              "request_group_id" => @request_group_id,
              "request_item_index" => index,
              "request_item_count" => 3,
              "request_item_run_id" => run_id
            },
            payload_overrides
          )
      },
      dashboard_runtime_invalidation?: false
    )
  end

  defp record_failed_group_event(org, mission, point_id, index, failure) do
    record_group_event(
      "failed",
      org,
      mission,
      point_id,
      index,
      %{
        "source" => %{"failure" => failure}
      }
    )
  end

  defp enqueue_job(mission, run_id) do
    Cadence.Jobs.enqueue(
      :telemetry_historical_data_workflow,
      mission.mission_id,
      run_id,
      %{
        "workflow" => "backfill",
        "attrs" => %{"backfill_run_id" => run_id}
      }
    )
  end

  defp seed_grouped_backfill_recovery(org, mission) do
    for {point_id, index} <- [{"HK.counter", 1}, {"HK.voltage", 2}, {"HK.current", 3}],
        stage <- ["requested", "approved", "started"] do
      assert {:ok, _event} = record_group_event(stage, org, mission, point_id, index)
    end

    assert {:ok, voltage_job} = enqueue_job(mission, run_id(2))
    assert {:ok, current_job} = enqueue_job(mission, run_id(3))

    claimed_job_ids =
      2
      |> Cadence.Jobs.claim_jobs()
      |> Enum.map(& &1.job_id)
      |> Enum.sort()

    assert claimed_job_ids == Enum.sort([voltage_job.job_id, current_job.job_id])

    assert {:ok, failed_voltage_job} =
             Cadence.Jobs.fail_worker_start(voltage_job.job_id, :source_window_unavailable)

    assert {:ok, failed_current_job} =
             Cadence.Jobs.fail_worker_start(current_job.job_id, :missing_point_id)

    assert failed_voltage_job.status == :failed
    assert failed_current_job.status == :failed

    assert {:ok, _counter_job} = enqueue_job(mission, run_id(1))

    assert {:ok, counter_completed} =
             record_group_event("completed", org, mission, "HK.counter", 1)

    assert {:ok, failed_event} =
             record_failed_group_event(org, mission, "HK.voltage", 2, %{
               "code" => "source_window_unavailable",
               "retryable" => true,
               "recovery_action" => "retry_job"
             })

    assert {:ok, nonretryable_failed_event} =
             record_failed_group_event(org, mission, "HK.current", 3, %{
               "code" => "missing_field:point_id",
               "retryable" => false,
               "retry_blockers" => ["missing point_id"],
               "recovery_action" => "correct_workflow_request"
             })

    %{
      counter_completed: counter_completed,
      current_job: failed_current_job,
      failed_event: failed_event,
      nonretryable_failed_event: nonretryable_failed_event,
      voltage_job: failed_voltage_job
    }
  end

  describe "historical workflow grouped backfill recovery surfaces" do
    test "recovers retryable and corrected bulk backfill items" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      %{
        counter_completed: counter_completed,
        current_job: current_job,
        failed_event: failed_event,
        nonretryable_failed_event: nonretryable_failed_event
      } = seed_grouped_backfill_recovery(org, mission)

      failed_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{failed_event.backfill_lifecycle_event_id}"

      {:ok, failed_view, _html} = live(conn, failed_path)
      render_dashboard_async(failed_view)

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="completed_with_failures"][data-historical-workflow-group-terminal="true"][data-historical-workflow-group-completed="1"][data-historical-workflow-group-failed="2"][data-historical-workflow-group-retryable-failed="1"][data-historical-workflow-group-nonretryable-failed="1"]),
               "HK.voltage"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery-guidance[data-historical-workflow-group-recovery-guidance-next-action="retry_failed_items"][data-historical-workflow-group-recovery-guidance-retry-eligible="true"][data-historical-workflow-group-recovery-guidance-retry-reason="retryable_group_failures"]),
               "Retry 1 failed jobs in request group #{@request_group_id}"
             )

      failed_view
      |> element("#dashboard-historical-workflow-group-retry-failed")
      |> render_click()

      assert_patch(failed_view)

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_group_failed_jobs"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-request-group-id="#{@request_group_id}"][data-workflow-latest-action-retried="1"][data-workflow-latest-action-retry-nonretryable="1"][data-workflow-latest-action-retry-skipped="0"][data-workflow-latest-action-retry-errors="0"])
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action-retry-nonretryable-run-ids="#{run_id(3)}"][data-workflow-latest-action-retry-nonretryable-event-ids="#{nonretryable_failed_event.backfill_lifecycle_event_id}"])
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="failing"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-failed="1"][data-historical-workflow-group-resolved-failed="1"][data-historical-workflow-group-retry-resolved="1"][data-historical-workflow-group-correction-requested="0"][data-historical-workflow-group-retryable-failed="0"][data-historical-workflow-group-nonretryable-failed="1"]),
               "HK.current"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery-guidance[data-historical-workflow-group-recovery-guidance-next-action="create_corrected_requests"][data-historical-workflow-group-recovery-guidance-retry-eligible="false"][data-historical-workflow-group-recovery-guidance-retry-reason="no_retryable_group_failures"]),
               "Create corrected workflow requests for non-retryable failed items."
             )

      refute has_element?(failed_view, "#dashboard-historical-workflow-group-retry-failed")

      failed_view
      |> element(
        ~s([data-historical-workflow-group-recovery-failed-item="#{nonretryable_failed_event.backfill_lifecycle_event_id}"])
      )
      |> render_click()

      assert_patch(failed_view)
      render_dashboard_async(failed_view)

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-correction-form[data-workflow-action-eligible="true"][data-workflow-action-reason="correction_request_required"])
             )

      corrected_run_id = "#{run_id(3)}-corrected"

      failed_view
      |> element("#dashboard-historical-workflow-correction-form")
      |> render_submit(%{
        "historical_workflow_correction" => %{
          "workflow" => "backfill",
          "run_id" => corrected_run_id,
          "original_run_id" => run_id(3),
          "original_event_id" => nonretryable_failed_event.backfill_lifecycle_event_id,
          "original_job_id" => current_job.job_id,
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "observable_id" => "HK.current",
          "point_id" => "HK.current",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "reason" => "operator_corrected_bulk_item",
          "request_mode" => "bulk_points",
          "request_group_id" => @request_group_id,
          "request_item_index" => "3",
          "request_item_count" => "3",
          "request_item_run_id" => corrected_run_id,
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(failed_view)

      assert [corrected_group_event] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: corrected_run_id
               )

      assert corrected_group_event.event_type == :backfill_requested

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="correction_request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="correction_request_recorded"][data-workflow-latest-action-request-group-id="#{@request_group_id}"][data-workflow-latest-action-result-event-ids="#{corrected_group_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{corrected_group_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="#{corrected_run_id}"]),
               "Corrected historical data workflow request recorded."
             )

      corrected_group_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{corrected_group_event.backfill_lifecycle_event_id}"

      {:ok, corrected_group_view, _html} = live(conn, corrected_group_path)
      render_dashboard_async(corrected_group_view)

      correction_task =
        "HK.current #{run_id(3)} replacement #{corrected_run_id} stage requested next approve"

      {:ok, missing_inspection_view, _html} = live(conn, corrected_group_path)
      render_dashboard_async(missing_inspection_view)

      missing_inspection_view
      |> element("#dashboard-historical-workflow-missing-replacement-inspect-#{corrected_run_id}")
      |> render_click()

      assert_patch(missing_inspection_view)

      assert has_element?(
               missing_inspection_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="missing_replacement_job_inspection"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="missing_replacement_job_inspection_recorded"][data-workflow-latest-action-request-group-id="#{@request_group_id}"][data-workflow-latest-action-target-run-id="#{corrected_run_id}"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"])
             )

      assert has_element?(
               corrected_group_view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected-form[data-historical-workflow-group-recovery-advance-request-group="#{@request_group_id}"][data-historical-workflow-group-recovery-advance-stage="approved"][data-historical-workflow-group-recovery-advance-eligible="true"][data-historical-workflow-group-recovery-advance-count="1"]),
               "Advance 1 corrected replacement request to approved."
             )

      corrected_group_view
      |> element("#dashboard-historical-workflow-group-recovery-advance-corrected-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => @request_group_id,
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "approved",
          "reason" => "dashboard_recovery_replacement_approved",
          "group_transition_scope" => "replacement_corrections",
          "group_correction_tasks" => correction_task,
          "confirmed" => "confirmed"
        }
      })

      assert_patch(corrected_group_view)

      approved_replacement_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(
          &(&1.backfill_run_id == corrected_run_id and
              &1.reason == "dashboard_recovery_replacement_approved")
        )

      assert [approved_replacement_event] = approved_replacement_events
      assert approved_replacement_event.backfill_run_id == corrected_run_id

      assert {:ok, _corrected_group_started} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "started",
                 %{
                   backfill_run_id: corrected_run_id,
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :authoritative,
                   reason: "operator_started_corrected_bulk_item",
                   actor_id: "operator",
                   actor_kind: "operator",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => run_id(3),
                     "corrects_event_id" => nonretryable_failed_event.backfill_lifecycle_event_id,
                     "corrects_job_id" => current_job.job_id,
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => @request_group_id,
                     "request_item_index" => 3,
                     "request_item_count" => 3,
                     "request_item_run_id" => corrected_run_id
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, corrected_group_completed} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "completed",
                 %{
                   backfill_run_id: corrected_run_id,
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :authoritative,
                   reason: "historical_data_job_completed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => run_id(3),
                     "corrects_event_id" => nonretryable_failed_event.backfill_lifecycle_event_id,
                     "corrects_job_id" => current_job.job_id,
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => @request_group_id,
                     "request_item_index" => 3,
                     "request_item_count" => 3,
                     "request_item_run_id" => corrected_run_id
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      corrected_group_completed_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{corrected_group_completed.backfill_lifecycle_event_id}"

      {:ok, corrected_group_completed_view, _html} = live(conn, corrected_group_completed_path)
      render_dashboard_async(corrected_group_completed_view)

      assert has_element?(
               corrected_group_completed_view,
               ~s([data-historical-workflow-group-correction-task="HK.current #{run_id(3)} replacement #{corrected_run_id} stage completed next done"])
             )

      completed_item_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{counter_completed.backfill_lifecycle_event_id}"

      {:ok, completed_item_view, _html} = live(conn, completed_item_path)
      render_dashboard_async(completed_item_view)

      assert has_element?(
               completed_item_view,
               ~s([data-data-link-related-id="#{failed_event.backfill_lifecycle_event_id}"]),
               "Failed item HK.voltage"
             )

      completed_item_view
      |> element(~s([data-data-link-related-id="#{failed_event.backfill_lifecycle_event_id}"]))
      |> render_click()

      assert_patch(completed_item_view)

      assert has_element?(
               completed_item_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               failed_event.backfill_lifecycle_event_id
             )
    end
  end
end
