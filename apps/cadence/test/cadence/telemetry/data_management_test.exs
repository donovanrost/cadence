defmodule Cadence.Telemetry.DataManagementTest do
  use Cadence.DataCase, async: false

  alias Cadence.Persistence.Schemas.BackgroundJobRow
  alias Cadence.Repo
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.HistoryStore
  alias Cadence.Telemetry.HistoryStore.ETS, as: HistoryStoreETS
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage

  setup do
    previous_storage_config = Application.get_env(:cadence, :telemetry_storage, [])
    previous_history_store = Application.get_env(:cadence, :telemetry_history_store, [])

    previous_current_value_store =
      Application.get_env(:cadence, :telemetry_current_value_store, [])

    Application.put_env(:cadence, :telemetry_storage,
      writer: Cadence.TestSupport.CapturingTelemetryStorageWriter,
      writer_opts: [test_pid: self()],
      realm: :flight,
      data_source_id: "managed_questdb_primary",
      binding_id: "default_flight_telemetry",
      dashboard_runtime_invalidation?: false
    )

    Application.put_env(:cadence, :telemetry_current_value_store,
      module: Cadence.Telemetry.CurrentValueStore.ETS
    )

    Application.put_env(:cadence, :telemetry_history_store,
      module: HistoryStoreETS,
      max_samples_per_point: :infinity
    )

    start_supervised!(HistoryStoreETS)
    HistoryStoreETS.reset()

    start_supervised!(Cadence.Telemetry.CurrentValueStore.ETS)
    CurrentValueStore.reset()

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_storage, previous_storage_config)
      Application.put_env(:cadence, :telemetry_history_store, previous_history_store)
      Application.put_env(:cadence, :telemetry_current_value_store, previous_current_value_store)
    end)

    :ok
  end

  test "historical workflow action policy owns stage and recovery eligibility" do
    assert %{
             id: "stage_approved",
             kind: :stage,
             eligible?: true,
             disabled?: false,
             reason: "stage_transition_available"
           } =
             Cadence.telemetry_historical_data_workflow_stage_action_policy(
               %{"stage" => "requested"},
               "approved"
             )

    assert %{
             eligible?: false,
             disabled?: true,
             reason: "job_already_exists"
           } =
             Cadence.telemetry_historical_data_workflow_stage_action_policy(
               %{
                 stage: "approved",
                 job_id: "job-1",
                 job_status: "queued"
               },
               "started"
             )

    assert %{
             id: "group_stage_completed",
             kind: :group_stage,
             eligible?: true,
             disabled?: false,
             eligible_count: 2,
             reason: "eligible_group_items"
           } =
             Cadence.telemetry_historical_data_workflow_group_stage_action_policy(
               %{
                 request_group_id: "group-1",
                 request_group_complete_eligible: "2"
               },
               "completed"
             )

    actions =
      Cadence.telemetry_historical_data_workflow_action_policy(%{
        request_group_id: "group-1",
        request_group_retryable_failed: "0",
        event_id: "event-1",
        job_id: "job-1",
        job_status: "failed",
        retryable: "true",
        recovery_action: "correct_workflow_request"
      })

    assert actions.retry_job.reason == "correction_required"
    refute actions.retry_job.eligible?
    assert actions.retry_group_failed_jobs.reason == "no_retryable_group_failures"
    refute actions.retry_group_failed_jobs.eligible?
    assert actions.correction_request.reason == "correction_request_required"
    assert actions.correction_request.eligible?
  end

  test "records historical workflow stage transitions through product action policy" do
    assert {:ok, requested} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "requested",
               %{
                 backfill_lifecycle_event_id: "stage-transition-requested",
                 backfill_run_id: "stage-transition-run",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 reason: "operator_requested_backfill",
                 payload: %{
                   "dashboard_context" => %{
                     "dashboard_id" => "dashboard-stage",
                     "dashboard_version" => "3",
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-stage-product",
                     "dashboard_data_view" => "all_revisions",
                     "dashboard_limit_mode" => "observed"
                   },
                   "comparison_review_origin" => %{
                     "request_event_id" => "review-request-stage",
                     "request_kind" => "comparison_open_findings_review",
                     "open_count" => "1",
                     "open_placement_ids" => "placement-stage"
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error,
            {:historical_workflow_stage_transition_blocked, "stage-transition-requested",
             "stage_transition_out_of_order"}} =
             Cadence.record_telemetry_historical_data_workflow_stage_transition(
               "backfill",
               "completed",
               requested.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 reason: "operator_completed_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, approved} =
             Cadence.record_telemetry_historical_data_workflow_stage_transition(
               "backfill",
               "approved",
               requested.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 reason: "operator_approved_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert approved.event_type == :backfill_approved
    assert approved.backfill_run_id == requested.backfill_run_id
    assert approved.payload["stage_transition_source"] == "dashboard_stage_action"
    assert approved.payload["source_event_id"] == requested.backfill_lifecycle_event_id
    assert approved.payload["source_event_type"] == "backfill_requested"

    assert approved.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-stage",
             "dashboard_version" => "3",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-stage-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert approved.payload["comparison_review_origin"] == %{
             "request_event_id" => "review-request-stage",
             "request_kind" => "comparison_open_findings_review",
             "open_count" => "1",
             "open_placement_ids" => "placement-stage"
           }

    assert {:error,
            {:historical_workflow_stage_transition_blocked, blocked_event_id, "already_in_stage"}} =
             Cadence.record_telemetry_historical_data_workflow_stage_transition(
               "backfill",
               "approved",
               approved.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 reason: "operator_approved_backfill_again"
               },
               dashboard_runtime_invalidation?: false
             )

    assert blocked_event_id == approved.backfill_lifecycle_event_id
  end

  test "historical workflow explanation summary owns lifecycle state semantics" do
    assert %{
             severity: :warning,
             state: "late_data_rejected",
             badge: "rejected",
             reason: "late_data_rejected"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               event_type: "late_data_rejected",
               stage: "completed"
             })

    assert %{
             severity: :error,
             state: "failed_correction_required",
             badge: "correction",
             reason: "failed_correction_required"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               "stage" => "failed",
               "retryable" => "false"
             })

    assert %{
             severity: :warning,
             state: "dispatch_failed",
             badge: "degraded",
             reason: "workflow_dispatch_failed"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               stage: "started",
               job_status: "failed"
             })

    assert %{
             severity: :warning,
             state: "correction",
             badge: "correction",
             reason: "correction_replacement_event"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               correction_source_event_id: "failed-event-1"
             })

    assert %{
             severity: :info,
             state: "backfill_requested",
             badge: "recorded",
             reason: "historical_data_workflow_recorded"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               event_type: "backfill_requested"
             })
  end

  test "late-data policy execution mode is product-owned" do
    assert :sample_execution =
             Cadence.telemetry_late_data_policy_execution_mode(%{
               point_id: "HK.counter",
               source_from: "2026-06-22T10:00:00Z",
               source_to: "2026-06-22T11:00:00Z"
             })

    assert :sample_execution =
             Cadence.telemetry_late_data_policy_execution_mode(%{
               point_id: "HK.counter",
               source_from: ~U[2026-06-22 10:00:00Z],
               source_to: ~U[2026-06-22 11:00:00Z]
             })

    assert :event_only =
             Cadence.telemetry_late_data_policy_execution_mode(%{
               observable_id: "HK.counter",
               source_from: "2026-06-22T10:00:00Z",
               source_to: "2026-06-22T11:00:00Z"
             })
  end

  test "event-only late-data policy records audit semantics without projection claims" do
    assert {:ok, event} =
             Cadence.record_telemetry_late_data_policy_decision(
               :accept,
               %{
                 backfill_run_id: "late-policy-event-only",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry",
                 execution_mode: "event_only",
                 payload: %{
                   "dashboard_context" => %{
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-policy-product",
                     "dashboard_limit_mode" => "compare"
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.event_type == :late_data_accepted
    assert event.payload["execution_mode"] == "event_only"
    assert event.payload["projection_effect"] == "audit_event_only"
    refute event.payload["record_current_values"]
    refute event.payload["refresh_latest_value"]

    assert event.payload["dashboard_context"] == %{
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-policy-product",
             "dashboard_limit_mode" => "compare"
           }
  end

  test "late-data policy write opts lock projection semantics" do
    assert {:ok, accept_opts} =
             Cadence.telemetry_late_data_policy_write_opts("accept",
               metadata: %{"caller" => "dashboard"},
               validity_state: :advisory,
               record_current_values?: false
             )

    assert Keyword.fetch!(accept_opts, :late_data?)
    assert Keyword.fetch!(accept_opts, :backfill_lifecycle_event_type) == :late_data_accepted
    assert Keyword.fetch!(accept_opts, :validity_state) == :canonical
    assert Keyword.fetch!(accept_opts, :record_current_values?)
    assert Keyword.fetch!(accept_opts, :refresh_latest_value?)
    assert Keyword.fetch!(accept_opts, :authority) == :authoritative
    assert Keyword.fetch!(accept_opts, :metadata)["caller"] == "dashboard"

    assert Keyword.fetch!(accept_opts, :metadata)["late_data_projection_effect"] ==
             "canonical_history_and_current_projection"

    assert {:ok, reject_opts} =
             Cadence.telemetry_late_data_policy_write_opts(:reject,
               metadata: %{"caller" => "dashboard"},
               validity_state: :canonical,
               record_current_values?: true,
               refresh_latest_value?: true
             )

    assert Keyword.fetch!(reject_opts, :late_data?)
    assert Keyword.fetch!(reject_opts, :backfill_lifecycle_event_type) == :late_data_rejected
    assert Keyword.fetch!(reject_opts, :validity_state) == :advisory
    refute Keyword.fetch!(reject_opts, :record_current_values?)
    refute Keyword.fetch!(reject_opts, :refresh_latest_value?)
    assert Keyword.fetch!(reject_opts, :authority) == :advisory
    assert Keyword.fetch!(reject_opts, :metadata)["caller"] == "dashboard"

    assert Keyword.fetch!(reject_opts, :metadata)["late_data_projection_effect"] ==
             "advisory_history_only"

    assert {:error, {:unsupported_late_data_policy_decision, "quarantine"}} =
             Cadence.telemetry_late_data_policy_write_opts("quarantine")
  end

  test "late-data policy write opts drive current projection behavior" do
    baseline =
      sample("sample-late-policy-baseline", ~U[2026-06-22 10:00:00Z], ~U[2026-06-22 10:00:03Z],
        raw_value: 10
      )

    accepted =
      sample("sample-late-policy-accepted", ~U[2026-06-22 10:05:00Z], ~U[2026-06-22 12:05:03Z],
        raw_value: 20
      )

    rejected =
      sample("sample-late-policy-rejected", ~U[2026-06-22 10:10:00Z], ~U[2026-06-22 12:10:03Z],
        raw_value: 99
      )

    assert :ok = Storage.persist_samples([baseline], organization_id: "org-product")
    assert_receive {:telemetry_storage_envelopes, [_baseline_envelope]}

    assert {:ok, accept_opts} =
             Cadence.telemetry_late_data_policy_write_opts(:accept,
               organization_id: "org-product",
               backfill_run_id: "late-policy-accept-run",
               recorded_at: ~U[2026-06-22 12:05:05Z],
               dashboard_runtime_invalidation?: false
             )

    assert :ok = Storage.persist_samples([accepted], accept_opts)
    assert_receive {:telemetry_storage_envelopes, [_accepted_envelope]}

    latest =
      Cadence.latest_telemetry_value("mission-product", "HK.counter", spacecraft_id: "sc-1")

    assert latest.sample_id == "sample-late-policy-accepted"
    assert latest.raw_value == 20
    assert latest.provenance["storage"]["validity_state"] == "canonical"

    assert {:ok, reject_opts} =
             Cadence.telemetry_late_data_policy_write_opts(:reject,
               organization_id: "org-product",
               backfill_run_id: "late-policy-reject-run",
               recorded_at: ~U[2026-06-22 12:10:05Z],
               dashboard_runtime_invalidation?: false
             )

    assert :ok = Storage.persist_samples([rejected], reject_opts)
    assert_receive {:telemetry_storage_envelopes, [_rejected_envelope]}

    latest =
      Cadence.latest_telemetry_value("mission-product", "HK.counter", spacecraft_id: "sc-1")

    assert latest.sample_id == "sample-late-policy-accepted"
    assert latest.raw_value == 20
  end

  test "executes accepted late-data policy by selecting source samples and writing canonical history" do
    assert :ok =
             HistoryStore.persist_samples([
               sample(
                 "sample-late-source-before",
                 ~U[2026-06-22 09:59:00Z],
                 ~U[2026-06-22 11:59:03Z],
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 raw_value: 9
               ),
               sample(
                 "sample-late-source-selected",
                 ~U[2026-06-22 10:10:00Z],
                 ~U[2026-06-22 12:10:03Z],
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 raw_value: 42
               )
             ])

    assert {:ok, %{event: event, sample_count: 1, diagnostics: diagnostics}} =
             Cadence.execute_telemetry_late_data_policy(
               :accept,
               %{
                 backfill_run_id: "late-policy-execute-accept",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry",
                 source_realm: :backfill,
                 source_data_source_id: "managed_questdb_backfill",
                 source_binding_id: "backfill_telemetry",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 10:30:00Z],
                 receipt_from: ~U[2026-06-22 12:00:00Z],
                 receipt_to: ~U[2026-06-22 12:30:00Z],
                 reason: "operator_accepts_late_data"
               },
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-late-source-selected"
    assert envelope.realm == :flight
    assert envelope.data_source_id == "managed_questdb_primary"
    assert envelope.binding_id == "default_flight_telemetry"
    assert envelope.validity_state == :canonical

    assert event.event_type == :late_data_accepted
    assert event.sample_count == 1
    assert event.payload["selected_sample_count"] == 1
    assert event.payload["projection_effect"] == "canonical_history_and_current_projection"
    assert event.payload["source"]["source_identity"]["realm"] == "backfill"
    assert diagnostics["point_id"] == "HK.counter"
  end

  test "executes rejected late-data policy as advisory history without current projection" do
    baseline =
      sample("sample-late-reject-baseline", ~U[2026-06-22 10:00:00Z], ~U[2026-06-22 10:00:03Z],
        raw_value: 10
      )

    late =
      sample("sample-late-reject-source", ~U[2026-06-22 10:20:00Z], ~U[2026-06-22 12:20:03Z],
        realm: :backfill,
        data_source_id: "managed_questdb_backfill",
        binding_id: "backfill_telemetry",
        raw_value: 99
      )

    assert :ok = Storage.persist_samples([baseline], organization_id: "org-product")
    assert_receive {:telemetry_storage_envelopes, [_baseline_envelope]}
    assert :ok = HistoryStore.persist_samples([late])

    assert {:ok, %{event: event, sample_count: 1}} =
             Cadence.execute_telemetry_late_data_policy(
               "reject",
               %{
                 backfill_run_id: "late-policy-execute-reject",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry",
                 source_realm: :backfill,
                 source_data_source_id: "managed_questdb_backfill",
                 source_binding_id: "backfill_telemetry",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:10:00Z],
                 source_to: ~U[2026-06-22 10:30:00Z],
                 receipt_from: ~U[2026-06-22 12:10:00Z],
                 receipt_to: ~U[2026-06-22 12:30:00Z],
                 reason: "operator_rejects_late_data"
               },
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-late-reject-source"
    assert envelope.validity_state == :advisory

    latest =
      Cadence.latest_telemetry_value("mission-product", "HK.counter", spacecraft_id: "sc-1")

    assert latest.sample_id == "sample-late-reject-baseline"
    assert latest.raw_value == 10

    assert event.event_type == :late_data_rejected
    assert event.sample_count == 1
    assert event.payload["projection_effect"] == "advisory_history_only"
    assert event.payload["record_current_values"] == false
    assert event.payload["refresh_latest_value"] == false
  end

  test "backfills telemetry samples through storage with lifecycle events" do
    samples = [
      sample("sample-backfill-1", ~U[2026-06-22 11:00:00Z], ~U[2026-06-22 12:00:03Z]),
      sample("sample-backfill-2", ~U[2026-06-22 11:05:00Z], ~U[2026-06-22 12:05:03Z])
    ]

    assert :ok =
             Cadence.backfill_telemetry_samples(
               samples,
               %{
                 backfill_run_id: "backfill-run-product",
                 organization_id: "org-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 source_endpoint_id: "station-a",
                 recorded_at: ~U[2026-06-22 12:05:05Z],
                 actor_id: "operator-1",
                 actor_kind: "user"
               },
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, envelopes}
    assert Enum.map(envelopes, & &1.sample_id) == ["sample-backfill-1", "sample-backfill-2"]
    assert Enum.all?(envelopes, &(&1.realm == :backfill))
    assert Enum.all?(envelopes, &(&1.data_source_id == "managed_questdb_backfill"))
    assert Enum.all?(envelopes, &(&1.binding_id == "backfill_telemetry"))

    events =
      "mission-product"
      |> Storage.list_backfill_lifecycle_events(
        organization_id: "org-product",
        backfill_run_id: "backfill-run-product"
      )
      |> Enum.sort_by(&event_stage_order/1)

    assert Enum.map(events, & &1.event_type) == [
             :backfill_requested,
             :backfill_approved,
             :backfill_started,
             :backfill_completed
           ]

    assert Enum.all?(events, &(&1.sample_count == 2))
    assert Enum.all?(events, &(&1.source_from == ~U[2026-06-22 11:00:00.000000Z]))
    assert Enum.all?(events, &(&1.source_to == ~U[2026-06-22 11:05:00.000000Z]))
    assert Enum.all?(events, &(&1.receipt_from == ~U[2026-06-22 12:00:03.000000Z]))
    assert Enum.all?(events, &(&1.receipt_to == ~U[2026-06-22 12:05:03.000000Z]))
    assert Enum.all?(events, &(&1.observable_id == "HK.counter"))
    assert Enum.all?(events, &(&1.spacecraft_id == "sc-1"))
  end

  test "imports telemetry samples through storage with lifecycle events" do
    samples = [sample("sample-import-1", ~U[2026-06-22 11:00:00Z], ~U[2026-06-22 12:00:03Z])]

    assert :ok =
             Cadence.import_telemetry_samples(
               samples,
               %{
                 import_run_id: "import-run-product",
                 organization_id: "org-product",
                 realm: :rehearsal,
                 data_source_id: "managed_questdb_rehearsal",
                 binding_id: "rehearsal_telemetry",
                 source_endpoint_id: "station-a",
                 recorded_at: ~U[2026-06-22 12:00:05Z]
               },
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-import-1"
    assert envelope.realm == :rehearsal
    assert envelope.data_source_id == "managed_questdb_rehearsal"
    assert envelope.binding_id == "rehearsal_telemetry"

    events =
      "mission-product"
      |> Storage.list_backfill_lifecycle_events(
        organization_id: "org-product",
        backfill_run_id: "import-run-product"
      )
      |> Enum.sort_by(&event_stage_order/1)

    assert Enum.map(events, & &1.event_type) == [
             :import_requested,
             :import_approved,
             :import_started,
             :import_completed
           ]
  end

  test "records historical data workflow stage events without writing samples" do
    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "requested",
               %{
                 backfill_run_id: "backfill-run-requested",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :advisory,
                 reason: "operator_requested_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.event_type == :backfill_requested
    assert event.backfill_run_id == "backfill-run-requested"
    assert event.authority == :advisory
    assert event.payload["workflow"] == "backfill"
    assert event.payload["stage"] == "requested"
    assert event.payload["run_id"] == "backfill-run-requested"
    assert event.payload["requested_event_type"] == "backfill_requested"

    assert [listed] =
             Storage.list_backfill_lifecycle_events("mission-product",
               organization_id: "org-product",
               backfill_run_id: "backfill-run-requested"
             )

    assert listed.backfill_lifecycle_event_id == event.backfill_lifecycle_event_id
    assert listed.event_type == :backfill_requested
    assert listed.payload["stage"] == "requested"
  end

  test "records historical data workflow requests through the product API" do
    attrs = %{
      backfill_run_id: "backfill-run-request-group",
      organization_id: "org-product",
      mission_id: "mission-product",
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      source_from: ~U[2026-06-22 10:00:00Z],
      source_to: ~U[2026-06-22 11:00:00Z],
      authority: :unknown,
      reason: "operator_requested_backfill",
      actor_id: "operator-2",
      actor_kind: "operator",
      payload: %{
        "dashboard_context" => %{
          "dashboard_id" => "dashboard-power",
          "dashboard_version" => "4"
        },
        "comparison_review_origin" => %{
          "request_event_id" => "review-request-group",
          "request_kind" => "comparison_open_findings_review",
          "open_count" => "2",
          "open_placement_ids" => "placement-counter,placement-voltage",
          "workflow_kind" => "bulk_correction_authority_review",
          "workflow_action" => "request_comparison_review",
          "workflow_selection_kind" => "open_comparison_findings",
          "workflow_selection_count" => "2",
          "primary_data_view" => "all_revisions",
          "compare_data_view" => "canonical"
        },
        "operator_note" => "AI&T replay gap"
      }
    }

    assert {:ok, events} =
             Cadence.record_telemetry_historical_data_workflow_request(
               "backfill",
               attrs,
               ["HK.counter", "HK.voltage"],
               dashboard_runtime_invalidation?: false
             )

    assert Enum.map(events, & &1.backfill_run_id) == [
             "backfill-run-request-group-001",
             "backfill-run-request-group-002"
           ]

    assert Enum.map(events, & &1.point_id) == ["HK.counter", "HK.voltage"]
    assert Enum.all?(events, &(&1.event_type == :backfill_requested))
    assert Enum.all?(events, &(&1.reason == "operator_requested_backfill"))
    assert Enum.all?(events, &(&1.payload["request_mode"] == "bulk_points"))
    assert Enum.map(events, & &1.payload["request_item_index"]) == [1, 2]
    assert Enum.all?(events, &(&1.payload["request_item_count"] == 2))
    assert Enum.all?(events, &(&1.payload["request_group_id"] == "backfill-run-request-group"))
    assert Enum.all?(events, &(&1.payload["operator_note"] == "AI&T replay gap"))

    assert Enum.all?(
             events,
             &(&1.payload["comparison_review_origin"] == %{
                 "request_event_id" => "review-request-group",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => "2",
                 "open_placement_ids" => "placement-counter,placement-voltage",
                 "workflow_kind" => "bulk_correction_authority_review",
                 "workflow_action" => "request_comparison_review",
                 "workflow_selection_kind" => "open_comparison_findings",
                 "workflow_selection_count" => "2",
                 "primary_data_view" => "all_revisions",
                 "compare_data_view" => "canonical"
               })
           )

    assert Enum.all?(
             events,
             &(&1.payload["dashboard_context"] == %{
                 "dashboard_id" => "dashboard-power",
                 "dashboard_version" => "4"
               })
           )

    assert Enum.map(events, & &1.payload["request_item_run_id"]) ==
             ["backfill-run-request-group-001", "backfill-run-request-group-002"]
  end

  test "records single historical data workflow request without an explicit point" do
    assert {:ok, [event]} =
             Cadence.record_telemetry_historical_data_workflow_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-request-single",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :unknown,
                 reason: "operator_requested_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               [],
               dashboard_runtime_invalidation?: false
             )

    assert event.backfill_run_id == "backfill-run-request-single"
    assert event.point_id == nil
    assert event.observable_id == nil
    assert event.payload["request_mode"] == "single_point"
    assert event.payload["request_group_id"] == "backfill-run-request-single"
    assert event.payload["request_item_index"] == 1
    assert event.payload["request_item_count"] == 1
    assert event.payload["request_item_run_id"] == "backfill-run-request-single"
  end

  test "records corrected historical data workflow request through the product API" do
    failed_job = failed_historical_workflow_job("backfill-run-original")

    assert {:ok, source_event} =
             record_group_failed_event(
               "failed-event-original",
               "backfill-run-original",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-original-group",
               item_count: 1,
               job_id: failed_job.job_id,
               point_id: "HK.counter",
               observable_id: "HK.counter",
               dashboard_context: %{
                 "dashboard_id" => "dashboard-correction",
                 "dashboard_version" => "5",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-correction-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :unknown,
                 reason: "operator_corrected_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               %{
                 "original_run_id" => "",
                 "original_event_id" => source_event.backfill_lifecycle_event_id,
                 "original_job_id" => ""
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.event_type == :backfill_requested
    assert event.backfill_run_id == "backfill-run-corrected"
    assert event.payload["recovery_action"] == "correct_workflow_request"
    assert event.payload["correction_source"] == "dashboard_correction_request"
    assert event.payload["correction_source_event_type"] == "backfill_failed"
    assert event.payload["corrects_run_id"] == "backfill-run-original"
    assert event.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert event.payload["corrects_job_id"] == failed_job.job_id
    assert event.payload["request_group_id"] == "backfill-run-original-group"
    assert event.payload["request_item_index"] == 1
    assert event.payload["request_item_count"] == 1
    assert event.payload["workflow"] == "backfill"
    assert event.payload["stage"] == "requested"

    assert event.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-correction",
             "dashboard_version" => "5",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-correction-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }
  end

  test "rejects corrected historical workflow requests without a valid correction source" do
    assert {:error, {:missing_field, :original_event_id}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-minimal",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{
                 "original_run_id" => "",
                 "original_event_id" => "",
                 "original_job_id" => nil
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error, {:historical_workflow_correction_source_not_found, "missing-event"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-missing-source",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => "missing-event"},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, retryable_source_event} =
             record_group_failed_event(
               "failed-event-retryable-source",
               "backfill-run-retryable-source",
               1,
               retryable: true,
               request_group_id: "backfill-run-retryable-source-group",
               item_count: 1
             )

    assert {:error,
            {:invalid_historical_workflow_correction_source, "failed-event-retryable-source",
             :correction_not_required}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-retryable-source",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => retryable_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, backfill_source_event} =
             record_group_failed_event(
               "failed-event-workflow-mismatch-source",
               "backfill-run-workflow-mismatch-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-workflow-mismatch-source-group",
               item_count: 1
             )

    assert {:error,
            {:invalid_historical_workflow_correction_source,
             "failed-event-workflow-mismatch-source", :workflow_mismatch}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "import",
               %{
                 import_run_id: "import-run-corrected-mismatch",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_import"
               },
               %{"original_event_id" => backfill_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, missing_job_source_event} =
             record_group_failed_event(
               "failed-event-missing-job-source",
               "backfill-run-missing-job-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-missing-job-source-group",
               item_count: 1
             )

    assert {:error,
            {:historical_workflow_correction_request_blocked, "failed-event-missing-job-source",
             "job_status_missing"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-missing-job",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => missing_job_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-queued-correction-source",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert {:ok, queued_job_source_event} =
             record_group_failed_event(
               "failed-event-queued-job-source",
               "backfill-run-queued-correction-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-queued-correction-source-group",
               item_count: 1,
               job_id: queued_job.job_id
             )

    assert {:error,
            {:historical_workflow_correction_request_blocked, "failed-event-queued-job-source",
             "job_not_failed"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-queued-job",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => queued_job_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert [claimed_queued_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_queued_job.job_id == queued_job.job_id

    mismatched_failed_job = failed_historical_workflow_job("backfill-run-job-id-mismatch-source")

    assert {:ok, mismatched_job_source_event} =
             record_group_failed_event(
               "failed-event-job-id-mismatch-source",
               "backfill-run-job-id-mismatch-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-job-id-mismatch-source-group",
               item_count: 1,
               job_id: "other-#{mismatched_failed_job.job_id}"
             )

    assert {:error,
            {:historical_workflow_correction_request_blocked,
             "failed-event-job-id-mismatch-source", :job_id_mismatch}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-job-id-mismatch",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => mismatched_job_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )
  end

  test "records corrected historical workflow transitions through the product API" do
    failed_job = failed_historical_workflow_job("backfill-run-correction-transition-source")

    assert {:ok, source_event} =
             record_group_failed_event(
               "failed-event-correction-transition",
               "backfill-run-correction-transition-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-correction-transition-group",
               item_count: 1,
               job_id: failed_job.job_id,
               dashboard_context: %{
                 "dashboard_id" => "dashboard-correction-transition",
                 "dashboard_version" => "6",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-correction-transition-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-correction-transition",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, stale_correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-stale-correction-transition",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill_again"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, approved} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "approved",
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_approved_corrected_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert approved.event_type == :backfill_approved
    assert approved.backfill_run_id == correction_request.backfill_run_id
    assert approved.reason == "operator_approved_corrected_backfill"
    assert approved.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert approved.payload["correction_transition_source_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert approved.payload["requested_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert approved.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert approved.payload["corrects_run_id"] == source_event.backfill_run_id
    assert approved.payload["corrects_job_id"] == failed_job.job_id

    assert approved.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-correction-transition",
             "dashboard_version" => "6",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-correction-transition-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    correction_request_id = correction_request.backfill_lifecycle_event_id

    assert {:error,
            {:historical_workflow_correction_transition_blocked, ^correction_request_id,
             "stage_transition_out_of_order"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "completed",
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_completed_corrected_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, started} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "started",
               approved.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_started_corrected_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert started.event_type == :backfill_started
    assert started.payload["dashboard_context"] == approved.payload["dashboard_context"]

    assert {:ok, completed} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "completed",
               started.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_completed_corrected_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert completed.event_type == :backfill_completed
    assert completed.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert completed.payload["dashboard_context"] == approved.payload["dashboard_context"]

    assert {:error,
            {:historical_workflow_correction_source_superseded,
             "failed-event-correction-transition"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "approved",
               stale_correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_approved_stale_corrected_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error,
            {:historical_workflow_correction_source_superseded,
             "failed-event-correction-transition"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-correction-after-completed",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill_after_completed"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, normal_request} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "requested",
               %{
                 backfill_lifecycle_event_id: "normal-request-event",
                 backfill_run_id: "backfill-run-normal-request",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_requested_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error,
            {:invalid_historical_workflow_correction_event, "normal-request-event",
             :missing_source_event}} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "approved",
               normal_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_approved_normal_request"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "records historical data workflow retry events without writing samples" do
    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "retried",
               %{
                 backfill_run_id: "backfill-run-retried",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :authoritative,
                 reason: "dashboard_historical_workflow_retried",
                 actor_id: "operator-2",
                 actor_kind: "operator",
                 payload: %{
                   "retry_action" => "retry_job",
                   "retry_source_event_id" => "telemetry_backfill_lifecycle_event_failed",
                   "retry_job_id" => "job-retried",
                   "retry_job_status" => "queued"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.event_type == :backfill_retried
    assert event.authority == :authoritative
    assert event.reason == "dashboard_historical_workflow_retried"
    assert event.payload["workflow"] == "backfill"
    assert event.payload["stage"] == "retried"
    assert event.payload["requested_event_type"] == "backfill_retried"
    assert event.payload["retry_action"] == "retry_job"
    assert event.payload["retry_source_event_id"] == "telemetry_backfill_lifecycle_event_failed"
    assert event.payload["retry_job_id"] == "job-retried"
    assert event.payload["retry_job_status"] == "queued"
  end

  test "records historical data workflow group transitions through the product API" do
    requested_events =
      for index <- 1..2 do
        run_id = "backfill-run-group-#{index}"
        point_id = "HK.group#{index}"

        assert {:ok, event} =
                 Cadence.record_telemetry_historical_data_workflow_event(
                   "backfill",
                   "requested",
                   %{
                     backfill_run_id: run_id,
                     organization_id: "org-product",
                     mission_id: "mission-product",
                     realm: :backfill,
                     data_source_id: "managed_questdb_backfill",
                     binding_id: "backfill_telemetry",
                     observable_id: point_id,
                     point_id: point_id,
                     source_from: ~U[2026-06-22 10:00:00Z],
                     source_to: ~U[2026-06-22 11:00:00Z],
                     authority: :unknown,
                     reason: "operator_requested_group_backfill",
                     actor_id: "operator-2",
                     actor_kind: "operator",
                     payload: %{
                       "request_source" => "dashboard",
                       "request_mode" => "bulk_points",
                       "request_group_id" => "backfill-run-group",
                       "request_item_index" => index,
                       "request_item_count" => 2,
                       "request_item_run_id" => run_id,
                       "dashboard_context" => %{
                         "dashboard_id" => "dashboard-group",
                         "dashboard_version" => "8",
                         "dashboard_time_mode" => "replay_run",
                         "dashboard_replay_run_id" => "replay-group-product",
                         "dashboard_data_view" => "all_revisions",
                         "dashboard_limit_mode" => "observed"
                       },
                       "comparison_review_origin" => %{
                         "request_event_id" => "review-request-group-transition",
                         "request_kind" => "comparison_open_findings_review",
                         "open_count" => "2",
                         "open_placement_ids" => "placement-counter,placement-voltage",
                         "workflow_kind" => "bulk_correction_authority_review",
                         "workflow_action" => "request_comparison_review",
                         "workflow_selection_kind" => "open_comparison_findings",
                         "workflow_selection_count" => "2",
                         "primary_data_view" => "all_revisions",
                         "compare_data_view" => "canonical"
                       }
                     }
                   },
                   dashboard_runtime_invalidation?: false
                 )

        event
      end

    assert {:ok, approved_events, job_results} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               "backfill-run-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert length(approved_events) == 2
    assert job_results == [{:ok, nil}, {:ok, nil}]

    assert Enum.map(approved_events, & &1.backfill_run_id) == [
             "backfill-run-group-1",
             "backfill-run-group-2"
           ]

    assert Enum.all?(approved_events, &(&1.reason == "operator_approved_group_backfill"))

    assert Enum.all?(
             approved_events,
             &(&1.payload["group_transition_source"] == "dashboard_group_action")
           )

    assert Enum.all?(
             approved_events,
             &(&1.payload["dashboard_context"] == %{
                 "dashboard_id" => "dashboard-group",
                 "dashboard_version" => "8",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-group-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               })
           )

    assert Enum.all?(
             approved_events,
             &(&1.payload["comparison_review_origin"] == %{
                 "request_event_id" => "review-request-group-transition",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => "2",
                 "open_placement_ids" => "placement-counter,placement-voltage",
                 "workflow_kind" => "bulk_correction_authority_review",
                 "workflow_action" => "request_comparison_review",
                 "workflow_selection_kind" => "open_comparison_findings",
                 "workflow_selection_count" => "2",
                 "primary_data_view" => "all_revisions",
                 "compare_data_view" => "canonical"
               })
           )

    assert Enum.map(approved_events, & &1.payload["requested_event_id"]) ==
             Enum.map(requested_events, & &1.backfill_lifecycle_event_id)

    assert {:error, {:no_eligible_items, "approved"}} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               "backfill-run-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_duplicate_group_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error, {:request_group_not_found, "missing-group"}} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               "missing-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_missing_group_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error, {:missing_field, :request_group_id}} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               nil,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_missing_group_backfill"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "records corrected group transitions through the correction transition API" do
    failed_job = failed_historical_workflow_job("backfill-run-correction-group-source")

    assert {:ok, source_event} =
             record_group_failed_event(
               "failed-event-correction-group-transition",
               "backfill-run-correction-group-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-correction-group",
               item_count: 1,
               job_id: failed_job.job_id,
               dashboard_context: %{
                 "dashboard_id" => "dashboard-correction-group",
                 "dashboard_version" => "9",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-correction-group-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-correction-group-fixed",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_group_backfill"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, [approved], [{:ok, nil}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               "backfill-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_corrected_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert approved.backfill_run_id == correction_request.backfill_run_id
    assert approved.payload["group_transition_source"] == "dashboard_group_action"
    assert approved.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert approved.payload["requested_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert approved.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id

    assert approved.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-correction-group",
             "dashboard_version" => "9",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-correction-group-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert {:ok, [started], [{:ok, started_job}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "started",
               "backfill-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_corrected_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert started.backfill_run_id == correction_request.backfill_run_id
    assert started.payload["group_transition_source"] == "dashboard_group_action"
    assert started.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert started.payload["correction_transition_source_event_id"] ==
             approved.backfill_lifecycle_event_id

    assert started.payload["corrects_run_id"] == source_event.backfill_run_id
    assert started.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert started_job.status == :queued
    assert started_job.run_id == correction_request.backfill_run_id

    assert {:ok, [completed], [{:ok, nil}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "completed",
               "backfill-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_completed_corrected_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert completed.backfill_run_id == correction_request.backfill_run_id
    assert completed.payload["group_transition_source"] == "dashboard_group_action"
    assert completed.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert completed.payload["correction_transition_source_event_id"] ==
             started.backfill_lifecycle_event_id

    assert completed.payload["requested_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert completed.payload["corrects_run_id"] == source_event.backfill_run_id
    assert completed.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
  end

  test "starts corrected import workflow group transition jobs through the product API" do
    failed_job =
      failed_historical_workflow_job("import-run-correction-group-source", workflow: :import)

    assert {:ok, source_event} =
             record_group_failed_event(
               "import-failed-event-correction-group-transition",
               "import-run-correction-group-source",
               1,
               workflow: :import,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "import-run-correction-group",
               item_count: 1,
               job_id: failed_job.job_id,
               dashboard_context: %{
                 "dashboard_id" => "dashboard-import-correction-group",
                 "dashboard_version" => "9",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-import-correction-group-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "import",
               %{
                 import_run_id: "import-run-correction-group-fixed",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_group_import"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert correction_request.event_type == :import_requested
    assert correction_request.backfill_run_id == "import-run-correction-group-fixed"
    assert correction_request.payload["workflow"] == "import"
    assert correction_request.payload["correction_source"] == "dashboard_correction_request"
    assert correction_request.payload["correction_source_event_type"] == "import_failed"

    assert correction_request.payload["corrects_event_id"] ==
             source_event.backfill_lifecycle_event_id

    assert correction_request.payload["corrects_job_id"] == failed_job.job_id

    assert correction_request.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-import-correction-group",
             "dashboard_version" => "9",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-import-correction-group-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert {:ok, [approved], [{:ok, nil}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "import",
               "approved",
               "import-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_corrected_group_import",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert approved.event_type == :import_approved
    assert approved.backfill_run_id == correction_request.backfill_run_id
    assert approved.payload["group_transition_source"] == "dashboard_group_action"
    assert approved.payload["correction_source"] == "dashboard_correction_request"
    assert approved.payload["correction_source_event_type"] == "import_failed"
    assert approved.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert approved.payload["requested_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert approved.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id

    assert {:ok, [started], [{:ok, started_job}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "import",
               "started",
               "import-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_corrected_group_import",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert started.event_type == :import_started
    assert started.backfill_run_id == correction_request.backfill_run_id
    assert started.payload["correction_source"] == "dashboard_correction_request"
    assert started.payload["correction_source_event_type"] == "import_failed"
    assert started.payload["correction_transition_source"] == "dashboard_correction_transition"
    assert started.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert started_job.status == :queued
    assert started_job.run_id == "import-run-correction-group-fixed"
    assert started_job.payload["workflow"] == "import"
    assert started_job.payload["attrs"]["import_run_id"] == "import-run-correction-group-fixed"

    assert started_job.payload["attrs"]["payload"]["correction_source"] ==
             "dashboard_correction_request"

    assert started_job.payload["attrs"]["payload"]["correction_source_event_type"] ==
             "import_failed"

    assert :ok =
             HistoryStore.persist_samples([
               sample(
                 "sample-import-corrected-source",
                 ~U[2026-06-22 10:20:00Z],
                 ~U[2026-06-22 10:20:03Z],
                 point_id: "HK.group_failed1",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 raw_value: 88
               )
             ])

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == started_job.job_id

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-import-corrected-source"
    assert envelope.raw_value == 88
    assert envelope.realm == :backfill
    assert envelope.data_source_id == "customer_archive_import"
    assert envelope.binding_id == "import_telemetry"

    events =
      Storage.list_backfill_lifecycle_events("mission-product",
        organization_id: "org-product",
        backfill_run_id: "import-run-correction-group-fixed"
      )

    assert Enum.map(events, & &1.event_type) == [
             :import_requested,
             :import_approved,
             :import_started,
             :import_completed
           ]

    completed = List.last(events)
    assert completed.reason == "historical_data_job_completed"
    assert completed.sample_count == 1
    assert completed.payload["workflow"] == "import"
    assert completed.payload["workflow_job_status"] == "completed"
    assert completed.payload["job_id"] == started_job.job_id
    assert completed.payload["request_group_id"] == "import-run-correction-group"
    assert completed.payload["request_item_index"] == 1
    assert completed.payload["request_item_count"] == 1
    assert completed.payload["correction_source"] == "dashboard_correction_request"
    assert completed.payload["correction_source_event_type"] == "import_failed"
    assert completed.payload["recovery_action"] == "correct_workflow_request"
    assert completed.payload["corrects_run_id"] == "import-run-correction-group-source"
    assert completed.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert completed.payload["corrects_job_id"] == failed_job.job_id

    assert completed.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-import-correction-group",
             "dashboard_version" => "9",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-import-correction-group-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }
  end

  test "retries failed corrected import replacement jobs through the product API" do
    failed_job =
      failed_historical_workflow_job("import-run-correction-retry-source", workflow: :import)

    assert {:ok, source_event} =
             record_group_failed_event(
               "import-failed-event-correction-retry-source",
               "import-run-correction-retry-source",
               1,
               workflow: :import,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "import-run-correction-retry-group",
               item_count: 1,
               job_id: failed_job.job_id,
               dashboard_context: %{
                 "dashboard_id" => "dashboard-import-correction-retry",
                 "dashboard_version" => "10",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-import-correction-retry-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "import",
               %{
                 import_run_id: "import-run-correction-retry-fixed",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_group_import"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, [_approved], [{:ok, nil}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "import",
               "approved",
               "import-run-correction-retry-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_corrected_group_import",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, [_started], [{:ok, started_job}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "import",
               "started",
               "import-run-correction-retry-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_corrected_group_import",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert started_job.status == :queued

    Application.put_env(:cadence, :telemetry_history_store,
      module: Cadence.TestSupport.FailingHistoryStore,
      failure_reason: :source_unavailable
    )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == started_job.job_id
    assert {:ok, failed_run_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert failed_run_job.status == :failed

    assert {:ok, failed_replacement_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "import-run-correction-retry-fixed"
             )

    assert failed_replacement_job.status == :failed

    events =
      Storage.list_backfill_lifecycle_events("mission-product",
        organization_id: "org-product",
        backfill_run_id: "import-run-correction-retry-fixed"
      )

    assert Enum.map(events, & &1.event_type) == [
             :import_requested,
             :import_approved,
             :import_started,
             :import_failed
           ]

    failed_replacement_event = List.last(events)
    assert failed_replacement_event.payload["workflow"] == "import"
    assert failed_replacement_event.payload["workflow_job_status"] == "failed"
    assert failed_replacement_event.payload["job_id"] == started_job.job_id

    assert failed_replacement_event.payload["request_group_id"] ==
             "import-run-correction-retry-group"

    assert failed_replacement_event.payload["request_item_index"] == 1
    assert failed_replacement_event.payload["request_item_count"] == 1
    assert failed_replacement_event.payload["correction_source"] == "dashboard_correction_request"
    assert failed_replacement_event.payload["correction_source_event_type"] == "import_failed"
    assert failed_replacement_event.payload["recovery_action"] == "correct_workflow_request"
    assert failed_replacement_event.payload["source"]["failure"]["retryable"] == true
    assert failed_replacement_event.payload["source"]["failure"]["recovery_action"] == "retry_job"

    assert failed_replacement_event.payload["corrects_event_id"] ==
             source_event.backfill_lifecycle_event_id

    assert failed_replacement_event.payload["corrects_job_id"] == failed_job.job_id

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "import-run-correction-retry-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-3",
                 actor_kind: "operator"
               },
               retry_run_ids: [correction_request.backfill_run_id],
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 1
    assert summary.nonretryable == 0
    assert summary.skipped == 0
    assert summary.failed == 0
    assert summary.retry_error_items == []
    assert [retry_event] = summary.events
    assert retry_event.event_type == :import_retried
    assert retry_event.backfill_run_id == correction_request.backfill_run_id

    assert retry_event.payload["retry_source_event_id"] ==
             failed_replacement_event.backfill_lifecycle_event_id

    assert retry_event.payload["retry_source_event_type"] == "import_failed"
    assert retry_event.payload["retry_job_id"] == started_job.job_id
    assert retry_event.payload["request_group_id"] == "import-run-correction-retry-group"
    assert retry_event.payload["correction_source"] == "dashboard_correction_request"
    assert retry_event.payload["correction_source_event_type"] == "import_failed"
    assert retry_event.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert retry_event.payload["corrects_job_id"] == failed_job.job_id

    assert {:ok, retried_replacement_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "import-run-correction-retry-fixed"
             )

    assert retried_replacement_job.status == :queued
  end

  test "starts historical data workflow group transition jobs through the product API" do
    requested_events =
      for index <- 1..2 do
        run_id = "backfill-run-group-start-#{index}"
        point_id = "HK.group_start#{index}"

        assert {:ok, event} =
                 Cadence.record_telemetry_historical_data_workflow_event(
                   "backfill",
                   "requested",
                   %{
                     backfill_run_id: run_id,
                     organization_id: "org-product",
                     mission_id: "mission-product",
                     realm: :backfill,
                     data_source_id: "managed_questdb_backfill",
                     binding_id: "backfill_telemetry",
                     observable_id: point_id,
                     point_id: point_id,
                     source_from: ~U[2026-06-22 10:00:00Z],
                     source_to: ~U[2026-06-22 11:00:00Z],
                     authority: :unknown,
                     reason: "operator_requested_group_start_backfill",
                     actor_id: "operator-2",
                     actor_kind: "operator",
                     payload: %{
                       "request_group_id" => "backfill-run-group-start",
                       "request_item_index" => index,
                       "request_item_count" => 2
                     }
                   },
                   dashboard_runtime_invalidation?: false
                 )

        event
      end

    assert {:error, {:no_eligible_items, "started"}} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "started",
               requested_events,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_group_backfill_too_early",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, approved_events, _approval_job_results} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               requested_events,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, started_events, job_results} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "started",
               requested_events ++ approved_events,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert length(started_events) == 2
    assert Enum.all?(started_events, &(&1.event_type == :backfill_started))

    assert Enum.all?(
             job_results,
             &match?({:ok, %{job_type: :telemetry_historical_data_workflow, status: :queued}}, &1)
           )

    assert Enum.map(job_results, fn {:ok, job} -> job.run_id end) ==
             ["backfill-run-group-start-1", "backfill-run-group-start-2"]
  end

  test "retries historical data workflow job through the product API" do
    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-single-retry",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_failed)
    assert failed_job.status == :failed

    assert {:ok, source_event} =
             record_group_failed_event(
               "failed-single-retry-event",
               "backfill-run-single-retry",
               1,
               retryable: true
             )

    assert {:ok, retried_job, retry_event} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               job.job_id,
               source_event.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert retried_job.status == :queued
    assert retry_event.event_type == :backfill_retried
    assert retry_event.actor_id == "operator-2"
    assert retry_event.payload["retry_action"] == "retry_job"

    assert retry_event.payload["retry_source_event_id"] ==
             source_event.backfill_lifecycle_event_id

    assert retry_event.payload["retry_job_id"] == job.job_id
    assert retry_event.payload["retry_job_status"] == "queued"
    assert [retried_claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert retried_claimed_job.job_id == job.job_id

    assert {:error, {:historical_workflow_event_not_found, "missing-event"}} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               job.job_id,
               "missing-event",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, mismatched_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-mismatched-retry",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert [claimed_mismatched_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_mismatched_job.job_id == mismatched_job.job_id

    assert {:ok, failed_mismatched_job} =
             Cadence.Jobs.fail_worker_start(mismatched_job.job_id, :source_failed)

    assert failed_mismatched_job.status == :failed

    assert {:error,
            {:historical_workflow_retry_blocked, "failed-single-retry-event", :job_run_mismatch}} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               mismatched_job.job_id,
               source_event.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-single-queued-retry",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert {:ok, queued_source_event} =
             record_group_failed_event(
               "failed-single-queued-retry-event",
               "backfill-run-single-queued-retry",
               1,
               retryable: true,
               request_group_id: "backfill-run-single-queued-retry-group"
             )

    assert {:error,
            {:historical_workflow_retry_blocked, "failed-single-queued-retry-event",
             "job_not_failed"}} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               queued_job.job_id,
               queued_source_event.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert [claimed_queued_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_queued_job.job_id == queued_job.job_id

    assert {:ok, correction_required_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-single-correction",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert [claimed_correction_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_correction_job.job_id == correction_required_job.job_id

    assert {:ok, failed_correction_job} =
             Cadence.Jobs.fail_worker_start(correction_required_job.job_id, :source_failed)

    assert failed_correction_job.status == :failed

    assert {:ok, correction_required_event} =
             record_group_failed_event(
               "failed-single-correction-event",
               "backfill-run-single-correction",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request"
             )

    assert {:error,
            {:historical_workflow_retry_blocked, "failed-single-correction-event",
             :correct_workflow_request}} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               correction_required_job.job_id,
               correction_required_event.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "retries historical data workflow group failed jobs through the product API" do
    retryable_job_1 = failed_historical_workflow_job("backfill-run-group-failed-1")
    retryable_job_2 = failed_historical_workflow_job("backfill-run-group-failed-2")

    assert {:ok, retryable_failed_event} =
             record_group_failed_event("failed-group-event-1", "backfill-run-group-failed-1", 1,
               retryable: true,
               item_count: 5
             )

    assert {:ok, second_retryable_failed_event} =
             record_group_failed_event("failed-group-event-2", "backfill-run-group-failed-2", 2,
               retryable: true,
               item_count: 5
             )

    assert {:ok, _nonretryable_failed_event} =
             record_group_failed_event("failed-group-event-3", "backfill-run-group-failed-3", 3,
               retryable: false,
               item_count: 5
             )

    assert {:ok, _missing_job_failed_event} =
             record_group_failed_event("failed-group-event-4", "backfill-run-group-failed-4", 4,
               retryable: true,
               item_count: 5
             )

    assert {:ok, _correction_required_failed_event} =
             record_group_failed_event("failed-group-event-5", "backfill-run-group-failed-5", 5,
               retryable: true,
               recovery_action: "correct_workflow_request",
               item_count: 5
             )

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-failed",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 2
    assert summary.nonretryable == 2
    assert summary.skipped == 1
    assert summary.failed == 0
    assert summary.retry_error_items == []

    nonretryable_items =
      summary.nonretryable_items
      |> Enum.sort_by(& &1.event_id)

    assert nonretryable_items == [
             %{
               event_id: "failed-group-event-3",
               reason: "nonretryable_failure",
               run_id: "backfill-run-group-failed-3"
             },
             %{
               event_id: "failed-group-event-5",
               reason: "correction_required",
               recovery_action: "correct_workflow_request",
               run_id: "backfill-run-group-failed-5"
             }
           ]

    assert summary.skipped_items == [
             %{
               event_id: "failed-group-event-4",
               reason: "job_status_missing",
               run_id: "backfill-run-group-failed-4"
             }
           ]

    retry_events =
      summary.events
      |> Enum.sort_by(& &1.payload["request_item_index"])

    assert Enum.map(retry_events, & &1.event_type) == [:backfill_retried, :backfill_retried]

    assert Enum.map(retry_events, & &1.reason) == [
             "dashboard_historical_workflow_retried",
             "dashboard_historical_workflow_retried"
           ]

    assert Enum.map(retry_events, & &1.actor_id) == ["operator-2", "operator-2"]

    assert Enum.map(retry_events, & &1.payload["retry_action"]) == ["retry_job", "retry_job"]

    assert Enum.map(retry_events, & &1.payload["retry_source_event_id"]) == [
             retryable_failed_event.backfill_lifecycle_event_id,
             second_retryable_failed_event.backfill_lifecycle_event_id
           ]

    assert Enum.map(retry_events, & &1.payload["request_group_id"]) == [
             "backfill-run-group-failed",
             "backfill-run-group-failed"
           ]

    assert Enum.map(retry_events, & &1.payload["request_item_index"]) == [1, 2]
    assert Enum.map(retry_events, & &1.payload["request_item_count"]) == [5, 5]

    assert Enum.map(retry_events, & &1.payload["retry_job_id"]) == [
             retryable_job_1.job_id,
             retryable_job_2.job_id
           ]

    assert Enum.map(retry_events, & &1.payload["retry_job_status"]) == ["queued", "queued"]

    assert {:ok, retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job("backfill-run-group-failed-1")

    assert retried_job.status == :queued

    assert {:ok, second_retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job("backfill-run-group-failed-2")

    assert second_retried_job.status == :queued

    assert {:error, {:missing_field, :request_group_id}} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _nonretryable_only_event} =
             record_group_failed_event(
               "failed-group-no-retry-event",
               "backfill-run-group-no-retry-1",
               1,
               retryable: false,
               request_group_id: "backfill-run-group-no-retry",
               item_count: 1
             )

    assert {:error,
            {:historical_workflow_group_retry_blocked, "backfill-run-group-no-retry",
             "no_retryable_group_failures"}} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-no-retry",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "retries only scoped replacement runs in a historical workflow group" do
    original_failed_job = failed_historical_workflow_job("backfill-run-group-scoped-original")

    replacement_failed_job =
      failed_historical_workflow_job("backfill-run-group-scoped-replacement")

    assert {:ok, _original_failed_event} =
             record_group_failed_event(
               "failed-group-scoped-original-event",
               "backfill-run-group-scoped-original",
               1,
               retryable: true,
               request_group_id: "backfill-run-group-scoped",
               item_count: 2
             )

    assert {:ok, replacement_failed_event} =
             record_group_failed_event(
               "failed-group-scoped-replacement-event",
               "backfill-run-group-scoped-replacement",
               2,
               retryable: true,
               request_group_id: "backfill-run-group-scoped",
               item_count: 2,
               recovery_action: "retry_job"
             )

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-scoped",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               retry_run_ids: ["backfill-run-group-scoped-replacement"],
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 1
    assert summary.nonretryable == 0
    assert summary.skipped == 0
    assert summary.failed == 0
    assert summary.retry_error_items == []
    assert [retry_event] = summary.events

    assert retry_event.payload["retry_source_event_id"] ==
             replacement_failed_event.backfill_lifecycle_event_id

    assert retry_event.payload["request_group_id"] == "backfill-run-group-scoped"
    assert retry_event.payload["request_item_index"] == 2
    assert retry_event.payload["retry_job_id"] == replacement_failed_job.job_id

    assert {:ok, still_failed_original} =
             Cadence.Jobs.fetch_job(original_failed_job.job_id)

    assert still_failed_original.status == :failed

    assert {:ok, retried_replacement} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "backfill-run-group-scoped-replacement"
             )

    assert retried_replacement.status == :queued
  end

  test "reports skipped items in degraded scoped replacement retry batches" do
    replacement_failed_job =
      failed_historical_workflow_job("backfill-run-group-degraded-replacement-failed")

    replacement_running_job =
      running_historical_workflow_job("backfill-run-group-degraded-replacement-running")

    assert {:ok, replacement_failed_event} =
             record_group_failed_event(
               "failed-group-degraded-replacement-event",
               "backfill-run-group-degraded-replacement-failed",
               1,
               retryable: true,
               request_group_id: "backfill-run-group-degraded-replacement",
               item_count: 2,
               recovery_action: "retry_job"
             )

    assert {:ok, replacement_running_event} =
             record_group_failed_event(
               "failed-group-degraded-running-event",
               "backfill-run-group-degraded-replacement-running",
               2,
               retryable: true,
               request_group_id: "backfill-run-group-degraded-replacement",
               item_count: 2,
               recovery_action: "retry_job"
             )

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-degraded-replacement",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               retry_run_ids: [
                 "backfill-run-group-degraded-replacement-failed",
                 "backfill-run-group-degraded-replacement-running"
               ],
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 1
    assert summary.nonretryable == 0
    assert summary.skipped == 1
    assert summary.failed == 0
    assert summary.retry_error_items == []
    assert [retry_event] = summary.events

    assert retry_event.backfill_run_id == "backfill-run-group-degraded-replacement-failed"

    assert retry_event.payload["retry_source_event_id"] ==
             replacement_failed_event.backfill_lifecycle_event_id

    assert retry_event.payload["request_group_id"] == "backfill-run-group-degraded-replacement"
    assert retry_event.payload["request_item_index"] == 1
    assert retry_event.payload["retry_job_id"] == replacement_failed_job.job_id

    assert [skipped_item] = summary.skipped_items
    assert skipped_item.run_id == "backfill-run-group-degraded-replacement-running"
    assert skipped_item.event_id == replacement_running_event.backfill_lifecycle_event_id
    assert skipped_item.job_id == replacement_running_job.job_id
    assert skipped_item.job_status == "running"
    assert skipped_item.reason == "job_not_failed"

    assert {:ok, retried_replacement} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "backfill-run-group-degraded-replacement-failed"
             )

    assert retried_replacement.status == :queued

    assert {:ok, still_running_replacement} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "backfill-run-group-degraded-replacement-running"
             )

    assert still_running_replacement.status == :running
  end

  test "retries import workflow group failed jobs through the product API" do
    retryable_job_1 =
      failed_historical_workflow_job("import-run-group-failed-1", workflow: :import)

    retryable_job_2 =
      failed_historical_workflow_job("import-run-group-failed-2", workflow: :import)

    assert {:ok, retryable_failed_event} =
             record_group_failed_event(
               "import-failed-group-event-1",
               "import-run-group-failed-1",
               1,
               workflow: :import,
               retryable: true,
               request_group_id: "import-run-group-failed",
               item_count: 2
             )

    assert {:ok, second_retryable_failed_event} =
             record_group_failed_event(
               "import-failed-group-event-2",
               "import-run-group-failed-2",
               2,
               workflow: :import,
               retryable: true,
               request_group_id: "import-run-group-failed",
               item_count: 2
             )

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "import-run-group-failed",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 2
    assert summary.nonretryable == 0
    assert summary.skipped == 0
    assert summary.failed == 0
    assert summary.retry_error_items == []

    retry_events =
      summary.events
      |> Enum.sort_by(& &1.payload["request_item_index"])

    assert Enum.map(retry_events, & &1.event_type) == [:import_retried, :import_retried]

    assert Enum.map(retry_events, & &1.backfill_run_id) == [
             "import-run-group-failed-1",
             "import-run-group-failed-2"
           ]

    assert Enum.map(retry_events, & &1.payload["workflow"]) == ["import", "import"]

    assert Enum.map(retry_events, & &1.payload["retry_source_event_type"]) == [
             "import_failed",
             "import_failed"
           ]

    assert Enum.map(retry_events, & &1.payload["retry_source_event_id"]) == [
             retryable_failed_event.backfill_lifecycle_event_id,
             second_retryable_failed_event.backfill_lifecycle_event_id
           ]

    assert Enum.map(retry_events, & &1.payload["request_group_id"]) == [
             "import-run-group-failed",
             "import-run-group-failed"
           ]

    assert Enum.map(retry_events, & &1.payload["request_item_index"]) == [1, 2]
    assert Enum.map(retry_events, & &1.payload["request_item_count"]) == [2, 2]

    assert Enum.map(retry_events, & &1.payload["retry_job_id"]) == [
             retryable_job_1.job_id,
             retryable_job_2.job_id
           ]

    assert Enum.map(retry_events, & &1.payload["retry_job_status"]) == ["queued", "queued"]

    assert {:ok, retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job("import-run-group-failed-1")

    assert retried_job.status == :queued
    assert retried_job.payload["workflow"] == "import"

    assert {:ok, second_retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job("import-run-group-failed-2")

    assert second_retried_job.status == :queued
    assert second_retried_job.payload["workflow"] == "import"
  end

  test "records stale replacement job inspection without advancing replacement stage" do
    failed_job = failed_historical_workflow_job("backfill-run-stale-inspection-source")

    assert {:ok, failed_event} =
             record_group_failed_event(
               "failed-event-stale-inspection-source",
               "backfill-run-stale-inspection-source",
               1,
               retryable: false,
               request_group_id: "backfill-run-stale-inspection-group",
               item_count: 1,
               recovery_action: "correct_workflow_request",
               job_id: failed_job.job_id
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-stale-inspection-replacement",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-1",
                 actor_kind: "operator"
               },
               %{
                 original_event_id: failed_event.backfill_lifecycle_event_id,
                 original_run_id: failed_event.backfill_run_id,
                 original_job_id: failed_job.job_id,
                 request_group_id: "backfill-run-stale-inspection-group",
                 request_item_index: 1,
                 request_item_count: 1,
                 request_item_run_id: "backfill-run-stale-inspection-replacement"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, replacement_job} =
             stale_running_historical_workflow_job(correction_request.backfill_run_id)

    assert {:ok, inspection_event} =
             Cadence.record_telemetry_historical_data_workflow_stale_replacement_inspection(
               replacement_job.job_id,
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert inspection_event.event_type == :backfill_stale_replacement_inspected
    assert inspection_event.reason == "dashboard_historical_workflow_stale_replacement_inspected"
    assert inspection_event.authority == :advisory
    assert inspection_event.backfill_run_id == correction_request.backfill_run_id
    assert inspection_event.payload["stale_replacement_action"] == "inspect_stale_replacement_job"

    assert inspection_event.payload["stale_replacement_source_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert inspection_event.payload["stale_replacement_run_id"] ==
             correction_request.backfill_run_id

    assert inspection_event.payload["stale_replacement_job_id"] == replacement_job.job_id
    assert inspection_event.payload["stale_replacement_job_status"] == "running"
    assert inspection_event.payload["stale_replacement_stale_after_seconds"] == 900
    refute Map.has_key?(inspection_event.payload, "stage")

    correction_request_id = correction_request.backfill_lifecycle_event_id

    assert {:error,
            {:historical_workflow_stale_replacement_inspection_blocked, ^correction_request_id,
             :job_run_mismatch}} =
             Cadence.record_telemetry_historical_data_workflow_stale_replacement_inspection(
               failed_job.job_id,
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "records missing replacement job inspection without creating replacement job" do
    failed_job = failed_historical_workflow_job("backfill-run-missing-inspection-source")

    assert {:ok, failed_event} =
             record_group_failed_event(
               "failed-event-missing-inspection-source",
               "backfill-run-missing-inspection-source",
               1,
               retryable: false,
               request_group_id: "backfill-run-missing-inspection-group",
               item_count: 1,
               recovery_action: "correct_workflow_request",
               job_id: failed_job.job_id
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-missing-inspection-replacement",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-1",
                 actor_kind: "operator"
               },
               %{
                 original_event_id: failed_event.backfill_lifecycle_event_id,
                 original_run_id: failed_event.backfill_run_id,
                 original_job_id: failed_job.job_id,
                 request_group_id: "backfill-run-missing-inspection-group",
                 request_item_index: 1,
                 request_item_count: 1,
                 request_item_run_id: "backfill-run-missing-inspection-replacement"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, inspection_event} =
             Cadence.record_telemetry_historical_data_workflow_missing_replacement_inspection(
               "backfill-run-missing-inspection-group",
               correction_request.backfill_run_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert inspection_event.event_type == :backfill_missing_replacement_inspected

    assert inspection_event.reason ==
             "dashboard_historical_workflow_missing_replacement_inspected"

    assert inspection_event.authority == :advisory
    assert inspection_event.backfill_run_id == correction_request.backfill_run_id

    assert inspection_event.payload["missing_replacement_action"] ==
             "inspect_missing_replacement_job"

    assert inspection_event.payload["missing_replacement_source_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert inspection_event.payload["missing_replacement_run_id"] ==
             correction_request.backfill_run_id

    assert inspection_event.payload["missing_replacement_expected_job_type"] ==
             "telemetry_historical_data_workflow"

    refute Map.has_key?(inspection_event.payload, "stage")

    assert {:error,
            {:historical_workflow_missing_replacement_inspection_blocked,
             "backfill-run-missing-inspection-unknown", :replacement_event_not_found}} =
             Cadence.record_telemetry_historical_data_workflow_missing_replacement_inspection(
               "backfill-run-missing-inspection-group",
               "backfill-run-missing-inspection-unknown",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _replacement_job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               %{
                 backfill_run_id: correction_request.backfill_run_id,
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: correction_request.realm,
                 data_source_id: correction_request.data_source_id,
                 binding_id: correction_request.binding_id,
                 observable_id: correction_request.observable_id,
                 source_from: correction_request.source_from,
                 source_to: correction_request.source_to
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error,
            {:historical_workflow_missing_replacement_inspection_blocked,
             "backfill-run-missing-inspection-replacement", {:job_exists, :queued}}} =
             Cadence.record_telemetry_historical_data_workflow_missing_replacement_inspection(
               "backfill-run-missing-inspection-group",
               correction_request.backfill_run_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "requeues stale replacement job and records authoritative lifecycle event" do
    failed_job = failed_historical_workflow_job("backfill-run-stale-requeue-source")

    assert {:ok, failed_event} =
             record_group_failed_event(
               "failed-event-stale-requeue-source",
               "backfill-run-stale-requeue-source",
               1,
               retryable: false,
               request_group_id: "backfill-run-stale-requeue-group",
               item_count: 1,
               recovery_action: "correct_workflow_request",
               job_id: failed_job.job_id
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-stale-requeue-replacement",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-1",
                 actor_kind: "operator"
               },
               %{
                 original_event_id: failed_event.backfill_lifecycle_event_id,
                 original_run_id: failed_event.backfill_run_id,
                 original_job_id: failed_job.job_id,
                 request_group_id: "backfill-run-stale-requeue-group",
                 request_item_index: 1,
                 request_item_count: 1,
                 request_item_run_id: "backfill-run-stale-requeue-replacement"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, replacement_job} =
             stale_running_historical_workflow_job(correction_request.backfill_run_id)

    assert {:ok, requeued_job, requeue_event} =
             Cadence.requeue_telemetry_historical_data_workflow_stale_replacement_job(
               replacement_job.job_id,
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert requeued_job.status == :queued
    assert requeued_job.started_at == nil
    assert requeued_job.completed_at == nil
    assert requeued_job.failure_reason == %{"reason" => "dashboard_stale_replacement_requeued"}

    assert requeue_event.event_type == :backfill_stale_replacement_requeued
    assert requeue_event.reason == "dashboard_historical_workflow_stale_replacement_requeued"
    assert requeue_event.authority == :authoritative
    assert requeue_event.backfill_run_id == correction_request.backfill_run_id
    assert requeue_event.payload["stale_replacement_action"] == "requeue_stale_replacement_job"

    assert requeue_event.payload["stale_replacement_source_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert requeue_event.payload["stale_replacement_run_id"] ==
             correction_request.backfill_run_id

    assert requeue_event.payload["stale_replacement_job_id"] == replacement_job.job_id
    assert requeue_event.payload["stale_replacement_job_status"] == "running"
    assert requeue_event.payload["stale_replacement_stale_after_seconds"] == 900
    assert requeue_event.payload["stale_replacement_requeued_job_id"] == requeued_job.job_id
    assert requeue_event.payload["stale_replacement_requeued_job_status"] == "queued"
    assert requeue_event.payload["stale_replacement_requeued_job_attempt_count"] == 1

    assert requeue_event.payload["stale_replacement_requeued_failure_reason"] ==
             "dashboard_stale_replacement_requeued"

    refute Map.has_key?(requeue_event.payload, "stage")

    assert {:ok, fetched_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               correction_request.backfill_run_id
             )

    assert fetched_job.status == :queued
  end

  test "dispatches historical data workflow jobs through the background job runner" do
    assert :ok =
             HistoryStore.persist_samples([
               sample("sample-source-before", ~U[2026-06-22 09:59:00Z], ~U[2026-06-22 10:59:03Z],
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 raw_value: 41
               ),
               sample("sample-source-copied", ~U[2026-06-22 10:20:00Z], ~U[2026-06-22 10:20:03Z],
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 raw_value: 43
               ),
               sample(
                 "sample-source-other-binding",
                 ~U[2026-06-22 10:30:00Z],
                 ~U[2026-06-22 10:30:03Z],
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "other_backfill_binding",
                 raw_value: 99
               )
             ])

    attrs = %{
      backfill_run_id: "backfill-run-dispatched",
      organization_id: "org-product",
      mission_id: "mission-product",
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      observable_id: "HK.counter",
      point_id: "HK.counter",
      source_from: ~U[2026-06-22 10:00:00Z],
      source_to: ~U[2026-06-22 11:00:00Z],
      authority: :authoritative,
      reason: "operator_started_backfill",
      actor_id: "operator-2",
      actor_kind: "operator",
      payload: %{
        "request_source" => "dashboard_direct_request",
        "request_mode" => "bulk_points",
        "request_group_id" => "backfill-run-dispatched-group",
        "request_item_index" => 1,
        "request_item_count" => 2,
        "request_item_run_id" => "backfill-run-dispatched",
        "dashboard_context" => %{
          "dashboard_id" => "dashboard-job-context",
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-job-context",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed"
        },
        "comparison_review_origin" => %{
          "review_request_event_id" => "review-job-context",
          "source" => "dashboard_comparison_review"
        }
      }
    }

    assert {:ok, started} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "started",
               attrs,
               dashboard_runtime_invalidation?: false
             )

    assert started.event_type == :backfill_started

    assert {:ok, job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               attrs,
               dashboard_runtime_invalidation?: false
             )

    assert job.job_type == :telemetry_historical_data_workflow
    assert job.run_id == "backfill-run-dispatched"
    assert job.status == :queued
    assert job.payload["workflow"] == "backfill"
    assert job.payload["attrs"]["backfill_run_id"] == "backfill-run-dispatched"

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert claimed_job.status == :running

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-source-copied"
    assert envelope.raw_value == 43
    assert envelope.realm == :backfill
    assert envelope.data_source_id == "managed_questdb_backfill"
    assert envelope.binding_id == "backfill_telemetry"

    events =
      Storage.list_backfill_lifecycle_events("mission-product",
        organization_id: "org-product",
        backfill_run_id: "backfill-run-dispatched"
      )

    assert Enum.map(events, & &1.event_type) == [:backfill_started, :backfill_completed]
    completed = List.last(events)
    assert completed.reason == "historical_data_job_completed"
    assert completed.sample_count == 1
    assert completed.payload["job_id"] == job.job_id
    assert completed.payload["workflow_job_status"] == "completed"
    assert completed.payload["request_source"] == "dashboard_direct_request"
    assert completed.payload["request_mode"] == "bulk_points"
    assert completed.payload["request_group_id"] == "backfill-run-dispatched-group"
    assert completed.payload["request_item_index"] == 1
    assert completed.payload["request_item_count"] == 2
    assert completed.payload["request_item_run_id"] == "backfill-run-dispatched"

    assert completed.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-job-context",
             "dashboard_version" => "1",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-job-context",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert completed.payload["comparison_review_origin"] == %{
             "review_request_event_id" => "review-job-context",
             "source" => "dashboard_comparison_review"
           }

    assert completed.payload["source"]["point_id"] == "HK.counter"

    assert completed.payload["source"]["source_identity"]["source_binding_id"] ==
             "backfill_telemetry"
  end

  test "records structured failure diagnostics for historical data workflow jobs" do
    attrs = %{
      backfill_run_id: "backfill-run-dispatch-failed",
      organization_id: "org-product",
      mission_id: "mission-product",
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      source_from: ~U[2026-06-22 10:00:00Z],
      source_to: ~U[2026-06-22 11:00:00Z],
      authority: :authoritative,
      reason: "operator_started_backfill",
      actor_id: "operator-2",
      actor_kind: "operator",
      payload: %{
        "request_source" => "dashboard_direct_request",
        "request_mode" => "bulk_points",
        "request_group_id" => "backfill-run-dispatch-failed-group",
        "request_item_index" => 2,
        "request_item_count" => 2,
        "request_item_run_id" => "backfill-run-dispatch-failed",
        "dashboard_context" => %{
          "dashboard_id" => "dashboard-job-failure-context",
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-job-failure-context",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed"
        }
      }
    }

    assert {:ok, job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               attrs,
               dashboard_runtime_invalidation?: false
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    assert {:ok, failed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert failed_job.status == :failed
    assert failed_job.failure_reason == %{"tuple" => ["missing_field", "point_id"]}

    assert [failed] =
             Storage.list_backfill_lifecycle_events("mission-product",
               organization_id: "org-product",
               backfill_run_id: "backfill-run-dispatch-failed"
             )

    assert failed.event_type == :backfill_failed
    assert failed.reason == :historical_data_job_failed
    assert failed.payload["job_id"] == job.job_id
    assert failed.payload["workflow_job_status"] == "failed"
    assert failed.payload["request_source"] == "dashboard_direct_request"
    assert failed.payload["request_mode"] == "bulk_points"
    assert failed.payload["request_group_id"] == "backfill-run-dispatch-failed-group"
    assert failed.payload["request_item_index"] == 2
    assert failed.payload["request_item_count"] == 2
    assert failed.payload["request_item_run_id"] == "backfill-run-dispatch-failed"

    assert failed.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-job-failure-context",
             "dashboard_version" => "1",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-job-failure-context",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert failed.payload["source"]["failure"]["code"] == "missing_field:point_id"
    assert failed.payload["source"]["failure"]["retryable"] == false
    assert failed.payload["source"]["failure"]["retry_blockers"] == ["missing point_id"]
    assert failed.payload["source"]["failure"]["recovery_action"] == "correct_workflow_request"
    assert failed.payload["source"]["source_window"]["from_observed_at"] == "2026-06-22T10:00:00Z"

    assert failed.payload["source"]["source_identity"]["source_binding_id"] ==
             "backfill_telemetry"
  end

  test "applies correction-authority decisions with dashboard-readable evidence" do
    initial =
      sample("sample-correction-initial", ~U[2026-06-22 11:10:00Z], ~U[2026-06-22 12:10:03Z])

    correction = %{initial | sample_id: "sample-correction-candidate", raw_value: 43}

    assert :ok =
             Storage.persist_samples([initial],
               organization_id: "org-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry",
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, [initial_envelope]}

    assert :ok =
             Storage.persist_samples([correction],
               organization_id: "org-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, [correction_envelope]}
    assert correction_envelope.observation_identity_id == initial_envelope.observation_identity_id
    assert correction_envelope.observation_id != initial_envelope.observation_id

    assert {:ok, state} =
             Cadence.apply_telemetry_observation_identity_decision(
               initial_envelope.observation_identity_id,
               "mark-canonical",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry",
                 canonical_observation_id: correction_envelope.observation_id,
                 canonical_sample_id: correction_envelope.sample_id,
                 canonical_revision: correction_envelope.revision,
                 correction_workflow_id: "correction-workflow-1",
                 authority: "operator",
                 requested_by: "console",
                 operator_id: "operator-7",
                 decision_reason: "operator_selected_corrected_candidate",
                 evidence_ref: %{"kind" => "dashboard_revision_marker", "id" => "marker-1"}
               },
               dashboard_runtime_invalidation?: false
             )

    assert state.validity_state == :canonical
    assert state.canonical_observation_id == correction_envelope.observation_id
    assert state.canonical_sample_id == correction_envelope.sample_id
    assert state.canonical_revision == 2
    assert state.decision_reason == "operator_selected_corrected_candidate"

    assert [event] =
             Storage.list_observation_identity_decision_events(
               initial_envelope.observation_identity_id,
               organization_id: "org-product",
               mission_id: "mission-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry"
             )

    assert event.decision == :mark_canonical
    assert event.decision_reason == "operator_selected_corrected_candidate"
    assert event.actor_id == "operator-7"
    assert event.actor_kind == "operator"
    assert event.previous_state["validity_state"] == "conflict"
    assert event.new_state["validity_state"] == "canonical"
    assert event.new_state["canonical_sample_id"] == correction_envelope.sample_id
    assert event.evidence_ref["kind"] == "dashboard_revision_marker"
    assert event.evidence_ref["id"] == "marker-1"

    assert event.evidence_ref["correction_workflow"] == %{
             "authority" => "operator",
             "id" => "correction-workflow-1",
             "kind" => "telemetry_correction_authority_workflow",
             "operator_id" => "operator-7",
             "reason" => "operator_selected_corrected_candidate",
             "requested_by" => "console"
           }
  end

  test "applies bulk correction-authority decisions with shared workflow evidence" do
    initial_counter =
      sample(
        "sample-bulk-correction-counter-initial",
        ~U[2026-06-22 11:10:00Z],
        ~U[2026-06-22 12:10:03Z],
        point_id: "HK.counter"
      )

    initial_voltage =
      sample(
        "sample-bulk-correction-voltage-initial",
        ~U[2026-06-22 11:11:00Z],
        ~U[2026-06-22 12:11:03Z],
        point_id: "HK.voltage",
        raw_value: 28
      )

    correction_counter = %{
      initial_counter
      | sample_id: "sample-bulk-correction-counter-candidate",
        raw_value: 44
    }

    correction_voltage = %{
      initial_voltage
      | sample_id: "sample-bulk-correction-voltage-candidate",
        raw_value: 29
    }

    assert :ok =
             Storage.persist_samples([initial_counter, initial_voltage],
               organization_id: "org-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry",
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, initial_envelopes}

    assert :ok =
             Storage.persist_samples([correction_counter, correction_voltage],
               organization_id: "org-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, correction_envelopes}

    initial_counter_envelope = envelope_by_sample_id(initial_envelopes, initial_counter.sample_id)
    initial_voltage_envelope = envelope_by_sample_id(initial_envelopes, initial_voltage.sample_id)

    correction_counter_envelope =
      envelope_by_sample_id(correction_envelopes, correction_counter.sample_id)

    correction_voltage_envelope =
      envelope_by_sample_id(correction_envelopes, correction_voltage.sample_id)

    assert {:ok, summary} =
             Cadence.apply_telemetry_observation_identity_decisions(
               [
                 %{
                   observation_identity_id: initial_counter_envelope.observation_identity_id,
                   canonical_observation_id: correction_counter_envelope.observation_id,
                   canonical_sample_id: correction_counter_envelope.sample_id,
                   canonical_revision: correction_counter_envelope.revision,
                   evidence_ref: %{"placement_id" => "placement-counter"}
                 },
                 %{
                   observation_identity_id: initial_voltage_envelope.observation_identity_id,
                   canonical_observation_id: correction_voltage_envelope.observation_id,
                   canonical_sample_id: correction_voltage_envelope.sample_id,
                   canonical_revision: correction_voltage_envelope.revision,
                   evidence_ref: %{"placement_id" => "placement-voltage"}
                 },
                 %{canonical_sample_id: "missing-identity"}
               ],
               "mark-canonical",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry",
                 correction_workflow_id: "bulk-correction-workflow-1",
                 authority: "operator",
                 requested_by: "dashboard_comparison_review",
                 operator_id: "operator-7",
                 decision_reason: "operator_accepted_bulk_correction_authority_review",
                 selection_kind: "open_comparison_findings",
                 evidence_ref: %{
                   "kind" => "dashboard_comparison_review",
                   "id" => "review-request-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert summary.workflow_id == "bulk-correction-workflow-1"
    assert summary.decision == :mark_canonical
    assert summary.requested == 3
    assert summary.applied == 2
    assert summary.failed == 1

    assert Enum.map(summary.results, & &1.observation_identity_id) == [
             initial_counter_envelope.observation_identity_id,
             initial_voltage_envelope.observation_identity_id
           ]

    assert [%{index: 3, reason: {:missing_field, :observation_identity_id}}] = summary.errors

    assert_bulk_decision_event!(
      initial_counter_envelope.observation_identity_id,
      correction_counter_envelope,
      1,
      "placement-counter"
    )

    assert_bulk_decision_event!(
      initial_voltage_envelope.observation_identity_id,
      correction_voltage_envelope,
      2,
      "placement-voltage"
    )
  end

  test "applies bulk comparison-review conflict decisions with workflow evidence" do
    counter =
      sample(
        "sample-bulk-conflict-counter",
        ~U[2026-06-22 11:10:00Z],
        ~U[2026-06-22 12:10:03Z],
        point_id: "HK.counter"
      )

    voltage =
      sample(
        "sample-bulk-conflict-voltage",
        ~U[2026-06-22 11:11:00Z],
        ~U[2026-06-22 12:11:03Z],
        point_id: "HK.voltage",
        raw_value: 28
      )

    assert :ok =
             Storage.persist_samples([counter, voltage],
               organization_id: "org-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry",
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, envelopes}

    counter_envelope = envelope_by_sample_id(envelopes, counter.sample_id)
    voltage_envelope = envelope_by_sample_id(envelopes, voltage.sample_id)

    assert {:ok, summary} =
             Cadence.apply_telemetry_observation_identity_decisions(
               [
                 %{
                   observation_identity_id: counter_envelope.observation_identity_id,
                   evidence_ref: %{
                     "placement_id" => "placement-counter",
                     "comparison_finding" => %{"placement_id" => "placement-counter"}
                   }
                 },
                 %{
                   observation_identity_id: voltage_envelope.observation_identity_id,
                   evidence_ref: %{
                     "placement_id" => "placement-voltage",
                     "comparison_finding" => %{"placement_id" => "placement-voltage"}
                   }
                 }
               ],
               "mark_conflict",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry",
                 correction_workflow_id: "review-request-1",
                 authority: "operator",
                 requested_by: "dashboard_comparison_review",
                 operator_id: "operator-7",
                 decision_reason: "dashboard_comparison_review_mark_conflict",
                 selection_kind: "open_comparison_findings",
                 evidence_ref: %{"kind" => "dashboard_comparison_review_finding"}
               },
               dashboard_runtime_invalidation?: false
             )

    assert summary.workflow_id == "review-request-1"
    assert summary.decision == :mark_conflict
    assert summary.requested == 2
    assert summary.applied == 2
    assert summary.failed == 0

    assert_bulk_conflict_decision_event!(
      counter_envelope.observation_identity_id,
      1,
      "placement-counter"
    )

    assert_bulk_conflict_decision_event!(
      voltage_envelope.observation_identity_id,
      2,
      "placement-voltage"
    )
  end

  test "rejects mixed-mission backfill samples before writing" do
    first = sample("sample-backfill-1", ~U[2026-06-22 11:00:00Z], ~U[2026-06-22 12:00:03Z])
    second = %{first | sample_id: "sample-backfill-2", mission_id: "mission-other"}

    assert {:error, {:mixed_mission_samples, ["mission-product", "mission-other"]}} =
             Cadence.backfill_telemetry_samples([first, second], %{
               backfill_run_id: "backfill-run-product",
               organization_id: "org-product",
               realm: :backfill,
               data_source_id: "managed_questdb_backfill",
               binding_id: "backfill_telemetry"
             })
  end

  defp sample(sample_id, generation_time, receipt_time, opts \\ []) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-product",
      spacecraft_id: "sc-1",
      point_id: Keyword.get(opts, :point_id, "HK.counter"),
      point_name: Keyword.get(opts, :point_id, "HK.counter"),
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      raw_value: Keyword.get(opts, :raw_value, 42),
      engineering_value: Keyword.get(opts, :engineering_value, Keyword.get(opts, :raw_value, 42)),
      quality_state: :good,
      generation_time: generation_time,
      receipt_time: receipt_time,
      provenance: provenance(opts)
    }
  end

  defp envelope_by_sample_id(envelopes, sample_id) do
    Enum.find(envelopes, &(&1.sample_id == sample_id))
  end

  defp assert_bulk_decision_event!(
         observation_identity_id,
         correction_envelope,
         item_index,
         placement_id
       ) do
    assert [event] =
             Storage.list_observation_identity_decision_events(
               observation_identity_id,
               organization_id: "org-product",
               mission_id: "mission-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry"
             )

    assert event.decision == :mark_canonical
    assert event.new_state["validity_state"] == "canonical"
    assert event.new_state["canonical_sample_id"] == correction_envelope.sample_id
    assert event.evidence_ref["kind"] == "dashboard_comparison_review"
    assert event.evidence_ref["id"] == "review-request-1"
    assert event.evidence_ref["placement_id"] == placement_id

    assert event.evidence_ref["bulk_workflow_item"] == %{
             "kind" => "telemetry_correction_authority_workflow_item",
             "workflow_id" => "bulk-correction-workflow-1",
             "item_index" => item_index,
             "item_count" => 3,
             "observation_identity_id" => observation_identity_id,
             "selection_kind" => "open_comparison_findings"
           }

    assert event.evidence_ref["correction_workflow"] == %{
             "authority" => "operator",
             "id" => "bulk-correction-workflow-1",
             "item_count" => 3,
             "item_index" => item_index,
             "item_observation_identity_id" => observation_identity_id,
             "kind" => "telemetry_correction_authority_workflow",
             "operator_id" => "operator-7",
             "reason" => "operator_accepted_bulk_correction_authority_review",
             "requested_by" => "dashboard_comparison_review",
             "selection_kind" => "open_comparison_findings"
           }
  end

  defp assert_bulk_conflict_decision_event!(
         observation_identity_id,
         item_index,
         placement_id
       ) do
    assert [event] =
             Storage.list_observation_identity_decision_events(
               observation_identity_id,
               organization_id: "org-product",
               mission_id: "mission-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry"
             )

    assert event.decision == :mark_conflict
    assert event.decision_reason == "dashboard_comparison_review_mark_conflict"
    assert event.actor_id == "operator-7"
    assert event.actor_kind == "operator"
    assert event.new_state["validity_state"] == "conflict"
    assert event.evidence_ref["kind"] == "dashboard_comparison_review_finding"
    assert event.evidence_ref["placement_id"] == placement_id
    assert event.evidence_ref["comparison_finding"]["placement_id"] == placement_id

    assert event.evidence_ref["bulk_workflow_item"] == %{
             "kind" => "telemetry_correction_authority_workflow_item",
             "workflow_id" => "review-request-1",
             "item_index" => item_index,
             "item_count" => 2,
             "observation_identity_id" => observation_identity_id,
             "selection_kind" => "open_comparison_findings"
           }

    assert event.evidence_ref["correction_workflow"] == %{
             "authority" => "operator",
             "id" => "review-request-1",
             "item_count" => 2,
             "item_index" => item_index,
             "item_observation_identity_id" => observation_identity_id,
             "kind" => "telemetry_correction_authority_workflow",
             "operator_id" => "operator-7",
             "reason" => "dashboard_comparison_review_mark_conflict",
             "requested_by" => "dashboard_comparison_review",
             "selection_kind" => "open_comparison_findings"
           }
  end

  defp provenance(opts) do
    storage =
      %{}
      |> maybe_put("realm", atom_text(Keyword.get(opts, :realm)))
      |> maybe_put("data_source_id", Keyword.get(opts, :data_source_id))
      |> maybe_put("binding_id", Keyword.get(opts, :binding_id))

    if map_size(storage) == 0 do
      %{}
    else
      %{"storage" => storage}
    end
  end

  defp atom_text(nil), do: nil
  defp atom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_text(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp failed_historical_workflow_job(run_id, opts \\ []) do
    workflow =
      opts
      |> Keyword.get(:workflow, :backfill)
      |> atom_text()

    payload_attrs =
      case workflow do
        "import" -> %{"import_run_id" => run_id}
        _workflow -> %{"backfill_run_id" => run_id}
      end

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               run_id,
               %{"workflow" => workflow, "attrs" => payload_attrs}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_failed)
    assert failed_job.status == :failed

    failed_job
  end

  defp running_historical_workflow_job(run_id, opts \\ []) do
    workflow =
      opts
      |> Keyword.get(:workflow, :backfill)
      |> atom_text()

    payload_attrs =
      case workflow do
        "import" -> %{"import_run_id" => run_id}
        _workflow -> %{"backfill_run_id" => run_id}
      end

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               run_id,
               %{"workflow" => workflow, "attrs" => payload_attrs}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    claimed_job
  end

  defp stale_running_historical_workflow_job(run_id) do
    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               run_id,
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    stale_job = %{
      claimed_job
      | started_at: DateTime.add(DateTime.utc_now(), -1_200, :second)
    }

    assert %BackgroundJobRow{} =
             stale_job.job_id
             |> then(&Repo.get!(BackgroundJobRow, &1))
             |> BackgroundJobRow.changeset(stale_job)
             |> Repo.update!()

    Cadence.Jobs.fetch_job(stale_job.job_id)
  end

  defp record_group_failed_event(event_id, run_id, item_index, opts) do
    workflow =
      opts
      |> Keyword.get(:workflow, :backfill)
      |> atom_text()

    failure =
      %{"retryable" => Keyword.fetch!(opts, :retryable)}
      |> maybe_put("recovery_action", Keyword.get(opts, :recovery_action))

    payload =
      %{
        "request_group_id" => Keyword.get(opts, :request_group_id, "backfill-run-group-failed"),
        "request_item_index" => item_index,
        "request_item_count" => Keyword.get(opts, :item_count, 4),
        "source" => %{"failure" => failure}
      }
      |> maybe_put("job_id", Keyword.get(opts, :job_id))
      |> maybe_put("dashboard_context", Keyword.get(opts, :dashboard_context))

    workflow_attrs =
      %{
        backfill_lifecycle_event_id: event_id,
        organization_id: "org-product",
        mission_id: "mission-product",
        realm: :backfill,
        data_source_id:
          Keyword.get(
            opts,
            :data_source_id,
            if(workflow == "import",
              do: "customer_archive_import",
              else: "managed_questdb_backfill"
            )
          ),
        binding_id:
          Keyword.get(
            opts,
            :binding_id,
            if(workflow == "import", do: "import_telemetry", else: "backfill_telemetry")
          ),
        observable_id: Keyword.get(opts, :observable_id, "HK.group_failed#{item_index}"),
        point_id: Keyword.get(opts, :point_id, "HK.group_failed#{item_index}"),
        source_from: ~U[2026-06-22 10:00:00Z],
        source_to: ~U[2026-06-22 11:00:00Z],
        authority: :advisory,
        reason: "historical_data_job_failed",
        payload: payload
      }
      |> Map.put(if(workflow == "import", do: :import_run_id, else: :backfill_run_id), run_id)

    Cadence.record_telemetry_historical_data_workflow_event(
      workflow,
      "failed",
      workflow_attrs,
      dashboard_runtime_invalidation?: false
    )
  end

  defp event_stage_order(%{event_type: :backfill_requested}), do: 1
  defp event_stage_order(%{event_type: :backfill_approved}), do: 2
  defp event_stage_order(%{event_type: :backfill_started}), do: 3
  defp event_stage_order(%{event_type: :backfill_completed}), do: 4
  defp event_stage_order(%{event_type: :backfill_failed}), do: 5
  defp event_stage_order(%{event_type: :backfill_retried}), do: 6
  defp event_stage_order(%{event_type: :import_requested}), do: 1
  defp event_stage_order(%{event_type: :import_approved}), do: 2
  defp event_stage_order(%{event_type: :import_started}), do: 3
  defp event_stage_order(%{event_type: :import_completed}), do: 4
  defp event_stage_order(%{event_type: :import_failed}), do: 5
  defp event_stage_order(%{event_type: :import_retried}), do: 6
  defp event_stage_order(_event), do: 99
end
