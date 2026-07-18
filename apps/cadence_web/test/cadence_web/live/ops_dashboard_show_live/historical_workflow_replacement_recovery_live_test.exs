defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecoveryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Jobs.BackgroundJobRow
  alias Cadence.Repo
  alias Cadence.Telemetry.Storage
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

  defp dashboard_context_payload(%Document{} = dashboard) do
    %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "archive",
      "dashboard_data_view" => "as_recorded",
      "dashboard_limit_mode" => "observed"
    }
  end

  defp stale_replacement_workflow!(org, mission, %Document{} = dashboard, suffix) do
    replacement_workflow!(org, mission, dashboard, suffix,
      prefix: "dashboard-stale-replacement",
      request_group_id: "dashboard-stale-replacement-#{suffix}-group",
      item_index: 1,
      item_count: 1,
      replacement_job: :stale
    )
  end

  defp replacement_workflow!(org, mission, %Document{} = dashboard, suffix, opts) do
    prefix = Keyword.fetch!(opts, :prefix)
    failed_run_id = "#{prefix}-#{suffix}-source"
    replacement_run_id = "#{prefix}-#{suffix}-corrected"
    request_group_id = Keyword.fetch!(opts, :request_group_id)
    item_index = Keyword.fetch!(opts, :item_index)
    item_count = Keyword.fetch!(opts, :item_count)

    failed_job = enqueue_failed_historical_workflow_job!(mission, failed_run_id)

    assert {:ok, failed_event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "failed",
               %{
                 backfill_run_id: failed_run_id,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.#{suffix}",
                 point_id: "HK.#{suffix}",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :advisory,
                 reason: "historical_data_job_failed",
                 actor_id: "system",
                 actor_kind: "system",
                 payload: %{
                   "request_source" => "dashboard_direct_request",
                   "request_mode" => "bulk_points",
                   "request_group_id" => request_group_id,
                   "request_item_index" => item_index,
                   "request_item_count" => item_count,
                   "request_item_run_id" => failed_run_id,
                   "job_id" => failed_job.job_id,
                   "dashboard_context" => dashboard_context_payload(dashboard),
                   "source" => %{
                     "failure" => %{
                       "code" => "source_window_unavailable",
                       "retryable" => false,
                       "recovery_action" => "correct_workflow_request"
                     }
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: replacement_run_id,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 actor_id: "operator-1",
                 actor_kind: "operator"
               },
               %{
                 original_event_id: failed_event.backfill_lifecycle_event_id,
                 original_run_id: failed_event.backfill_run_id,
                 original_job_id: failed_job.job_id,
                 request_group_id: request_group_id,
                 request_item_index: item_index,
                 request_item_count: item_count,
                 request_item_run_id: replacement_run_id,
                 dashboard_id: dashboard.dashboard_id,
                 dashboard_version: "1",
                 dashboard_time_mode: "archive",
                 dashboard_data_view: "as_recorded",
                 dashboard_limit_mode: "observed"
               },
               dashboard_runtime_invalidation?: false
             )

    assert correction_request.payload["dashboard_context"] == dashboard_context_payload(dashboard)

    replacement_job =
      case Keyword.fetch!(opts, :replacement_job) do
        :missing ->
          nil

        :failed ->
          enqueue_failed_historical_workflow_job!(mission, correction_request.backfill_run_id)

        :stale ->
          enqueue_stale_running_historical_workflow_job!(
            mission,
            correction_request.backfill_run_id
          )
      end

    %{
      failed_event: failed_event,
      failed_job: failed_job,
      correction_request: correction_request,
      replacement_job: replacement_job
    }
  end

  defp enqueue_failed_historical_workflow_job!(mission, run_id) do
    assert {:ok, job} = enqueue_historical_workflow_job(mission, run_id)
    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == job.job_id))
    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_window_failed)
    failed_job
  end

  defp enqueue_stale_running_historical_workflow_job!(mission, run_id) do
    assert {:ok, job} = enqueue_historical_workflow_job(mission, run_id)
    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == job.job_id))
    assert {:ok, running_job} = Cadence.Jobs.fetch_job(job.job_id)

    stale_job = %{running_job | started_at: DateTime.add(DateTime.utc_now(), -1_200, :second)}

    assert {:ok, updated_row} =
             job.job_id
             |> then(&Repo.get!(BackgroundJobRow, &1))
             |> BackgroundJobRow.changeset(stale_job)
             |> Repo.update()

    BackgroundJobRow.to_domain(updated_row)
  end

  defp enqueue_historical_workflow_job(mission, run_id) do
    Cadence.Jobs.enqueue(
      :telemetry_historical_data_workflow,
      mission.mission_id,
      run_id,
      %{"workflow" => "backfill", "attrs" => %{"backfill_run_id" => run_id}}
    )
  end

  defp element_attribute(html, selector, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attribute)

    value
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_replacement_recovery_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_replacement_recovery_live_test_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_replacement_recovery_live_view, pid}, fn ->
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

  describe "replacement recovery LiveView workflows" do
    test "inspects and requeues stale replacement jobs from rendered recovery controls" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      inspect_workflow =
        stale_replacement_workflow!(org, mission, dashboard, "inspect")

      inspect_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{inspect_workflow.correction_request.backfill_lifecycle_event_id}"

      {:ok, inspect_view, _html} = live(conn, inspect_path)
      render_dashboard_async(inspect_view)

      assert has_element?(
               inspect_view,
               ~s(#dashboard-historical-workflow-group-recovery-closure-readiness[data-historical-workflow-group-recovery-closure-action="inspect_stale_replacement_jobs"][data-historical-workflow-group-recovery-closure-stale-jobs="1"][data-historical-workflow-group-recovery-closure-stale-runs="#{inspect_workflow.correction_request.backfill_run_id}"])
             )

      assert has_element?(
               inspect_view,
               ~s(#dashboard-historical-workflow-stale-replacement-inspect-#{inspect_workflow.correction_request.backfill_run_id}[data-workflow-action-id="inspect_stale_replacement_job"][data-workflow-action-replacement-run="#{inspect_workflow.correction_request.backfill_run_id}"][data-workflow-action-job-id="#{inspect_workflow.replacement_job.job_id}"][data-workflow-action-event-id="#{inspect_workflow.correction_request.backfill_lifecycle_event_id}"])
             )

      inspect_view
      |> element(
        "#dashboard-historical-workflow-stale-replacement-inspect-#{inspect_workflow.correction_request.backfill_run_id}"
      )
      |> render_click()

      assert_patch(inspect_view)

      assert [_, inspection_event] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: inspect_workflow.correction_request.backfill_run_id
               )

      assert inspection_event.event_type == :backfill_stale_replacement_inspected

      assert inspection_event.payload["stale_replacement_action"] ==
               "inspect_stale_replacement_job"

      assert inspection_event.payload["stale_replacement_run_id"] ==
               inspect_workflow.correction_request.backfill_run_id

      assert inspection_event.payload["stale_replacement_job_id"] ==
               inspect_workflow.replacement_job.job_id

      assert inspection_event.payload["dashboard_context"] == dashboard_context_payload(dashboard)

      assert has_element?(
               inspect_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="stale_replacement_job_inspection"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="stale_replacement_job_inspection_recorded"][data-workflow-latest-action-result-event-ids="#{inspection_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{inspection_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="#{inspect_workflow.correction_request.backfill_run_id}"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               inspection_event.backfill_lifecycle_event_id
             )

      requeue_workflow =
        stale_replacement_workflow!(org, mission, dashboard, "requeue")

      requeue_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{requeue_workflow.correction_request.backfill_lifecycle_event_id}"

      {:ok, requeue_view, _html} = live(conn, requeue_path)
      render_dashboard_async(requeue_view)

      assert has_element?(
               requeue_view,
               ~s(#dashboard-historical-workflow-stale-replacement-requeue-#{requeue_workflow.correction_request.backfill_run_id}[data-workflow-action-id="requeue_stale_replacement_job"][data-workflow-action-replacement-run="#{requeue_workflow.correction_request.backfill_run_id}"][data-workflow-action-job-id="#{requeue_workflow.replacement_job.job_id}"][data-workflow-action-event-id="#{requeue_workflow.correction_request.backfill_lifecycle_event_id}"])
             )

      requeue_view
      |> element(
        "#dashboard-historical-workflow-stale-replacement-requeue-#{requeue_workflow.correction_request.backfill_run_id}"
      )
      |> render_click()

      assert_patch(requeue_view)

      assert {:ok, requeued_job} =
               Cadence.fetch_background_job(requeue_workflow.replacement_job.job_id)

      assert requeued_job.status == :queued
      assert requeued_job.started_at == nil

      assert [_, requeue_event] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: requeue_workflow.correction_request.backfill_run_id
               )

      assert requeue_event.event_type == :backfill_stale_replacement_requeued
      assert requeue_event.payload["stale_replacement_action"] == "requeue_stale_replacement_job"

      assert requeue_event.payload["stale_replacement_run_id"] ==
               requeue_workflow.correction_request.backfill_run_id

      assert requeue_event.payload["stale_replacement_job_id"] ==
               requeue_workflow.replacement_job.job_id

      assert requeue_event.payload["stale_replacement_requeued_job_status"] == "queued"
      assert requeue_event.payload["dashboard_context"] == dashboard_context_payload(dashboard)

      assert has_element?(
               requeue_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="stale_replacement_job_requeue"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="stale_replacement_job_requeue_recorded"][data-workflow-latest-action-job-id="#{requeue_workflow.replacement_job.job_id}"][data-workflow-latest-action-result-event-ids="#{requeue_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{requeue_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="#{requeue_workflow.correction_request.backfill_run_id}"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Requeued stale replacement job #{requeue_workflow.replacement_job.job_id}"
             )
    end

    test "renders mixed missing failed and stale replacement recovery action queue" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      request_group_id = "dashboard-mixed-replacement-recovery-group"
      prefix = "dashboard-mixed-replacement-recovery"

      missing_workflow =
        replacement_workflow!(org, mission, dashboard, "missing",
          prefix: prefix,
          request_group_id: request_group_id,
          item_index: 1,
          item_count: 3,
          replacement_job: :missing
        )

      failed_workflow =
        replacement_workflow!(org, mission, dashboard, "failed",
          prefix: prefix,
          request_group_id: request_group_id,
          item_index: 2,
          item_count: 3,
          replacement_job: :failed
        )

      stale_workflow =
        replacement_workflow!(org, mission, dashboard, "stale",
          prefix: prefix,
          request_group_id: request_group_id,
          item_index: 3,
          item_count: 3,
          replacement_job: :stale
        )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{missing_workflow.correction_request.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)
      html = render(view)

      closure_selector = "#dashboard-historical-workflow-group-recovery-closure-readiness"

      assert element_attribute(
               html,
               closure_selector,
               "data-historical-workflow-group-recovery-closure-action"
             ) == "inspect_missing_replacement_jobs"

      closure_actions =
        element_attribute(
          html,
          closure_selector,
          "data-historical-workflow-group-recovery-closure-actions"
        )

      assert String.contains?(closure_actions, "inspect_missing_replacement_jobs")

      assert String.contains?(closure_actions, "retry_failed_replacement_jobs") or
               String.contains?(closure_actions, "inspect_failed_replacement_jobs")

      assert String.contains?(closure_actions, "inspect_stale_replacement_jobs")

      assert element_attribute(
               html,
               closure_selector,
               "data-historical-workflow-group-recovery-closure-blocked-jobs"
             ) == "2"

      assert element_attribute(
               html,
               closure_selector,
               "data-historical-workflow-group-recovery-closure-failed-jobs"
             ) == "1"

      assert element_attribute(
               html,
               closure_selector,
               "data-historical-workflow-group-recovery-closure-missing-jobs"
             ) == "1"

      assert element_attribute(
               html,
               closure_selector,
               "data-historical-workflow-group-recovery-closure-stale-jobs"
             ) == "1"

      if String.contains?(closure_actions, "retry_failed_replacement_jobs") do
        assert has_element?(
                 view,
                 ~s(#dashboard-historical-workflow-group-retry-failed-replacements[data-workflow-action-id="retry_failed_replacement_jobs"][data-workflow-action-retry-run-ids="#{failed_workflow.correction_request.backfill_run_id}"][data-workflow-action-eligible-count="1"])
               )
      end

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-missing-replacement-inspect-#{missing_workflow.correction_request.backfill_run_id}[data-workflow-action-id="inspect_missing_replacement_job"][data-workflow-action-request-group="#{request_group_id}"][data-workflow-action-replacement-run="#{missing_workflow.correction_request.backfill_run_id}"])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-group-recovery-remaining-work-replacement-run="#{failed_workflow.correction_request.backfill_run_id}"][data-historical-workflow-group-recovery-remaining-work-job-id="#{failed_workflow.replacement_job.job_id}"][data-historical-workflow-group-recovery-remaining-work-event-id="#{failed_workflow.correction_request.backfill_lifecycle_event_id}"][data-historical-workflow-group-recovery-remaining-work-job-action="inspect_failed_replacement_job"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-stale-replacement-inspect-#{stale_workflow.correction_request.backfill_run_id}[data-workflow-action-id="inspect_stale_replacement_job"][data-workflow-action-replacement-run="#{stale_workflow.correction_request.backfill_run_id}"][data-workflow-action-job-id="#{stale_workflow.replacement_job.job_id}"][data-workflow-action-event-id="#{stale_workflow.correction_request.backfill_lifecycle_event_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-stale-replacement-requeue-#{stale_workflow.correction_request.backfill_run_id}[data-workflow-action-id="requeue_stale_replacement_job"][data-workflow-action-replacement-run="#{stale_workflow.correction_request.backfill_run_id}"][data-workflow-action-job-id="#{stale_workflow.replacement_job.job_id}"][data-workflow-action-event-id="#{stale_workflow.correction_request.backfill_lifecycle_event_id}"])
             )
    end
  end
end
