defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCorrectionCompletionLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Protocol.RecordArchive.Postgres.PacketRecordRow
  alias Cadence.Repo
  alias Cadence.Telemetry.{HistoryStore, Sample, Storage}
  alias Cadence.Telemetry.HistoryStore.ETS, as: HistoryStoreETS
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

  defp persist_sample_scope!(%Sample{} = sample) do
    raw_evidence =
      RawEvidence.new(%{
        evidence_id: sample.evidence_id,
        mission_id: sample.mission_id,
        spacecraft_id: sample.spacecraft_id,
        protocol_family: :space_packet,
        direction: :downlink,
        raw: <<0, 1, 2, 3>>,
        source_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        source_ref: "dashboard-correction-completion-live-test",
        metadata: %{}
      })

    packet_record = %PacketRecord{
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      mission_id: sample.mission_id,
      spacecraft_id: sample.spacecraft_id,
      protocol_family: :space_packet,
      packet_kind: :space_packet,
      apid: 1,
      sequence_flags: 3,
      sequence_count: 1,
      secondary_header?: false,
      packet_data: <<0, 1, 2, 3>>,
      source_time: sample.generation_time,
      receipt_time: sample.receipt_time,
      provenance: %{}
    }

    {:ok, _raw_evidence_row} = Repo.insert(RawEvidenceRow.changeset(raw_evidence))
    {:ok, _packet_record_row} = Repo.insert(PacketRecordRow.changeset(packet_record))

    :ok
  end

  defp telemetry_sample(mission, sample_id, point_id, generation_time, receipt_time, opts) do
    %Sample{
      sample_id: sample_id,
      mission_id: mission.mission_id,
      spacecraft_id: Keyword.get(opts, :spacecraft_id, "sc-dashboard-telemetry"),
      point_id: point_id,
      point_name: point_id,
      packet_definition_id:
        Keyword.get(opts, :packet_definition_id, "packet-def-dashboard-telemetry"),
      packet_definition_version: 1,
      packet_id: Keyword.get(opts, :packet_id, "packet-dashboard-telemetry"),
      evidence_id: Keyword.get(opts, :evidence_id, "evidence-dashboard-telemetry"),
      raw_value: Keyword.fetch!(opts, :raw_value),
      engineering_value: Keyword.fetch!(opts, :engineering_value),
      quality_state: :good,
      generation_time: generation_time,
      receipt_time: receipt_time,
      provenance: Keyword.get(opts, :provenance, %{})
    }
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views =
      Process.get(:ops_dashboard_historical_workflow_correction_completion_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_correction_completion_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_correction_completion_view, pid}, fn ->
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

  describe "historical workflow correction and completion surfaces" do
    test "records replay corrected import workflow requests from the lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "import",
                 "failed",
                 %{
                   import_run_id: "dashboard-import-run-nonretryable",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "replay_run",
                       "dashboard_replay_run_id" => "replay-import-correction-1",
                       "dashboard_data_view" => "all_revisions",
                       "dashboard_limit_mode" => "compare"
                     },
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:point_id",
                         "retryable" => false,
                         "retry_blockers" => ["missing point_id"],
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert event.event_type == :import_failed
      assert event.backfill_run_id == "dashboard-import-run-nonretryable"

      assert {:ok, job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-import-run-nonretryable",
                 %{
                   "workflow" => "import",
                   "attrs" => %{"import_run_id" => "dashboard-import-run-nonretryable"}
                 }
               )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :missing_point_id)
      assert failed_job.status == :failed

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}&time_mode=replay_run&replay_run_id=replay-import-correction-1&data_view=all_revisions&limit_mode=compare"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-guidance[data-historical-workflow-job-guidance-next-action="create_corrected_request"][data-historical-workflow-job-guidance-retry-eligible="false"][data-historical-workflow-job-guidance-retry-reason="correction_required"][data-historical-workflow-job-guidance-correction-eligible="true"][data-historical-workflow-job-guidance-correction-reason="correction_request_required"]),
               "Create a corrected request for failed event"
             )

      refute has_element?(view, "#dashboard-historical-workflow-retry-job")
      assert has_element?(view, "#dashboard-historical-workflow-correction-form")

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-correction-dashboard-time-mode[value="replay_run"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-correction-dashboard-replay-run-id[value="replay-import-correction-1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-correction-dashboard-data-view[value="all_revisions"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-correction-dashboard-limit-mode[value="compare"])
             )

      view
      |> element("#dashboard-historical-workflow-correction-form")
      |> render_submit(%{
        "historical_workflow_correction" => %{
          "workflow" => "import",
          "run_id" => "dashboard-import-run-corrected",
          "original_run_id" => "dashboard-import-run-nonretryable",
          "original_event_id" => event.backfill_lifecycle_event_id,
          "original_job_id" => job.job_id,
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "observable_id" => "HK.counter",
          "point_id" => "HK.counter",
          "source_from" => "2026-06-22T14:00:00Z",
          "source_to" => "2026-06-22T15:00:00Z",
          "reason" => "operator_corrected_import_missing_point",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-import-correction-1",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "compare",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      assert [corrected] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-import-run-corrected"
               )

      assert corrected.event_type == :import_requested
      assert corrected.payload["correction_source"] == "dashboard_correction_request"
      assert corrected.payload["corrects_event_id"] == event.backfill_lifecycle_event_id
      assert corrected.payload["corrects_job_id"] == job.job_id

      assert corrected.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-import-correction-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "compare"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="correction_request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="correction_request_recorded"][data-workflow-latest-action-result-event-ids="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-corrected"][data-workflow-latest-action-dashboard-time-mode="replay_run"][data-workflow-latest-action-dashboard-replay-run-id="replay-import-correction-1"][data-workflow-latest-action-dashboard-data-view="all_revisions"][data-workflow-latest-action-dashboard-limit-mode="compare"]),
               "Corrected historical data workflow request recorded."
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_id=#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-href*="time_mode=replay_run"][data-workflow-latest-action-handoff-href*="replay_run_id=replay-import-correction-1"][data-workflow-latest-action-handoff-href*="data_view=all_revisions"][data-workflow-latest-action-handoff-href*="limit_mode=compare"]),
               "Selected result"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event type"]),
               "import_failed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event"]),
               event.backfill_lifecycle_event_id
             )
    end

    test "shows completed corrected import workflow evidence in the lifecycle inspector" do
      previous_history_store = Application.get_env(:cadence, :telemetry_history_store, [])

      Application.put_env(:cadence, :telemetry_history_store,
        module: HistoryStoreETS,
        max_samples_per_point: :infinity
      )

      start_supervised!(HistoryStoreETS)
      HistoryStoreETS.reset()

      on_exit(fn ->
        Application.put_env(:cadence, :telemetry_history_store, previous_history_store)
      end)

      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, failed_source_job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-import-run-correction-completed-source",
                 %{
                   "workflow" => "import",
                   "attrs" => %{
                     "import_run_id" => "dashboard-import-run-correction-completed-source"
                   }
                 }
               )

      assert [claimed_failed_source_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_failed_source_job.job_id == failed_source_job.job_id

      assert {:ok, failed_source_job} =
               Cadence.Jobs.fail_worker_start(failed_source_job.job_id, :missing_point_id)

      assert {:ok, source_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "import",
                 "failed",
                 %{
                   import_run_id: "dashboard-import-run-correction-completed-source",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 14:00:00Z],
                   source_to: ~U[2026-06-22 15:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-import-run-correction-completed",
                     "request_item_index" => 1,
                     "request_item_count" => 1,
                     "request_item_run_id" => "dashboard-import-run-correction-completed-source",
                     "job_id" => failed_source_job.job_id,
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "archive",
                       "dashboard_data_view" => "as_recorded",
                       "dashboard_limit_mode" => "observed"
                     },
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

      assert {:ok, _correction_request} =
               Cadence.record_telemetry_historical_data_workflow_correction_request(
                 "import",
                 %{
                   import_run_id: "dashboard-import-run-correction-completed-fixed",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 14:00:00Z],
                   source_to: ~U[2026-06-22 15:00:00Z],
                   authority: :unknown,
                   reason: "operator_corrected_completed_import"
                 },
                 %{"original_event_id" => source_event.backfill_lifecycle_event_id},
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, [_approved], [{:ok, nil}]} =
               Cadence.record_telemetry_historical_data_workflow_group_transition(
                 "import",
                 "approved",
                 "dashboard-import-run-correction-completed",
                 %{
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   authority: :authoritative,
                   reason: "operator_approved_completed_import"
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, [_started], [{:ok, started_job}]} =
               Cadence.record_telemetry_historical_data_workflow_group_transition(
                 "import",
                 "started",
                 "dashboard-import-run-correction-completed",
                 %{
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   authority: :authoritative,
                   reason: "operator_started_completed_import"
                 },
                 dashboard_runtime_invalidation?: false
               )

      source_sample =
        telemetry_sample(
          mission,
          "dashboard-import-completed-correction-source-sample",
          "HK.counter",
          ~U[2026-06-22 14:10:00Z],
          ~U[2026-06-22 14:10:03Z],
          raw_value: 91,
          engineering_value: 91,
          provenance: %{
            "storage" => %{
              "realm" => "backfill",
              "data_source_id" => "customer_archive_import",
              "binding_id" => "import_telemetry"
            }
          }
        )

      assert :ok = persist_sample_scope!(source_sample)
      assert :ok = HistoryStore.persist_samples([source_sample])
      assert [claimed_started_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_started_job.job_id == started_job.job_id
      assert {:ok, completed_job} = JobRunner.run_job(started_job.job_id)
      assert completed_job.status == :completed

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-import-run-correction-completed-fixed"
        )

      assert Enum.map(events, & &1.event_type) == [
               :import_requested,
               :import_approved,
               :import_started,
               :import_completed
             ]

      completed_event = List.last(events)

      completed_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{completed_event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, completed_path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_completed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow job"]),
               started_job.job_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow job status"]),
               "completed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event type"]),
               "import_failed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event"]),
               source_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source job"]),
               failed_source_job.job_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{started_job.job_id}"][data-historical-workflow-job-status="completed"])
             )

      assert has_element?(
               view,
               ~s([data-data-link-related-id="#{source_event.backfill_lifecycle_event_id}"]),
               "Correction source event"
             )
    end
  end
end
