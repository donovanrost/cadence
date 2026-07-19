defmodule Cadence.Projections.TelemetryLatestValuesTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.Schemas.{PacketRecordRow, RawEvidenceRow, TelemetryLatestValueRow}
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage

  test "rebuilds the latest-value projection from canonical telemetry samples" do
    binding_set = persist_binding_set_fixture()

    older_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        receipt_time: DateTime.from_unix!(1_700_000_010, :second),
        raw: build_space_packet(42, 1, <<0, 10>>)
      })

    newer_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        receipt_time: DateTime.from_unix!(1_700_000_020, :second),
        raw: build_space_packet(42, 2, <<0, 20>>)
      })

    assert {:ok, _older_result} =
             Cadence.process_and_persist_telemetry_ingress(
               older_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _newer_result} =
             Cadence.process_and_persist_telemetry_ingress(
               newer_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter").raw_value == 20

    Repo.delete_all(TelemetryLatestValueRow)
    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter") == nil

    assert {:ok, 1} = Cadence.rebuild_latest_telemetry_values("mission-alpha")
    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter").raw_value == 20
  end

  test "rebuild keeps late-arriving older source-time samples from replacing latest" do
    binding_set = persist_binding_set_fixture()

    current_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        source_time: DateTime.from_unix!(1_700_000_100, :second),
        receipt_time: DateTime.from_unix!(1_700_000_105, :second),
        raw: build_space_packet(42, 1, <<0, 20>>)
      })

    late_arrival =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        source_time: DateTime.from_unix!(1_700_000_000, :second),
        receipt_time: DateTime.from_unix!(1_700_000_200, :second),
        raw: build_space_packet(42, 2, <<0, 10>>)
      })

    assert {:ok, _current_result} =
             Cadence.process_and_persist_telemetry_ingress(
               current_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _late_result} =
             Cadence.process_and_persist_telemetry_ingress(
               late_arrival,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter").raw_value == 20

    Repo.delete_all(TelemetryLatestValueRow)

    assert {:ok, 1} = Cadence.rebuild_latest_telemetry_values("mission-alpha")
    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter").raw_value == 20
  end

  test "rebuild preserves source-scoped latest values for the same point" do
    flight_sample =
      sample("sample-rebuild-flight", 1, ~U[2026-06-21 12:00:00Z],
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    rehearsal_sample =
      sample("sample-rebuild-rehearsal", 2, ~U[2026-06-21 12:01:00Z],
        generation_time: ~U[2026-06-21 12:01:00Z]
      )

    persist_sample_scope!(flight_sample)
    persist_sample_scope!(rehearsal_sample)

    assert :ok =
             Storage.persist_samples([flight_sample],
               organization_id: "org-test",
               realm: :flight,
               data_source_id: "flight-questdb",
               binding_id: "flight-binding"
             )

    assert :ok =
             Storage.persist_samples([rehearsal_sample],
               organization_id: "org-test",
               realm: :rehearsal,
               data_source_id: "rehearsal-questdb",
               binding_id: "rehearsal-binding"
             )

    Repo.delete_all(TelemetryLatestValueRow)

    assert {:ok, 2} = Cadence.rebuild_latest_telemetry_values("mission-alpha")

    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter",
             realm: :flight,
             data_source_id: "flight-questdb",
             source_binding_id: "flight-binding"
           ).raw_value == 1

    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter",
             realm: :rehearsal,
             data_source_id: "rehearsal-questdb",
             source_binding_id: "rehearsal-binding"
           ).raw_value == 2
  end

  test "rebuild applies storage validity policy and ignores unresolved conflicts" do
    canonical =
      sample("sample-rebuild-canonical", 20, ~U[2026-06-21 12:00:03Z],
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    conflict =
      sample("sample-rebuild-conflict", 99, ~U[2026-06-21 12:00:05Z],
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    persist_sample_scope!(canonical)
    persist_sample_scope!(conflict)

    assert :ok = Storage.persist_samples([canonical], organization_id: "org-test")

    assert :ok =
             Storage.persist_samples([conflict],
               organization_id: "org-test",
               validity_state: :conflict
             )

    latest_before_rebuild = Cadence.latest_telemetry_value("mission-alpha", "HK.counter")
    assert latest_before_rebuild.sample_id == "sample-rebuild-canonical"
    assert latest_before_rebuild.raw_value == 20

    Repo.delete_all(TelemetryLatestValueRow)
    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter") == nil

    assert {:ok, 1} = Cadence.rebuild_latest_telemetry_values("mission-alpha")

    latest_after_rebuild = Cadence.latest_telemetry_value("mission-alpha", "HK.counter")
    assert latest_after_rebuild.sample_id == "sample-rebuild-canonical"
    assert latest_after_rebuild.raw_value == 20
    assert latest_after_rebuild.provenance["storage"]["validity_state"] == "canonical"
  end

  test "operator canonical decision promotes a conflicting sample into latest value" do
    canonical =
      sample("sample-decision-latest-canonical", 20, ~U[2026-06-21 12:00:03Z],
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    conflict =
      sample("sample-decision-latest-conflict", 99, ~U[2026-06-21 12:00:05Z],
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    persist_sample_scope!(canonical)
    persist_sample_scope!(conflict)

    assert :ok = Storage.persist_samples([canonical], organization_id: "org-test")

    assert :ok =
             Storage.persist_samples([conflict],
               organization_id: "org-test",
               validity_state: :conflict
             )

    latest_before_decision = Cadence.latest_telemetry_value("mission-alpha", "HK.counter")
    assert latest_before_decision.sample_id == canonical.sample_id

    [state] =
      Storage.list_observation_identity_states("mission-alpha",
        organization_id: "org-test",
        point_id: "HK.counter"
      )

    assert {:ok, _state} =
             Storage.apply_observation_identity_decision(
               state.observation_identity_id,
               :mark_canonical,
               organization_id: state.organization_id,
               mission_id: state.mission_id,
               realm: state.realm,
               data_source_id: state.data_source_id,
               binding_id: state.binding_id,
               canonical_observation_id: state.latest_observation_id,
               canonical_sample_id: conflict.sample_id,
               canonical_revision: state.latest_revision,
               decision_reason: "operator_selected_conflict_candidate",
               dashboard_runtime_invalidation?: false
             )

    latest_after_decision = Cadence.latest_telemetry_value("mission-alpha", "HK.counter")
    assert latest_after_decision.sample_id == conflict.sample_id
    assert latest_after_decision.raw_value == 99
    assert latest_after_decision.provenance["storage"]["validity_state"] == "canonical"

    assert latest_after_decision.provenance["storage"]["decision_reason"] ==
             "operator_selected_conflict_candidate"

    canonical_history =
      Cadence.telemetry_history("mission-alpha", "HK.counter", order: :asc, limit: 10)

    assert Enum.map(canonical_history, & &1.sample_id) == [conflict.sample_id]
    assert hd(canonical_history).provenance["storage"]["validity_state"] == "canonical"

    all_revisions_history =
      Cadence.telemetry_history("mission-alpha", "HK.counter",
        view: :all_revisions,
        order: :asc,
        limit: 10
      )

    assert Enum.map(all_revisions_history, & &1.sample_id) == [
             canonical.sample_id,
             conflict.sample_id
           ]

    assert List.last(all_revisions_history).provenance["storage"]["validity_state"] == "conflict"
  end

  test "operator non-canonical decision removes the affected identity from latest value" do
    canonical =
      sample("sample-decision-latest-remove", 20, ~U[2026-06-21 12:00:03Z],
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    persist_sample_scope!(canonical)
    assert :ok = Storage.persist_samples([canonical], organization_id: "org-test")

    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter").sample_id ==
             canonical.sample_id

    [state] =
      Storage.list_observation_identity_states("mission-alpha",
        organization_id: "org-test",
        point_id: "HK.counter"
      )

    assert {:ok, _state} =
             Storage.apply_observation_identity_decision(
               state.observation_identity_id,
               :mark_conflict,
               organization_id: state.organization_id,
               mission_id: state.mission_id,
               realm: state.realm,
               data_source_id: state.data_source_id,
               binding_id: state.binding_id,
               decision_reason: "operator_quarantined_identity",
               dashboard_runtime_invalidation?: false
             )

    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter") == nil
    assert Cadence.telemetry_history("mission-alpha", "HK.counter", order: :asc, limit: 10) == []
  end

  test "rebuilds the latest-value projection in an async job" do
    binding_set = persist_binding_set_fixture()

    older_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        receipt_time: DateTime.from_unix!(1_700_000_030, :second),
        raw: build_space_packet(42, 3, <<0, 30>>)
      })

    newer_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        receipt_time: DateTime.from_unix!(1_700_000_040, :second),
        raw: build_space_packet(42, 4, <<0, 40>>)
      })

    assert {:ok, _older_result} =
             Cadence.process_and_persist_telemetry_ingress(
               older_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _newer_result} =
             Cadence.process_and_persist_telemetry_ingress(
               newer_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    Repo.delete_all(TelemetryLatestValueRow)

    assert {:ok, rebuild_run} = Cadence.start_rebuild_latest_telemetry_values("mission-alpha")
    assert rebuild_run.status == :running

    assert {:ok, queued_job} =
             Cadence.fetch_latest_telemetry_value_rebuild_job(rebuild_run.rebuild_run_id)

    assert queued_job.status == :queued

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.run_id == rebuild_run.rebuild_run_id

    assert {:ok, rebuild_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert rebuild_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.fetch_latest_telemetry_value_rebuild_run(rebuild_run.rebuild_run_id)

    assert completed_run.rebuilt_value_count == 1
    assert rebuild_job.job_type == :telemetry_latest_value_rebuild
    assert rebuild_job.attempt_count == 1
    assert Cadence.latest_telemetry_value("mission-alpha", "HK.counter").raw_value == 40
  end

  defp persist_binding_set_fixture do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-rebuild",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-projection",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.Governance.persist_binding_set(binding_set)
    binding_set
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end

  defp sample(sample_id, raw_value, receipt_time, opts) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-alpha",
      spacecraft_id: nil,
      point_id: "HK.counter",
      point_name: "HK.counter",
      packet_definition_id: "packet-rebuild",
      packet_definition_version: 1,
      packet_id: "packet-" <> sample_id,
      evidence_id: "evidence-" <> sample_id,
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      receipt_time: receipt_time,
      generation_time: Keyword.get(opts, :generation_time, receipt_time),
      provenance: %{}
    }
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
        source_ref: "test-source",
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
end
