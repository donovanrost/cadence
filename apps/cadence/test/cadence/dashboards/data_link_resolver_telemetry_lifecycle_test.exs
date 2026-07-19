defmodule Cadence.Dashboards.DataLinkResolverTelemetryLifecycleTest do
  use Cadence.RuntimeCase, async: false

  import Cadence.Dashboards.DataLinkResolverFixtures

  alias Cadence.Dashboards.{
    DataBinding,
    DataLink,
    DataLinkResolver,
    DataSource,
    DataSources,
    LifecycleEvent,
    SourceWatermarks
  }

  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow

  alias Cadence.Dashboards.DocumentStore.LifecycleEventRow,
    as: DashboardLifecycleEventRow

  alias Cadence.Repo
  alias Cadence.Telemetry.Storage
  alias Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent

  alias Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionEventRow,
    as: TelemetryObservationIdentityDecisionEventRow

  test "resolves source binding event links from persisted data bindings" do
    organization_id = "org-resolver-source-binding-event"
    mission_id = "mission-resolver-source-binding-event"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, _data_source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "mission-questdb-lifecycle",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: organization_id,
               mission_id: mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true},
               metadata: %{storage: :questdb}
             })

    binding = %DataBinding{
      binding_id: "flight-telemetry-lifecycle",
      organization_id: organization_id,
      mission_id: mission_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-lifecycle",
      dataset: "flight",
      priority: 0,
      metadata: %{reason: :primary}
    }

    assert {:ok, _persisted_binding} =
             DataSources.persist_data_binding(binding,
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-21 20:00:00Z],
               payload: %{change_request_id: "CR-99"}
             )

    [event] = DataSources.list_data_binding_events("flight-telemetry-lifecycle")

    link = %DataLink{
      label: "Source binding event",
      target: :source_binding_event,
      target_id: event.data_binding_event_id,
      context: %{source_request_id: "telemetry-request-1", logical_source: :telemetry},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :source_binding_event
    assert row_value(inspector.rows, "Source binding event") == event.data_binding_event_id
    assert row_value(inspector.rows, "Binding") == "flight-telemetry-lifecycle"
    assert row_value(inspector.rows, "Event type") == "registered"
    assert row_value(inspector.rows, "Current logical source") == "telemetry"
    assert row_value(inspector.rows, "Current realm") == "flight"
    assert row_value(inspector.rows, "Current data source") == "mission-questdb-lifecycle"
    assert row_value(inspector.rows, "Current dataset") == "flight"
    assert row_value(inspector.rows, "Actor") == "operator-1"
    assert row_value(inspector.context_rows, "Logical source") == "telemetry"

    assert related_link(
             inspector.related_links,
             :operational_event,
             "operational_event:dashboard_data_binding_event:#{event.data_binding_event_id}"
           )

    interval_link = %DataLink{
      label: "Source binding interval",
      target: :source_binding_interval,
      target_id: "effective_interval:source_binding:#{event.data_binding_event_id}",
      context: %{source_request_id: "telemetry-request-1", logical_source: :telemetry},
      source: :frame
    }

    assert {:ok, interval_inspector} =
             DataLinkResolver.resolve(interval_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert interval_inspector.status == :resolved
    assert interval_inspector.target == :source_binding_interval

    assert row_value(interval_inspector.rows, "Source binding interval") ==
             interval_link.target_id

    assert row_value(interval_inspector.rows, "Binding") == "flight-telemetry-lifecycle"
    assert row_value(interval_inspector.rows, "Data binding event") == event.data_binding_event_id
    assert row_value(interval_inspector.rows, "Data source") == "mission-questdb-lifecycle"

    assert related_link(
             interval_inspector.related_links,
             :source_binding_event,
             event.data_binding_event_id
           )
  end

  test "resolves source watermark event links from persisted transition events" do
    organization_id = "org-resolver-source-watermark"
    mission_id = "mission-resolver-source-watermark"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, event, _status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: organization_id,
                 mission_id: mission_id,
                 logical_source: :telemetry,
                 data_source_id: "flight-questdb",
                 source_binding_id: "flight-telemetry",
                 realm: :flight,
                 dataset: "flight",
                 replay_run_id: "replay-run-watermark",
                 complete_through: ~U[2026-06-21 12:05:00Z],
                 previous_complete_through: ~U[2026-06-21 12:00:00Z],
                 latest_receipt_time: ~U[2026-06-21 12:05:30Z],
                 previous_latest_receipt_time: ~U[2026-06-21 12:00:30Z],
                 retention_starts_at: ~U[2026-06-21 11:00:00Z],
                 sample_count: 42,
                 confidence: :authoritative,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-21 12:06:00Z],
                 payload: %{write_id: "write-1"}
               },
               invalidate_runtime_cache?: false
             )

    link = %DataLink{
      label: "Source watermark event",
      target: :source_watermark_event,
      target_id: event.source_watermark_event_id,
      context: %{source_request_id: "events-request-1", logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :source_watermark_event
    assert row_value(inspector.rows, "Source watermark event") == event.source_watermark_event_id
    assert row_value(inspector.rows, "Source watermark key") == event.source_watermark_key
    assert row_value(inspector.rows, "Logical source") == "telemetry"
    assert row_value(inspector.rows, "Data source") == "flight-questdb"
    assert row_value(inspector.rows, "Source binding") == "flight-telemetry"
    assert row_value(inspector.rows, "Replay run") == "replay-run-watermark"
    assert row_value(inspector.rows, "Event type") == "observed"
    assert row_value(inspector.rows, "Complete through") == "2026-06-21T12:05:00.000000Z"
    assert row_value(inspector.rows, "Latest receipt time") == "2026-06-21T12:05:30.000000Z"
    assert row_value(inspector.rows, "Retention starts at") == "2026-06-21T11:00:00.000000Z"
    assert row_value(inspector.rows, "Sample count") == "42"
    assert row_value(inspector.rows, "Confidence") == "authoritative"
    assert row_value(inspector.rows, "Reason") == "telemetry_storage_write"
    assert row_value(inspector.context_rows, "Logical source") == "events"
  end

  test "resolves telemetry revision decision event links" do
    organization_id = "org-resolver-revision-decision"
    mission_id = "mission-resolver-revision-decision"
    persist_mission_scope(organization_id, mission_id)

    Repo.insert!(%OpsDashboardRow{
      dashboard_id: "dashboard-resolver-revision",
      organization_id: organization_id,
      mission_id: mission_id,
      name: "Revision decision dashboard",
      document: %{
        "dashboard_id" => "dashboard-resolver-revision",
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "name" => "Revision decision dashboard",
        "metadata" => %{"version" => 4}
      },
      latest_version: 4,
      draft_version: 4,
      lifecycle_state: "active"
    })

    comparison_review_request =
      LifecycleEvent.new(%{
        dashboard_lifecycle_event_id: "correction-workflow-1",
        organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: "dashboard-resolver-revision",
        event_type: :comparison_review_requested,
        dashboard_version: 4,
        actor_id: "ops-1",
        occurred_at: ~U[2026-06-22 12:09:00Z],
        payload: %{
          "schema" => "dashboard_comparison_review_request.v1",
          "request_kind" => "comparison_open_findings_review",
          "open_count" => 4,
          "open_placement_ids" => ["placement-1", "placement-2", "placement-3", "placement-4"]
        }
      })

    assert {:ok, _row} =
             comparison_review_request
             |> DashboardLifecycleEventRow.changeset()
             |> Repo.insert()

    decision_event =
      ObservationIdentityDecisionEvent.new(%{
        decision_event_id: "resolver-decision-event-1",
        observation_identity_id: "resolver-identity-1",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :flight,
        data_source_id: "flight-questdb",
        binding_id: "flight-telemetry",
        observable_id: "HK.counter",
        point_id: "HK.counter",
        spacecraft_id: "sc-resolver-revision",
        decision: :mark_canonical,
        decision_reason: "operator_selected_corrected_value",
        actor_id: "ops-1",
        actor_kind: "operator",
        evidence_ref: %{
          "kind" => "ticket",
          "id" => "OPS-123",
          "source_panel" => "data_link_inspector",
          "source_target" => "comparison_finding",
          "source_target_id" => "placement-1",
          "source_link_label" => "Comparison finding",
          "comparison_finding" => %{
            "placement_id" => "placement-1",
            "state" => "increased",
            "delta" => "+2",
            "primary_sample_id" => "sample-primary-1",
            "compare_sample_id" => "sample-compare-1",
            "primary_data_view" => "all_revisions",
            "compare_data_view" => "canonical",
            "primary_data_management" => "recomputed_analysis",
            "compare_data_management" => "degraded",
            "widget_id" => "widget-1",
            "widget_title" => "Counter"
          },
          "correction_workflow" => %{
            "kind" => "telemetry_correction_authority_workflow",
            "id" => "correction-workflow-1",
            "authority" => "operator",
            "requested_by" => "dashboard_comparison_review"
          },
          "bulk_workflow_item" => %{
            "kind" => "telemetry_correction_authority_workflow_item",
            "workflow_id" => "correction-workflow-1",
            "item_index" => 2,
            "item_count" => 4,
            "observation_identity_id" => "resolver-identity-1",
            "selection_kind" => "open_comparison_findings"
          }
        },
        previous_state: %{
          "validity_state" => "conflict",
          "canonical_sample_id" => "sample-before",
          "canonical_revision" => 1
        },
        new_state: %{
          "validity_state" => "canonical",
          "canonical_sample_id" => "sample-after",
          "canonical_revision" => 2
        },
        occurred_at: ~U[2026-06-22 12:10:00Z]
      })

    assert {:ok, _row} =
             decision_event
             |> TelemetryObservationIdentityDecisionEventRow.changeset()
             |> Repo.insert()

    link = %DataLink{
      label: "Telemetry revision decision event",
      target: :telemetry_revision_decision_event,
      target_id: decision_event.decision_event_id,
      context: %{
        source_request_id: "events-request-1",
        logical_source: :events,
        observable_id: "HK.counter",
        data: %{
          realm: :flight,
          data_source_id: "flight-questdb",
          source_binding_id: "flight-telemetry"
        }
      },
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :telemetry_revision_decision_event
    assert row_value(inspector.rows, "Revision decision event") == "resolver-decision-event-1"
    assert row_value(inspector.rows, "Observation identity") == "resolver-identity-1"
    assert row_value(inspector.rows, "Decision") == "mark_canonical"
    assert row_value(inspector.rows, "Decision reason") == "operator_selected_corrected_value"
    assert row_value(inspector.rows, "Data source") == "flight-questdb"
    assert row_value(inspector.rows, "Source binding") == "flight-telemetry"
    assert row_value(inspector.rows, "Observable") == "HK.counter"
    assert row_value(inspector.rows, "Point") == "HK.counter"
    assert row_value(inspector.rows, "Source panel") == "data_link_inspector"
    assert row_value(inspector.rows, "Source target") == "comparison_finding"
    assert row_value(inspector.rows, "Source target id") == "placement-1"
    assert row_value(inspector.rows, "Source link label") == "Comparison finding"
    assert row_value(inspector.rows, "Correction workflow") == "correction-workflow-1"
    assert row_value(inspector.rows, "Correction authority") == "operator"
    assert row_value(inspector.rows, "Correction requested by") == "dashboard_comparison_review"
    assert row_value(inspector.rows, "Bulk workflow") == "correction-workflow-1"
    assert row_value(inspector.rows, "Bulk workflow item") == "2"
    assert row_value(inspector.rows, "Bulk workflow item count") == "4"

    assert row_value(inspector.rows, "Bulk workflow observation identity") ==
             "resolver-identity-1"

    assert row_value(inspector.rows, "Bulk workflow selection") == "open_comparison_findings"
    assert row_value(inspector.rows, "Comparison finding") == "placement-1"
    assert row_value(inspector.rows, "Comparison state") == "increased"
    assert row_value(inspector.rows, "Comparison delta") == "+2"
    assert row_value(inspector.rows, "Comparison primary sample") == "sample-primary-1"
    assert row_value(inspector.rows, "Comparison compare sample") == "sample-compare-1"
    assert row_value(inspector.rows, "Comparison primary data view") == "all_revisions"
    assert row_value(inspector.rows, "Comparison compare data view") == "canonical"

    assert row_value(inspector.rows, "Comparison primary data management") ==
             "recomputed_analysis"

    assert row_value(inspector.rows, "Comparison compare data management") == "degraded"
    assert row_value(inspector.rows, "Comparison widget") == "widget-1"
    assert row_value(inspector.rows, "Comparison widget title") == "Counter"
    assert row_value(inspector.rows, "Previous validity state") == "conflict"
    assert row_value(inspector.rows, "New validity state") == "canonical"
    assert row_value(inspector.rows, "Previous canonical sample") == "sample-before"
    assert row_value(inspector.rows, "New canonical sample") == "sample-after"
    assert row_value(inspector.context_rows, "Source request") == "events-request-1"
    assert row_value(inspector.context_rows, "Logical source") == "events"
    assert related_link(inspector.related_links, :telemetry_point, "HK.counter")
    assert related_link(inspector.related_links, :telemetry_sample, "sample-before")
    assert related_link(inspector.related_links, :telemetry_sample, "sample-after")

    workflow_link =
      related_link(inspector.related_links, :dashboard_lifecycle_event, "correction-workflow-1")

    assert workflow_link
    assert workflow_link.relationship_kind == :comparison_review_origin

    assert {:ok, workflow_inspector} =
             DataLinkResolver.resolve(workflow_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert workflow_inspector.status == :resolved
    assert workflow_inspector.target == :dashboard_lifecycle_event

    assert row_value(workflow_inspector.rows, "Dashboard lifecycle event") ==
             "correction-workflow-1"

    assert row_value(workflow_inspector.rows, "Event type") == "comparison_review_requested"
    assert row_value(workflow_inspector.rows, "Dashboard") == "dashboard-resolver-revision"
    assert row_value(workflow_inspector.rows, "Dashboard version") == "4"

    assert {:error, missing_inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: "mission-other"
             )

    assert missing_inspector.status == :missing
  end

  test "resolves telemetry backfill lifecycle event links" do
    organization_id = "org-resolver-backfill-lifecycle"
    mission_id = "mission-resolver-backfill-lifecycle"
    persist_mission_scope(organization_id, mission_id)

    Repo.insert!(%OpsDashboardRow{
      dashboard_id: "dashboard-resolver-1",
      organization_id: organization_id,
      mission_id: mission_id,
      name: "Resolver dashboard",
      document: %{
        "dashboard_id" => "dashboard-resolver-1",
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "name" => "Resolver dashboard",
        "metadata" => %{"version" => 7}
      },
      latest_version: 7,
      draft_version: 7,
      lifecycle_state: "active"
    })

    comparison_review_request =
      LifecycleEvent.new(%{
        dashboard_lifecycle_event_id: "review-request-resolver",
        organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: "dashboard-resolver-1",
        event_type: :comparison_review_requested,
        dashboard_version: 7,
        actor_id: "ops-1",
        occurred_at: ~U[2026-06-22 12:19:00Z],
        payload: %{
          "schema" => "dashboard_comparison_review_request.v1",
          "request_kind" => "comparison_open_findings_review",
          "open_count" => 2,
          "open_placement_ids" => ["placement-1", "placement-2"]
        }
      })

    assert {:ok, _row} =
             comparison_review_request
             |> DashboardLifecycleEventRow.changeset()
             |> Repo.insert()

    assert {:ok, event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-backfill-event-1",
                 backfill_run_id: "resolver-backfill-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :flight,
                 replay_run_id: "replay-run-backfill",
                 data_source_id: "flight-questdb",
                 binding_id: "flight-telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 spacecraft_id: "sc-resolver-backfill",
                 event_type: :backfill_completed,
                 source_from: ~U[2026-06-22 11:00:00Z],
                 source_to: ~U[2026-06-22 12:00:00Z],
                 receipt_from: ~U[2026-06-22 12:10:00Z],
                 receipt_to: ~U[2026-06-22 12:20:00Z],
                 sample_count: 42,
                 authority: :authoritative,
                 reason: :operator_backfill,
                 actor_id: "ops-1",
                 actor_kind: "operator",
                 occurred_at: ~U[2026-06-22 12:21:00Z],
                 payload: %{
                   "ticket" => "OPS-123",
                   "workflow" => "backfill",
                   "stage" => "completed",
                   "run_id" => "resolver-backfill-run-1",
                   "dashboard_context" => %{
                     "dashboard_id" => "dashboard-resolver-1",
                     "dashboard_version" => "7",
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-run-backfill",
                     "dashboard_data_view" => "all_revisions",
                     "dashboard_limit_mode" => "observed"
                   },
                   "comparison_review_origin" => %{
                     "request_event_id" => comparison_review_request.dashboard_lifecycle_event_id,
                     "request_kind" => "comparison_open_findings_review",
                     "open_count" => "2",
                     "open_placement_ids" => "placement-1,placement-2",
                     "scope_kind" => "transport",
                     "scope_ids" => "transport-alpha,transport-beta",
                     "contact_ids" => "contact-alpha,contact-beta",
                     "resource_ids" => "transport-alpha",
                     "transport_ids" => "transport-alpha",
                     "source_endpoint_ids" => "endpoint-alpha",
                     "ground_station_ids" => "dss-14",
                     "scope_link_ids" => "link-alpha"
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission_id,
               "resolver-backfill-run-1",
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => "resolver-backfill-run-1"}
               }
             )

    link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: event.backfill_lifecycle_event_id,
      context: %{
        source_request_id: "events-request-1",
        logical_source: :events,
        observable_id: "HK.counter",
        data: %{
          realm: :flight,
          data_source_id: "flight-questdb",
          source_binding_id: "flight-telemetry"
        }
      },
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert inspector.status == :resolved
    assert inspector.target == :telemetry_backfill_lifecycle_event
    assert row_value(inspector.rows, "Backfill lifecycle event") == "resolver-backfill-event-1"
    assert row_value(inspector.rows, "Backfill run") == "resolver-backfill-run-1"
    assert row_value(inspector.rows, "Event type") == "backfill_completed"
    assert row_value(inspector.rows, "Workflow") == "backfill"
    assert row_value(inspector.rows, "Workflow stage") == "completed"
    assert row_value(inspector.rows, "Workflow run") == "resolver-backfill-run-1"
    assert row_value(inspector.rows, "Dashboard context") == "dashboard-resolver-1"
    assert row_value(inspector.rows, "Dashboard context version") == "7"
    assert row_value(inspector.rows, "Dashboard context time mode") == "replay_run"
    assert row_value(inspector.rows, "Dashboard context replay run") == "replay-run-backfill"
    assert row_value(inspector.rows, "Dashboard context data view") == "all_revisions"
    assert row_value(inspector.rows, "Dashboard context limit mode") == "observed"
    assert row_value(inspector.rows, "Comparison review request") == "review-request-resolver"

    assert row_value(inspector.rows, "Comparison review kind") ==
             "comparison_open_findings_review"

    assert row_value(inspector.rows, "Comparison review open count") == "2"
    assert row_value(inspector.rows, "Comparison review placements") == "placement-1,placement-2"
    assert row_value(inspector.rows, "Comparison review scope kind") == "transport"

    assert row_value(inspector.rows, "Comparison review scope ids") ==
             "transport-alpha,transport-beta"

    assert row_value(inspector.rows, "Comparison review contact ids") ==
             "contact-alpha,contact-beta"

    assert row_value(inspector.rows, "Comparison review resource ids") == "transport-alpha"
    assert row_value(inspector.rows, "Comparison review transport ids") == "transport-alpha"
    assert row_value(inspector.rows, "Comparison review source endpoint ids") == "endpoint-alpha"
    assert row_value(inspector.rows, "Comparison review ground station ids") == "dss-14"
    assert row_value(inspector.rows, "Comparison review scope link ids") == "link-alpha"
    assert row_value(inspector.rows, "Replay run") == "replay-run-backfill"
    assert row_value(inspector.rows, "Data source") == "flight-questdb"
    assert row_value(inspector.rows, "Source binding") == "flight-telemetry"
    assert row_value(inspector.rows, "Observable") == "HK.counter"
    assert row_value(inspector.rows, "Point") == "HK.counter"
    assert row_value(inspector.rows, "Sample count") == "42"
    assert row_value(inspector.rows, "Authority") == "authoritative"
    assert row_value(inspector.rows, "Reason") == "operator_backfill"
    assert row_value(inspector.rows, "Workflow job") == job.job_id
    assert row_value(inspector.rows, "Workflow job status") == "queued"
    assert row_value(inspector.rows, "Workflow job attempts") == "0"
    assert row_value(inspector.context_rows, "Source request") == "events-request-1"
    assert row_value(inspector.context_rows, "Logical source") == "events"
    assert related_link(inspector.related_links, :telemetry_point, "HK.counter")

    comparison_review_link =
      related_link(
        inspector.related_links,
        :dashboard_lifecycle_event,
        comparison_review_request.dashboard_lifecycle_event_id
      )

    assert comparison_review_link
    assert comparison_review_link.relationship_kind == :comparison_review_origin

    assert {:ok, comparison_review_inspector} =
             DataLinkResolver.resolve(comparison_review_link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert comparison_review_inspector.status == :resolved
    assert comparison_review_inspector.target == :dashboard_lifecycle_event

    assert row_value(comparison_review_inspector.rows, "Dashboard lifecycle event") ==
             comparison_review_request.dashboard_lifecycle_event_id

    assert row_value(comparison_review_inspector.rows, "Dashboard") == "dashboard-resolver-1"

    assert row_value(comparison_review_inspector.rows, "Event type") ==
             "comparison_review_requested"

    assert row_value(comparison_review_inspector.rows, "Dashboard version") == "7"

    assert row_value(comparison_review_inspector.rows, "Payload schema") ==
             "dashboard_comparison_review_request.v1"

    assert row_value(comparison_review_inspector.rows, "Comparison review kind") ==
             "comparison_open_findings_review"

    assert row_value(comparison_review_inspector.rows, "Comparison review open count") == "2"

    assert row_value(comparison_review_inspector.rows, "Comparison review placements") ==
             "placement-1,placement-2"

    assert {:error, missing_inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: "mission-other"
             )

    assert missing_inspector.status == :missing
  end

  test "resolves telemetry backfill lifecycle missing replacement inspection rows" do
    organization_id = "org-resolver-backfill-missing-replacement"
    mission_id = "mission-resolver-backfill-missing-replacement"
    persist_mission_scope(organization_id, mission_id)

    assert {:ok, event} =
             Storage.record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "resolver-missing-replacement-inspection-1",
                 backfill_run_id: "resolver-corrected-run-1",
                 organization_id: organization_id,
                 mission_id: mission_id,
                 realm: :backfill,
                 replay_run_id: "resolver-missing-replacement-replay-1",
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 event_type: :backfill_missing_replacement_inspected,
                 authority: :advisory,
                 reason: "dashboard_historical_workflow_missing_replacement_inspected",
                 actor_id: "ops-1",
                 actor_kind: "operator",
                 occurred_at: ~U[2026-06-22 12:24:00Z],
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "missing_replacement_inspected",
                   "run_id" => "resolver-corrected-run-1",
                   "request_group_id" => "resolver-missing-group-1",
                   "missing_replacement_action" => "inspect_missing_replacement_job",
                   "missing_replacement_source_event_id" => "resolver-source-failed-event-1",
                   "missing_replacement_source_event_type" => "backfill_failed",
                   "missing_replacement_run_id" => "resolver-corrected-run-1",
                   "missing_replacement_expected_job_type" => "telemetry_historical_data_workflow"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

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

    assert inspector.status == :resolved
    assert inspector.target == :telemetry_backfill_lifecycle_event

    assert row_value(inspector.rows, "Backfill lifecycle event") ==
             event.backfill_lifecycle_event_id

    assert row_value(inspector.rows, "Backfill run") == "resolver-corrected-run-1"
    assert row_value(inspector.rows, "Event type") == "backfill_missing_replacement_inspected"
    assert row_value(inspector.rows, "Workflow") == "backfill"
    assert row_value(inspector.rows, "Workflow stage") == "missing_replacement_inspected"
    assert row_value(inspector.rows, "Workflow run") == "resolver-corrected-run-1"
    assert row_value(inspector.rows, "Request group") == "resolver-missing-group-1"

    assert row_value(inspector.rows, "Missing replacement action") ==
             "inspect_missing_replacement_job"

    assert row_value(inspector.rows, "Missing replacement source event") ==
             "resolver-source-failed-event-1"

    assert row_value(inspector.rows, "Missing replacement source event type") ==
             "backfill_failed"

    assert row_value(inspector.rows, "Missing replacement run") == "resolver-corrected-run-1"

    assert row_value(inspector.rows, "Missing replacement expected job type") ==
             "telemetry_historical_data_workflow"

    assert row_value(inspector.rows, "Workflow job status") == "missing"
    assert related_link(inspector.related_links, :telemetry_point, "HK.counter")
  end

  test "resolves grouped telemetry backfill lifecycle job progress" do
    organization_id = "org-resolver-backfill-group-jobs"
    mission_id = "mission-resolver-backfill-group-jobs"
    persist_mission_scope(organization_id, mission_id)

    base_event = %{
      organization_id: organization_id,
      mission_id: mission_id,
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      source_from: ~U[2026-06-22 10:00:00Z],
      source_to: ~U[2026-06-22 11:00:00Z],
      authority: :advisory,
      reason: :operator_requested_bulk_backfill_from_dashboard,
      actor_id: "ops-1",
      actor_kind: "operator"
    }

    requested_items = [
      {"resolver-backfill-group-event-001", "resolver-backfill-group-run-001", "HK.counter", 1},
      {"resolver-backfill-group-event-002", "resolver-backfill-group-run-002", "HK.voltage", 2},
      {"resolver-backfill-group-event-003", "resolver-backfill-group-run-003", "HK.current", 3}
    ]

    events =
      Enum.map(requested_items, fn {event_id, run_id, point_id, item_index} ->
        assert {:ok, event} =
                 Storage.record_backfill_lifecycle_event(
                   Map.merge(base_event, %{
                     backfill_lifecycle_event_id: event_id,
                     backfill_run_id: run_id,
                     observable_id: point_id,
                     point_id: point_id,
                     event_type: :backfill_requested,
                     payload: %{
                       "workflow" => "backfill",
                       "stage" => "requested",
                       "run_id" => run_id,
                       "request_mode" => "bulk_points",
                       "request_group_id" => "resolver-backfill-group",
                       "request_item_index" => item_index,
                       "request_item_count" => 3,
                       "request_item_run_id" => run_id,
                       "comparison_review_origin" => %{
                         "request_event_id" => "review-request-group-resolver",
                         "request_kind" => "comparison_open_findings_review",
                         "open_count" => "3",
                         "open_placement_ids" => "placement-1,placement-2,placement-3"
                       }
                     }
                   }),
                   dashboard_runtime_invalidation?: false
                 )

        event
      end)

    jobs =
      Enum.map(requested_items, fn {_event_id, run_id, _point_id, _item_index} ->
        assert {:ok, job} =
                 Cadence.Jobs.enqueue(
                   :telemetry_historical_data_workflow,
                   mission_id,
                   run_id,
                   %{
                     "workflow" => "backfill",
                     "attrs" => %{"backfill_run_id" => run_id}
                   }
                 )

        job
      end)

    [_counter_job, voltage_job, current_job] = jobs

    assert {:ok, failed_voltage_job} =
             Cadence.Jobs.fail_worker_start(voltage_job.job_id, :source_window_failed)

    assert failed_voltage_job.status == :failed

    assert {:ok, failed_current_job} =
             Cadence.Jobs.fail_worker_start(current_job.job_id, :missing_point_id)

    assert failed_current_job.status == :failed

    assert {:ok, failed_voltage_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-backfill-group-failed-002",
                 backfill_run_id: "resolver-backfill-group-run-002",
                 observable_id: "HK.voltage",
                 point_id: "HK.voltage",
                 event_type: :backfill_failed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "failed",
                   "run_id" => "resolver-backfill-group-run-002",
                   "request_group_id" => "resolver-backfill-group",
                   "request_item_index" => 2,
                   "request_item_count" => 3,
                   "request_item_run_id" => "resolver-backfill-group-run-002"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, failed_current_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-backfill-group-failed-003",
                 backfill_run_id: "resolver-backfill-group-run-003",
                 observable_id: "HK.current",
                 point_id: "HK.current",
                 event_type: :backfill_failed,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "failed",
                   "run_id" => "resolver-backfill-group-run-003",
                   "request_group_id" => "resolver-backfill-group",
                   "request_item_index" => 3,
                   "request_item_count" => 3,
                   "request_item_run_id" => "resolver-backfill-group-run-003"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _retry_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-backfill-group-retry-002",
                 backfill_run_id: "resolver-backfill-group-run-002",
                 observable_id: "HK.voltage",
                 point_id: "HK.voltage",
                 event_type: :backfill_retried,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "retried",
                   "run_id" => "resolver-backfill-group-run-002",
                   "request_group_id" => "resolver-backfill-group",
                   "request_item_index" => 2,
                   "request_item_count" => 3,
                   "request_item_run_id" => "resolver-backfill-group-run-002",
                   "retry_source_event_id" => failed_voltage_event.backfill_lifecycle_event_id,
                   "retry_job_id" => voltage_job.job_id,
                   "retry_job_status" => "queued"
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _correction_event} =
             Storage.record_backfill_lifecycle_event(
               Map.merge(base_event, %{
                 backfill_lifecycle_event_id: "resolver-backfill-group-correction-003",
                 backfill_run_id: "resolver-backfill-group-run-003-corrected",
                 observable_id: "HK.current",
                 point_id: "HK.current",
                 event_type: :backfill_requested,
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "requested",
                   "run_id" => "resolver-backfill-group-run-003-corrected",
                   "request_group_id" => "resolver-backfill-group",
                   "request_item_index" => 3,
                   "request_item_count" => 3,
                   "request_item_run_id" => "resolver-backfill-group-run-003-corrected",
                   "corrects_event_id" => failed_current_event.backfill_lifecycle_event_id,
                   "corrects_run_id" => "resolver-backfill-group-run-003",
                   "corrects_job_id" => current_job.job_id
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    [selected_event | _events] = events

    link = %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: selected_event.backfill_lifecycle_event_id,
      context: %{logical_source: :events},
      source: :frame
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link,
               organization_id: organization_id,
               mission_id: mission_id
             )

    assert row_value(inspector.rows, "Request group") == "resolver-backfill-group"

    assert row_value(inspector.rows, "Comparison review request") ==
             "review-request-group-resolver"

    assert row_value(inspector.rows, "Comparison review open count") == "3"

    assert row_value(inspector.rows, "Comparison review placements") ==
             "placement-1,placement-2,placement-3"

    assert row_value(inspector.rows, "Request group progress") ==
             "0/3 completed, 0 failed, 2 resolved"

    assert row_value(inspector.rows, "Request group job progress") ==
             "queued 1, failed 1, missing 1"

    group_job_items = row_value(inspector.rows, "Request group job items")

    assert group_job_items =~
             "1:HK.counter resolver-backfill-group-run-001 queued #{Enum.at(jobs, 0).job_id}"

    assert group_job_items =~
             "2:HK.voltage resolver-backfill-group-run-002 failed #{Enum.at(jobs, 1).job_id} event="

    assert group_job_items =~
             "2:HK.voltage resolver-backfill-group-run-002 failed #{Enum.at(jobs, 1).job_id}"

    assert group_job_items =~ "completed="

    assert group_job_items =~ "3:HK.current resolver-backfill-group-run-003-corrected missing"

    assert row_value(inspector.rows, "Request group retried items") ==
             "HK.voltage resolver-backfill-group-run-002 retried queued #{voltage_job.job_id}"

    assert row_value(inspector.rows, "Request group corrected items") ==
             "HK.current resolver-backfill-group-run-003 corrected resolver-backfill-group-run-003-corrected requested #{current_job.job_id}"

    assert row_value(inspector.rows, "Request group correction tasks") ==
             "HK.current resolver-backfill-group-run-003 replacement resolver-backfill-group-run-003-corrected stage requested next approve"
  end
end
