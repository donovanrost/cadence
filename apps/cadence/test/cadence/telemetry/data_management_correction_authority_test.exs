defmodule Cadence.Telemetry.DataManagementCorrectionAuthorityTest do
  use Cadence.ConfigCase, async: false

  import Cadence.Telemetry.DataManagementFixtures

  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.HistoryStore
  alias Cadence.Telemetry.Storage

  setup do
    persistence_policy = data_management_persistence_policy()

    start_supervised!(
      CurrentValueStore.child_spec(persistence_policy.storage.current_value_store_policy)
    )

    start_supervised!(HistoryStore.child_spec(persistence_policy.history_store))
    CurrentValueStore.reset(persistence_policy.storage.current_value_store_policy)
    HistoryStore.reset(persistence_policy.history_store)

    %{persistence_policy: persistence_policy}
  end

  test "applies correction-authority decisions with dashboard-readable evidence", %{
    persistence_policy: persistence_policy
  } do
    initial =
      sample("sample-correction-initial", ~U[2026-06-22 11:10:00Z], ~U[2026-06-22 12:10:03Z])

    correction = %{initial | sample_id: "sample-correction-candidate", raw_value: 43}

    assert :ok =
             Storage.persist_samples(persistence_policy.storage, [initial],
               organization_id: "org-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry",
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, [initial_envelope]}

    assert :ok =
             Storage.persist_samples(persistence_policy.storage, [correction],
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

  test "applies bulk correction-authority decisions with shared workflow evidence", %{
    persistence_policy: persistence_policy
  } do
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
             Storage.persist_samples(
               persistence_policy.storage,
               [initial_counter, initial_voltage],
               organization_id: "org-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry",
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, initial_envelopes}

    assert :ok =
             Storage.persist_samples(
               persistence_policy.storage,
               [correction_counter, correction_voltage],
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

  test "applies bulk comparison-review conflict decisions with workflow evidence", %{
    persistence_policy: persistence_policy
  } do
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
             Storage.persist_samples(persistence_policy.storage, [counter, voltage],
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

  test "rejects mixed-mission backfill samples before writing", %{
    persistence_policy: persistence_policy
  } do
    first = sample("sample-backfill-1", ~U[2026-06-22 11:00:00Z], ~U[2026-06-22 12:00:03Z])
    second = %{first | sample_id: "sample-backfill-2", mission_id: "mission-other"}

    assert {:error, {:mixed_mission_samples, ["mission-product", "mission-other"]}} =
             Cadence.backfill_telemetry_samples(
               [first, second],
               %{
                 backfill_run_id: "backfill-run-product",
                 organization_id: "org-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry"
               },
               persistence_policy: persistence_policy
             )
  end
end
