defmodule Cadence.Projections.DerivedTelemetryLatestValuesTest do
  alias Cadence.DerivedTelemetry, as: DerivedTelemetryService
  alias Cadence.Jobs
  alias Cadence.Projections.DerivedTelemetryLatestValues
  alias Cadence.Reads.DerivedTelemetry, as: DerivedTelemetryReads
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.DerivedTelemetry.Definition
  alias Cadence.DerivedTelemetry.Store.LatestValueRow, as: DerivedTelemetryLatestValueRow
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.PacketDefinition

  test "rebuilds the latest derived telemetry value projection in an async job" do
    binding_set = persist_binding_set_fixture()

    definition =
      Definition.new(%{
        mission_id: "mission-alpha",
        derived_definition_id: "counter-double",
        point_id: "DERIVED.counter_double",
        point_name: "DERIVED.counter_double",
        expression: "HK.counter * 2"
      })

    assert {:ok, ^definition} = Cadence.Governance.persist_derived_definition(definition)

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(1, 10, 1_700_000_400),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(2, 25, 1_700_000_410),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, derived_run} = DerivedTelemetryService.evaluate("mission-alpha")
    assert derived_run.status == :completed

    assert DerivedTelemetryReads.latest_value("mission-alpha", "DERIVED.counter_double").value ==
             50

    Repo.delete_all(DerivedTelemetryLatestValueRow)

    assert DerivedTelemetryReads.latest_value("mission-alpha", "DERIVED.counter_double") ==
             nil

    assert DerivedTelemetryReads.latest_values_for_mission("mission-alpha") == []

    assert {:ok, rebuild_run} =
             DerivedTelemetryLatestValues.start_rebuild("mission-alpha")

    assert rebuild_run.status == :running

    assert {:ok, queued_job} =
             Jobs.fetch_job_for_run(
               :derived_telemetry_latest_value_rebuild,
               rebuild_run.rebuild_run_id
             )

    assert queued_job.status == :queued

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.run_id == rebuild_run.rebuild_run_id

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed
    assert completed_job.job_type == :derived_telemetry_latest_value_rebuild
    assert completed_job.attempt_count == 1

    assert {:ok, completed_run} =
             DerivedTelemetryLatestValues.fetch_run(rebuild_run.rebuild_run_id)

    assert completed_run.status == :completed
    assert completed_run.rebuilt_value_count == 1

    assert DerivedTelemetryReads.latest_value("mission-alpha", "DERIVED.counter_double").value ==
             50

    assert DerivedTelemetryReads.latest_values_for_mission("mission-alpha")
           |> Enum.map(fn sample -> {sample.point_id, sample.value} end) == [
             {"DERIVED.counter_double", 50}
           ]
  end

  defp persist_binding_set_fixture do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-derived-latest-rebuild",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-derived-latest-rebuild",
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

  defp raw_evidence_fixture(sequence_count, counter_value, receipt_unix) do
    RawEvidence.new(%{
      mission_id: "mission-alpha",
      receipt_time: DateTime.from_unix!(receipt_unix, :second),
      raw: build_space_packet(42, sequence_count, <<counter_value::16>>)
    })
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
