defmodule Cadence.Projections.TelemetryLatestValuesTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.Schemas.TelemetryLatestValueRow
  alias Cadence.Telemetry.PacketDefinition

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

    assert {:ok, ^binding_set} = Cadence.persist_binding_set(binding_set)
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
end
