defmodule Cadence.Telemetry.Storage.ObservationIdentityStatesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.TelemetryRevisionSummary
  alias Cadence.OperationalEvents
  alias Cadence.Platform.EventBus
  alias Cadence.Telemetry.ObservationIdentityStateChanged
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, ObservationIdentityStates, WriteContext}

  test "envelope state publication uses the explicitly selected event bus" do
    event_bus = start_event_bus()
    assert :ok = Cadence.Telemetry.Facts.subscribe(event_bus, self())
    envelope = envelope(sample_id: "sample-explicit-bus", revision: 1)

    assert :ok = ObservationIdentityStates.record_envelopes([envelope], event_bus: event_bus)

    assert_receive {:"$gen_cast",
                    {:cadence_fact, {:cadence, :telemetry, :facts},
                     %ObservationIdentityStateChanged{} = fact}}

    assert fact.observation_identity_id == envelope.observation_identity_id
    refute_receive {:"$gen_cast", {:cadence_fact, {:cadence, :telemetry, :facts}, _fact}}
  end

  test "records the first canonical observation for an identity" do
    envelope = envelope(sample_id: "sample-1", revision: 1)

    assert :ok = ObservationIdentityStates.record_envelopes([envelope])
    assert {:ok, state} = ObservationIdentityStates.fetch(envelope.observation_identity_id)

    assert state.canonical_observation_id == envelope.observation_id
    assert state.canonical_sample_id == "sample-1"
    assert state.canonical_revision == 1
    assert state.latest_observation_id == envelope.observation_id
    assert state.realm == :flight
    assert state.validity_state == :canonical
    assert state.canonical_count == 1
    assert state.duplicate_count == 0
    assert state.conflict_count == 0
  end

  test "keeps canonical selection while counting alternate-path duplicates" do
    canonical = envelope(sample_id: "sample-primary", data_source_id: "ds-primary")

    duplicate =
      envelope(
        sample_id: "sample-backup",
        data_source_id: "ds-backup",
        validity_state: :duplicate
      )

    assert canonical.observation_identity_id == duplicate.observation_identity_id

    assert :ok = ObservationIdentityStates.record_envelopes([canonical, duplicate])
    assert {:ok, state} = ObservationIdentityStates.fetch(canonical.observation_identity_id)

    assert state.canonical_observation_id == canonical.observation_id
    assert state.canonical_sample_id == "sample-primary"
    assert state.latest_observation_id == duplicate.observation_id
    assert state.latest_sample_id == "sample-backup"
    assert state.validity_state == :canonical
    assert state.canonical_count == 1
    assert state.duplicate_count == 1
  end

  test "replayed observation writes are idempotent for identity counters" do
    envelope = envelope(sample_id: "sample-idempotent", revision: 1)

    assert :ok = ObservationIdentityStates.record_envelopes([envelope])
    assert :ok = ObservationIdentityStates.record_envelopes([envelope])

    assert {:ok, state} = ObservationIdentityStates.fetch(envelope.observation_identity_id)

    assert state.latest_observation_id == envelope.observation_id
    assert state.canonical_observation_id == envelope.observation_id
    assert state.canonical_count == 1
    assert state.duplicate_count == 0
    assert state.conflict_count == 0
    assert state.superseded_count == 0
    assert state.advisory_count == 0
  end

  test "promotes a higher canonical revision and records supersession metadata" do
    initial = envelope(sample_id: "sample-initial", revision: 1)

    correction =
      envelope(
        sample_id: "sample-correction",
        revision: 2,
        raw_value: 43,
        supersedes_observation_id: initial.observation_id
      )

    assert :ok = ObservationIdentityStates.record_envelopes([initial, correction])
    assert {:ok, state} = ObservationIdentityStates.fetch(correction.observation_identity_id)

    assert state.canonical_observation_id == correction.observation_id
    assert state.canonical_sample_id == "sample-correction"
    assert state.canonical_revision == 2
    assert state.canonical_count == 2
    assert state.decision_reason == "canonical_revision"
    assert state.payload["latest_observation_id"] == correction.observation_id
    assert state.payload["supersedes_observation_id"] == initial.observation_id
  end

  test "records conflicts without promoting them to canonical" do
    canonical = envelope(sample_id: "sample-canonical")
    conflict = envelope(sample_id: "sample-conflict", validity_state: :conflict)

    assert :ok = ObservationIdentityStates.record_envelopes([canonical, conflict])
    assert {:ok, state} = ObservationIdentityStates.fetch(canonical.observation_identity_id)

    assert state.canonical_observation_id == canonical.observation_id
    assert state.latest_observation_id == conflict.observation_id
    assert state.validity_state == :conflict
    assert state.canonical_count == 1
    assert state.conflict_count == 1
  end

  test "applies an operator decision to resolve conflict state and select canonical observation" do
    canonical = envelope(sample_id: "sample-decision-canonical")
    conflict = envelope(sample_id: "sample-decision-conflict", validity_state: :conflict)

    assert :ok = ObservationIdentityStates.record_envelopes([canonical, conflict])
    assert {:ok, before} = ObservationIdentityStates.fetch(canonical.observation_identity_id)
    assert before.validity_state == :conflict

    before_fingerprint =
      TelemetryRevisionSummary.from_identity_states([before]).dependency_fingerprint

    decided_at = ~U[2026-06-22 12:10:00Z]
    attach_runtime_invalidation_telemetry(self())

    assert {:ok, state} =
             Storage.apply_observation_identity_decision(
               canonical.observation_identity_id,
               :mark_canonical,
               organization_id: canonical.organization_id,
               mission_id: canonical.mission_id,
               realm: canonical.realm,
               data_source_id: canonical.data_source_id,
               binding_id: canonical.binding_id,
               canonical_observation_id: conflict.observation_id,
               canonical_sample_id: conflict.sample_id,
               canonical_revision: conflict.revision,
               decision_reason: "operator_selected_conflict_candidate",
               decided_at: decided_at,
               operator_id: "ops-1"
             )

    assert state.validity_state == :canonical
    assert state.canonical_observation_id == conflict.observation_id
    assert state.canonical_sample_id == conflict.sample_id
    assert state.canonical_revision == conflict.revision
    assert state.conflict_count == 1
    assert state.decision_reason == "operator_selected_conflict_candidate"
    assert DateTime.compare(state.decided_at, decided_at) == :eq
    assert state.payload["decision"]["decision"] == "mark_canonical"
    assert state.payload["decision"]["operator_id"] == "ops-1"

    assert [event] =
             Storage.list_observation_identity_decision_events(
               canonical.observation_identity_id,
               organization_id: canonical.organization_id,
               mission_id: canonical.mission_id,
               realm: canonical.realm,
               data_source_id: canonical.data_source_id,
               binding_id: canonical.binding_id
             )

    assert event.observation_identity_id == canonical.observation_identity_id
    assert event.decision == :mark_canonical
    assert event.decision_reason == "operator_selected_conflict_candidate"
    assert event.actor_id == "ops-1"
    assert event.actor_kind == "operator"
    assert event.previous_state["validity_state"] == "conflict"
    assert event.new_state["validity_state"] == "canonical"
    assert event.new_state["canonical_observation_id"] == conflict.observation_id
    assert DateTime.compare(event.occurred_at, decided_at) == :eq
    assert state.decision_event_id == event.decision_event_id

    assert fetched =
             Storage.fetch_observation_identity_decision_event(
               event.decision_event_id,
               organization_id: canonical.organization_id,
               mission_id: canonical.mission_id
             )

    assert fetched.decision_event_id == event.decision_event_id
    assert fetched.observation_identity_id == canonical.observation_identity_id

    assert [operational_event] =
             OperationalEvents.list_events(canonical.organization_id, canonical.mission_id,
               category: :telemetry,
               kind: :telemetry_observation_marked_canonical,
               source_record_kind: :telemetry_observation_identity_decision_event,
               source_record_id: event.decision_event_id
             )

    assert operational_event.subject == %{kind: :telemetry_point, id: canonical.point_id}
    assert operational_event.scope["data_source_id"] == canonical.data_source_id
    assert operational_event.scope["source_binding_id"] == canonical.binding_id
    assert operational_event.payload["decision"] == "mark_canonical"
    assert operational_event.previous["validity_state"] == "conflict"
    assert operational_event.current["validity_state"] == "canonical"

    refute Storage.fetch_observation_identity_decision_event(
             event.decision_event_id,
             organization_id: canonical.organization_id,
             mission_id: "mission-other"
           )

    after_fingerprint =
      TelemetryRevisionSummary.from_identity_states([state]).dependency_fingerprint

    assert after_fingerprint != before_fingerprint

    assert_receive {:runtime_invalidation_telemetry, metadata}
    assert metadata.boundary == :telemetry_revision_state_changed
    assert metadata.filters.observation_identity_id == state.observation_identity_id

    assert metadata.filters.telemetry_revision_dependency.fingerprint ==
             state_dependency(state).fingerprint
  end

  test "requires tenant context when applying observation identity decisions" do
    envelope = envelope(sample_id: "sample-decision-context")
    assert :ok = ObservationIdentityStates.record_envelopes([envelope])

    assert {:error, {:missing_field, :organization_id}} =
             Storage.apply_observation_identity_decision(
               envelope.observation_identity_id,
               :mark_conflict,
               mission_id: envelope.mission_id
             )

    assert {:error, :observation_identity_state_not_found} =
             Storage.apply_observation_identity_decision(
               envelope.observation_identity_id,
               :mark_conflict,
               organization_id: envelope.organization_id,
               mission_id: "wrong-mission"
             )
  end

  test "keeps replay identity states and decisions isolated by replay run" do
    replay_one =
      envelope(
        sample_id: "sample-replay-decision-1",
        realm: :replay,
        replay_run_id: "replay-run-1",
        data_source_id: "ds-replay",
        binding_id: "binding-replay",
        validity_state: :conflict
      )

    replay_two =
      envelope(
        sample_id: "sample-replay-decision-2",
        realm: :replay,
        replay_run_id: "replay-run-2",
        data_source_id: "ds-replay",
        binding_id: "binding-replay",
        validity_state: :conflict
      )

    assert :ok = ObservationIdentityStates.record_envelopes([replay_one, replay_two])

    assert {:ok, replay_one_state} =
             ObservationIdentityStates.fetch(replay_one.observation_identity_id)

    assert replay_one_state.replay_run_id == "replay-run-1"

    assert [listed_state] =
             ObservationIdentityStates.list("mission-identity",
               organization_id: "org-identity",
               realm: :replay,
               replay_run_id: "replay-run-1",
               data_source_id: "ds-replay",
               binding_id: "binding-replay"
             )

    assert listed_state.observation_identity_id == replay_one.observation_identity_id

    assert [] =
             ObservationIdentityStates.list("mission-identity",
               organization_id: "org-identity",
               realm: :replay,
               replay_run_id: "replay-run-3",
               data_source_id: "ds-replay",
               binding_id: "binding-replay"
             )

    attach_runtime_invalidation_telemetry(self())

    assert {:ok, decided_state} =
             Storage.apply_observation_identity_decision(
               replay_one.observation_identity_id,
               :mark_conflict,
               organization_id: replay_one.organization_id,
               mission_id: replay_one.mission_id,
               realm: replay_one.realm,
               replay_run_id: replay_one.replay_run_id,
               data_source_id: replay_one.data_source_id,
               binding_id: replay_one.binding_id,
               decision_reason: "operator_reviewed_replay_conflict",
               decided_at: ~U[2026-06-22 12:10:00Z],
               refresh_latest_value?: false
             )

    assert decided_state.replay_run_id == "replay-run-1"

    assert [event] =
             Storage.list_observation_identity_decision_events_for_mission(
               replay_one.mission_id,
               organization_id: replay_one.organization_id,
               realm: :replay,
               replay_run_id: "replay-run-1",
               data_source_id: replay_one.data_source_id,
               binding_id: replay_one.binding_id
             )

    assert event.observation_identity_id == replay_one.observation_identity_id
    assert event.replay_run_id == "replay-run-1"
    assert event.new_state["replay_run_id"] == "replay-run-1"

    assert [] =
             Storage.list_observation_identity_decision_events_for_mission(
               replay_one.mission_id,
               organization_id: replay_one.organization_id,
               realm: :replay,
               replay_run_id: "replay-run-2",
               data_source_id: replay_one.data_source_id,
               binding_id: replay_one.binding_id
             )

    assert_receive {:runtime_invalidation_telemetry, metadata}
    assert metadata.boundary == :telemetry_revision_state_changed
    assert metadata.filters.replay_run_id == "replay-run-1"
    assert metadata.filters.observation_identity_id == replay_one.observation_identity_id
  end

  test "lists decision events by mission source observable and time window" do
    in_range = envelope(sample_id: "sample-decision-list-in-range", point_id: "HK.counter")

    out_of_range =
      envelope(sample_id: "sample-decision-list-out-of-range", point_id: "HK.counter")

    other_point =
      envelope(sample_id: "sample-decision-list-other-point", point_id: "HK.voltage")

    assert :ok = ObservationIdentityStates.record_envelopes([in_range, out_of_range, other_point])

    assert {:ok, _state} =
             Storage.apply_observation_identity_decision(
               in_range.observation_identity_id,
               :mark_conflict,
               organization_id: in_range.organization_id,
               mission_id: in_range.mission_id,
               realm: in_range.realm,
               data_source_id: in_range.data_source_id,
               binding_id: in_range.binding_id,
               decision_reason: "operator_marked_counter_conflict",
               decided_at: ~U[2026-06-22 12:10:00Z],
               operator_id: "ops-1",
               refresh_latest_value?: false,
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _state} =
             Storage.apply_observation_identity_decision(
               out_of_range.observation_identity_id,
               :mark_conflict,
               organization_id: out_of_range.organization_id,
               mission_id: out_of_range.mission_id,
               realm: out_of_range.realm,
               data_source_id: out_of_range.data_source_id,
               binding_id: out_of_range.binding_id,
               decision_reason: "old_counter_conflict",
               decided_at: ~U[2026-06-22 11:30:00Z],
               refresh_latest_value?: false,
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _state} =
             Storage.apply_observation_identity_decision(
               other_point.observation_identity_id,
               :mark_conflict,
               organization_id: other_point.organization_id,
               mission_id: other_point.mission_id,
               realm: other_point.realm,
               data_source_id: other_point.data_source_id,
               binding_id: other_point.binding_id,
               decision_reason: "voltage_conflict",
               decided_at: ~U[2026-06-22 12:12:00Z],
               refresh_latest_value?: false,
               dashboard_runtime_invalidation?: false
             )

    assert [event] =
             Storage.list_observation_identity_decision_events_for_mission(
               in_range.mission_id,
               organization_id: in_range.organization_id,
               realm: in_range.realm,
               data_source_id: in_range.data_source_id,
               binding_id: in_range.binding_id,
               point_id: "HK.counter",
               from_occurred_at: ~U[2026-06-22 12:00:00Z],
               to_occurred_at: ~U[2026-06-22 12:30:00Z]
             )

    assert event.observation_identity_id == in_range.observation_identity_id
    assert event.decision == :mark_conflict
    assert event.decision_reason == "operator_marked_counter_conflict"
    assert event.actor_id == "ops-1"
    assert event.point_id == "HK.counter"
  end

  test "rolls back projection decisions when the audit event is invalid" do
    canonical = envelope(sample_id: "sample-decision-rollback-canonical")
    conflict = envelope(sample_id: "sample-decision-rollback-conflict", validity_state: :conflict)

    assert :ok = ObservationIdentityStates.record_envelopes([canonical, conflict])
    assert {:ok, before} = ObservationIdentityStates.fetch(canonical.observation_identity_id)

    assert {:error, %Ecto.Changeset{}} =
             Storage.apply_observation_identity_decision(
               canonical.observation_identity_id,
               :mark_canonical,
               organization_id: canonical.organization_id,
               mission_id: canonical.mission_id,
               realm: canonical.realm,
               data_source_id: canonical.data_source_id,
               binding_id: canonical.binding_id,
               canonical_observation_id: conflict.observation_id,
               canonical_sample_id: conflict.sample_id,
               canonical_revision: conflict.revision,
               decision_reason: "invalid_event_payload",
               evidence_ref: "not-a-map"
             )

    assert {:ok, after_rollback} =
             ObservationIdentityStates.fetch(canonical.observation_identity_id)

    assert after_rollback.validity_state == before.validity_state
    assert after_rollback.canonical_observation_id == before.canonical_observation_id
    assert after_rollback.decision_reason == before.decision_reason

    assert [] =
             Storage.list_observation_identity_decision_events(
               canonical.observation_identity_id,
               organization_id: canonical.organization_id,
               mission_id: canonical.mission_id
             )
  end

  test "emits runtime invalidation for changed observation identity state" do
    attach_runtime_invalidation_telemetry(self())
    envelope = envelope(sample_id: "sample-invalidation")

    assert :ok = ObservationIdentityStates.record_envelopes([envelope])

    assert_receive {:runtime_invalidation_telemetry, metadata}
    assert metadata.boundary == :telemetry_revision_state_changed
    assert metadata.filters.organization_id == envelope.organization_id
    assert metadata.filters.mission_id == envelope.mission_id
    assert metadata.filters.logical_source == :telemetry
    assert metadata.filters.data_source_id == envelope.data_source_id
    assert metadata.filters.source_binding_id == envelope.binding_id
    assert metadata.filters.realm == envelope.realm
    assert metadata.filters.observable == envelope.observable_id
    assert metadata.filters.observation_identity_id == envelope.observation_identity_id
  end

  test "lists identity states by mission and query filters" do
    flight_conflict = envelope(sample_id: "sample-flight-conflict", validity_state: :conflict)

    rehearsal =
      envelope(
        sample_id: "sample-rehearsal",
        realm: :rehearsal,
        data_source_id: "ds-rehearsal",
        point_id: "HK.voltage"
      )

    other_mission =
      envelope(
        sample_id: "sample-other-mission",
        mission_id: "mission-other",
        point_id: "HK.counter"
      )

    assert :ok =
             ObservationIdentityStates.record_envelopes([
               flight_conflict,
               rehearsal,
               other_mission
             ])

    assert [state] =
             ObservationIdentityStates.list("mission-identity",
               validity_state: :conflict,
               point_id: "HK.counter"
             )

    assert state.observation_identity_id == flight_conflict.observation_identity_id
    assert state.validity_state == :conflict

    assert [state] =
             ObservationIdentityStates.list("mission-identity",
               realm: "rehearsal",
               data_source_id: "ds-rehearsal"
             )

    assert state.observation_identity_id == rehearsal.observation_identity_id
    assert state.realm == :rehearsal

    assert Enum.all?(
             ObservationIdentityStates.list("mission-identity"),
             &(&1.mission_id == "mission-identity")
           )
  end

  test "exposes identity state reads through the telemetry storage API" do
    envelope = envelope(sample_id: "sample-public-api", spacecraft_id: "sc-public")

    assert :ok = ObservationIdentityStates.record_envelopes([envelope])

    assert {:ok, fetched} =
             Storage.fetch_observation_identity_state(envelope.observation_identity_id)

    assert fetched.observation_identity_id == envelope.observation_identity_id

    assert [listed] =
             Storage.list_observation_identity_states("mission-identity",
               spacecraft_id: "sc-public"
             )

    assert listed.observation_identity_id == envelope.observation_identity_id
  end

  test "bulk fetches identity states by observation identity id" do
    first = envelope(sample_id: "sample-bulk-first", point_id: "HK.counter")
    second = envelope(sample_id: "sample-bulk-second", point_id: "HK.voltage")
    other_mission = envelope(sample_id: "sample-bulk-other-mission", mission_id: "mission-other")

    assert :ok = ObservationIdentityStates.record_envelopes([first, second, other_mission])

    states =
      Storage.fetch_observation_identity_states(
        [
          first.observation_identity_id,
          second.observation_identity_id,
          other_mission.observation_identity_id,
          first.observation_identity_id,
          nil,
          ""
        ],
        organization_id: "org-identity",
        mission_id: "mission-identity",
        realm: :flight,
        data_source_id: "ds-primary",
        binding_id: "binding-v1"
      )

    assert Enum.map(states, & &1.observation_identity_id) |> Enum.sort() ==
             [first.observation_identity_id, second.observation_identity_id] |> Enum.sort()

    assert [] =
             Storage.fetch_observation_identity_states(
               [first.observation_identity_id],
               organization_id: "org-identity",
               mission_id: "mission-other"
             )

    assert [] =
             Storage.fetch_observation_identity_states([first.observation_identity_id],
               mission_id: "mission-identity"
             )
  end

  defp envelope(overrides) do
    validity_state = Keyword.get(overrides, :validity_state, :canonical)
    revision = Keyword.get(overrides, :revision, 1)
    raw_value = Keyword.get(overrides, :raw_value, 42)
    mission_id = Keyword.get(overrides, :mission_id, "mission-identity")

    {:ok, context} =
      WriteContext.new(
        organization_id: Keyword.get(overrides, :organization_id, "org-identity"),
        mission_id: mission_id,
        realm: Keyword.get(overrides, :realm, :flight),
        replay_run_id: Keyword.get(overrides, :replay_run_id),
        data_source_id: Keyword.get(overrides, :data_source_id, "ds-primary"),
        binding_id: Keyword.get(overrides, :binding_id, "binding-v1"),
        source_endpoint_id: Keyword.get(overrides, :source_endpoint_id, "station-a"),
        recorded_at: Keyword.get(overrides, :recorded_at, ~U[2026-06-22 12:00:00Z]),
        metadata: %{}
      )

    sample = %Sample{
      sample_id: Keyword.fetch!(overrides, :sample_id),
      mission_id: mission_id,
      spacecraft_id: Keyword.get(overrides, :spacecraft_id, "sc-1"),
      point_id: Keyword.get(overrides, :point_id, "HK.counter"),
      point_name:
        Keyword.get(overrides, :point_name, Keyword.get(overrides, :point_id, "HK.counter")),
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id:
        Keyword.get(overrides, :packet_id, "packet-" <> Keyword.fetch!(overrides, :sample_id)),
      evidence_id:
        Keyword.get(overrides, :evidence_id, "evidence-" <> Keyword.fetch!(overrides, :sample_id)),
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      generation_time: ~U[2026-06-22 11:59:59Z],
      receipt_time: ~U[2026-06-22 12:00:00Z],
      provenance: %{}
    }

    {:ok, envelope} =
      ObservationEnvelope.from_sample(context, sample,
        validity_state: validity_state,
        revision: revision,
        supersedes_observation_id: Keyword.get(overrides, :supersedes_observation_id)
      )

    envelope
  end

  defp attach_runtime_invalidation_telemetry(test_pid) do
    handler_id = "observation-identity-state-invalidation-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [RuntimeInvalidation.telemetry_event()],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:runtime_invalidation_telemetry, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp state_dependency(state) do
    state
    |> List.wrap()
    |> TelemetryRevisionSummary.from_identity_states()
    |> Map.fetch!(:dependency)
  end

  defp start_event_bus do
    start_supervised!(%{
      id: {:observation_identity_fact_event_bus, make_ref()},
      start: {EventBus, :start_link, [[name: nil, delivery: :async, before_notify: nil]]},
      restart: :temporary
    })
  end
end
