defmodule Cadence.Dashboards.DataLinkResolverRecoveryTest do
  use Cadence.RuntimeCase, async: false

  import Cadence.Dashboards.DataLinkResolverFixtures

  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Dashboards.{DataLink, DataLinkInspector, DataLinkResolver}
  alias Cadence.Telemetry.Storage

  test "resolves late-data policy lifecycle source relationships" do
    organization_id = "org-resolver-late-data-policy"
    mission_id = "mission-resolver-late-data-policy"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, _source_event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-late-source-event-1",
                 backfill_run_id: "resolver-late-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :flight,
                 data_source_id: "flight-questdb",
                 binding_id: "flight-telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 event_type: :backfill_completed,
                 source_from: ~U[2026-06-22 11:00:00Z],
                 source_to: ~U[2026-06-22 12:00:00Z],
                 authority: :authoritative,
                 reason: :operator_backfill,
                 payload: %{"workflow" => "backfill", "stage" => "completed"}
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, policy_event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-late-policy-event-1",
                 backfill_run_id: "resolver-late-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :flight,
                 data_source_id: "flight-questdb",
                 binding_id: "flight-telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 event_type: :late_data_accepted,
                 source_from: ~U[2026-06-22 11:00:00Z],
                 source_to: ~U[2026-06-22 12:00:00Z],
                 authority: :authoritative,
                 reason: :dashboard_late_data_policy,
                 payload: %{
                   "kind" => "late_data_policy_decision",
                   "policy_decision" => "accept",
                   "execution_mode" => "sample_execution",
                   "source_event_id" => "resolver-late-source-event-1",
                   "source_event_type" => "backfill_completed",
                   "selected_sample_count" => 2,
                   "write_validity_state" => "canonical",
                   "record_current_values" => true,
                   "refresh_latest_value" => true,
                   "projection_effect" => "canonical_history_and_current_projection",
                   "dashboard_context" => %{"dashboard_limit_mode" => "compare"}
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: policy_event.backfill_lifecycle_event_id,
      context: %{logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert row_value(inspector.rows, "Late data policy decision") == "accept"
    assert row_value(inspector.rows, "Late data execution mode") == "sample_execution"
    assert row_value(inspector.rows, "Late data source event") == "resolver-late-source-event-1"
    assert row_value(inspector.rows, "Late data source event type") == "backfill_completed"
    assert row_value(inspector.rows, "Late data selected samples") == "2"
    assert row_value(inspector.rows, "Late data write validity") == "canonical"
    assert row_value(inspector.rows, "Late data current projection") == "true"
    assert row_value(inspector.rows, "Late data latest refresh") == "true"
    assert row_value(inspector.rows, "Dashboard context limit mode") == "compare"

    assert row_value(inspector.rows, "Late data projection effect") ==
             "canonical_history_and_current_projection"

    assert related_link(
             inspector.related_links,
             :telemetry_backfill_lifecycle_event,
             "resolver-late-source-event-1"
           )
  end

  test "resolves telemetry backfill lifecycle recovery relationships" do
    organization_id = "org-resolver-backfill-recovery-links"
    mission_id = "mission-resolver-backfill-recovery-links"
    persist_mission_scope(organization_id, mission_id)

    base_event = %{
      organization_id: organization_id,
      mission_id: mission_id,
      realm: :flight,
      data_source_id: "flight-questdb",
      binding_id: "flight-telemetry",
      observable_id: "HK.counter",
      point_id: "HK.counter",
      spacecraft_id: "sc-resolver-backfill",
      source_from: ~U[2026-06-22 11:00:00Z],
      source_to: ~U[2026-06-22 12:00:00Z],
      authority: :authoritative,
      actor_id: "ops-1",
      actor_kind: "operator"
    }

    assert {:ok, source_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-source-event-1",
                 backfill_run_id: "resolver-recovery-run-1",
                 event_type: :backfill_failed,
                 reason: :historical_data_job_failed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "failed",
                   "run_id" => "resolver-recovery-run-1"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, retry_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-retry-event-1",
                 backfill_run_id: "resolver-recovery-run-1",
                 event_type: :backfill_retried,
                 reason: "dashboard_historical_workflow_retried",
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "retried",
                   "run_id" => "resolver-recovery-run-1",
                   "retry_source_event_id" => source_event.backfill_lifecycle_event_id,
                   "retry_source_event_type" => "backfill_failed"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, correction_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-correction-event-1",
                 backfill_run_id: "resolver-recovery-correction-run-1",
                 event_type: :backfill_requested,
                 reason: :dashboard_historical_workflow_correction_requested,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "requested",
                   "run_id" => "resolver-recovery-correction-run-1",
                   "corrects_event_id" => source_event.backfill_lifecycle_event_id,
                   "corrects_run_id" => source_event.backfill_run_id,
                   "correction_source" => "dashboard_data_link_inspector"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, correction_transition_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-correction-transition-1",
                 backfill_run_id: "resolver-recovery-correction-run-1",
                 event_type: :backfill_completed,
                 reason: :dashboard_historical_workflow_correction_completed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "completed",
                   "run_id" => "resolver-recovery-correction-run-1",
                   "corrects_event_id" => source_event.backfill_lifecycle_event_id,
                   "correction_transition_source_event_id" =>
                     correction_event.backfill_lifecycle_event_id
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, policy_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-recovery-policy-event-1",
                 backfill_run_id: "resolver-recovery-run-1",
                 event_type: :late_data_accepted,
                 reason: :dashboard_late_data_policy,
                 payload: %{
                   "kind" => "late_data_policy_decision",
                   "policy_decision" => "accept",
                   "source_event_id" => source_event.backfill_lifecycle_event_id
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    source_link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: source_event.backfill_lifecycle_event_id,
      context: %{logical_source: :events},
      source: :frame
    }

    assert {:ok, source_inspector} =
             DataLinkResolver.resolve(source_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert %DataLink{relationship_kind: :retry_event} =
             related_link(
               source_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               retry_event.backfill_lifecycle_event_id
             )

    assert %DataLink{relationship_kind: :correction_request} =
             related_link(
               source_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               correction_event.backfill_lifecycle_event_id
             )

    assert %DataLink{relationship_kind: :correction_transition} =
             related_link(
               source_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               correction_transition_event.backfill_lifecycle_event_id
             )

    assert %DataLink{relationship_kind: :late_data_policy_event} =
             related_link(
               source_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               policy_event.backfill_lifecycle_event_id
             )

    retry_link = %{source_link | target_id: retry_event.backfill_lifecycle_event_id}

    assert {:ok, retry_inspector} =
             DataLinkResolver.resolve(
               %{
                 retry_link
                 | context:
                     Map.put(retry_link.context, :navigation, %{
                       from: %{
                         link_id: source_link.link_id,
                         target: "telemetry_backfill_lifecycle_event",
                         target_id: source_event.backfill_lifecycle_event_id,
                         label: "Source event",
                         relationship_kind: "retry_event",
                         relationship_label: "Retry event HK.counter"
                       }
                     })
               },
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert retry_inspector.navigation == %{
             from: %{
               target: "telemetry_backfill_lifecycle_event",
               target_id: source_event.backfill_lifecycle_event_id,
               label: "Source event",
               relationship_kind: "retry_event",
               relationship_label: "Retry event HK.counter"
             }
           }

    assert %DataLink{relationship_kind: :source_event} =
             related_link(
               retry_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               source_event.backfill_lifecycle_event_id
             )

    correction_link = %{source_link | target_id: correction_event.backfill_lifecycle_event_id}

    assert {:ok, correction_inspector} =
             DataLinkResolver.resolve(correction_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert %DataLink{relationship_kind: :source_event} =
             related_link(
               correction_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               source_event.backfill_lifecycle_event_id
             )

    assert %DataLink{relationship_kind: :correction_transition} =
             related_link(
               correction_inspector.related_links,
               :telemetry_backfill_lifecycle_event,
               correction_transition_event.backfill_lifecycle_event_id
             )
  end

  test "resolves telemetry backfill lifecycle failure diagnostics" do
    organization_id = "org-resolver-backfill-failure"
    mission_id = "mission-resolver-backfill-failure"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-backfill-failed-event-1",
                 backfill_run_id: "resolver-backfill-failed-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :backfill,
                 replay_run_id: "replay-run-backfill-failure",
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 event_type: :backfill_failed,
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :advisory,
                 reason: :historical_data_job_failed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "failed",
                   "run_id" => "resolver-backfill-failed-run-1",
                   "source" => %{
                     "point_id" => nil,
                     "source_window" => %{
                       "from_observed_at" => "2026-06-22T10:00:00Z",
                       "to_observed_at" => "2026-06-22T11:00:00Z"
                     },
                     "source_identity" => %{
                       "realm" => "backfill",
                       "replay_run_id" => "replay-run-backfill-failure",
                       "data_source_id" => "managed_questdb_backfill",
                       "source_binding_id" => "backfill_telemetry"
                     },
                     "source_limit" => 10_000,
                     "failure" => %{
                       "code" => "missing_field:point_id",
                       "detail" => "{:missing_field, :point_id}",
                       "retryable" => false,
                       "retry_blockers" => ["missing point_id"],
                       "recovery_action" => "correct_workflow_request"
                     }
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission_id,
               "resolver-backfill-failed-run-1",
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => "resolver-backfill-failed-run-1"}
               }
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_window_failed)
    assert failed_job.status == :failed

    link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: event.backfill_lifecycle_event_id,
      context: %{logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert row_value(inspector.rows, "Workflow failure code") == "missing_field:point_id"
    assert row_value(inspector.rows, "Workflow failure detail") == "{:missing_field, :point_id}"
    assert row_value(inspector.rows, "Workflow retryable") == "false"
    assert row_value(inspector.rows, "Workflow retry blockers") == "missing point_id"
    assert row_value(inspector.rows, "Workflow recovery action") == "correct_workflow_request"
    assert row_value(inspector.rows, "Replay run") == "replay-run-backfill-failure"

    assert row_value(inspector.rows, "Workflow source replay run") ==
             "replay-run-backfill-failure"

    assert row_value(inspector.rows, "Workflow source data source") == "managed_questdb_backfill"
    assert row_value(inspector.rows, "Workflow source binding") == "backfill_telemetry"
    assert row_value(inspector.rows, "Workflow source from") == "2026-06-22T10:00:00Z"
    assert row_value(inspector.rows, "Workflow source to") == "2026-06-22T11:00:00Z"
    assert row_value(inspector.rows, "Workflow source limit") == "10000"
    assert row_value(inspector.rows, "Workflow job") == job.job_id
    assert row_value(inspector.rows, "Workflow job status") == "failed"
  end

  test "does not resolve mission events or contacts outside the requested organization and mission" do
    organization_id = "org-resolver-events-scope-a"
    mission_id = "mission-resolver-events-scope-a"
    persist_mission_scope(organization_id, mission_id)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "resolver-scope-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths("source-endpoint-alpha"),
        starts_at: ~U[2026-06-20 12:00:00Z],
        ends_at: ~U[2026-06-20 12:10:00Z]
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_contact} =
             Cadence.Contacts.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "weather"
             )

    [mission_event] = Cadence.list_mission_events(organization_id, mission_id, order: :asc)
    persist_mission_scope("org-resolver-events-scope-b", "mission-resolver-events-scope-b")

    assert {:error, event_inspector} =
             DataLinkResolver.resolve(
               %DataLink{
                 label: "Mission event",
                 target: :mission_event,
                 target_id: mission_event.mission_event_id
               },
               organization_id: "org-resolver-events-scope-b",
               mission_id: "mission-resolver-events-scope-b"
             )

    assert event_inspector.status == :missing

    assert {:error, contact_inspector} =
             DataLinkResolver.resolve(
               %DataLink{
                 label: "Contact",
                 target: :contact,
                 target_id: scheduled_contact.scheduled_contact_id
               },
               organization_id: "org-resolver-events-scope-b",
               mission_id: "mission-resolver-events-scope-b"
             )

    assert contact_inspector.status == :missing
  end

  test "returns a missing inspector for stale dashboard link ids" do
    inspector = DataLinkResolver.missing("stale-link-1")

    assert %DataLinkInspector{} = inspector
    assert inspector.status == :missing
    assert inspector.title == "Data link"
    assert inspector.target == :data_link
    assert inspector.target_id == "stale-link-1"
    assert row_value(inspector.rows, "Link") == "stale-link-1"
    assert inspector.related_links == []
  end

  test "returns an unsupported inspector for invalid data-link targets" do
    link = %DataLink{label: "Command", target: :command, target_id: "cmd-1"}

    assert {:error, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: "org-resolver-unsupported",
               mission_id: "mission-resolver-unsupported"
             )

    assert inspector.status == :unsupported
    assert inspector.target == :command
    assert inspector.target_id == "cmd-1"
  end
end
