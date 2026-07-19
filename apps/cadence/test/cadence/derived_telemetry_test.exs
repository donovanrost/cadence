defmodule Cadence.DerivedTelemetryTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.DerivedTelemetry.Definition
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.PacketDefinition

  test "evaluates chained governed derived telemetry definitions in topological order" do
    binding_set = persist_binding_set_fixture()

    base_definition =
      Definition.new(%{
        mission_id: "mission-alpha",
        derived_definition_id: "counter-double",
        point_id: "DERIVED.counter_double",
        point_name: "DERIVED.counter_double",
        expression: "HK.counter * 2"
      })

    chained_definition =
      Definition.new(%{
        mission_id: "mission-alpha",
        derived_definition_id: "counter-double-plus-one",
        point_id: "DERIVED.counter_double_plus_one",
        point_name: "DERIVED.counter_double_plus_one",
        expression: "DERIVED.counter_double + 1"
      })

    assert {:ok, ^base_definition} = Cadence.persist_derived_definition(base_definition)
    assert {:ok, ^chained_definition} = Cadence.persist_derived_definition(chained_definition)

    assert ["DERIVED.counter_double + 1", "HK.counter * 2"] =
             Cadence.list_derived_definitions("mission-alpha")
             |> Enum.map(& &1.expression)
             |> Enum.sort()

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(1, 10, 1_700_000_100),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(2, 20, 1_700_000_110),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, run} = Cadence.start_evaluate_derived_telemetry("mission-alpha")
    assert run.status == :running

    assert {:ok, queued_job} = Cadence.fetch_derived_telemetry_job(run.derived_run_id)
    assert queued_job.status == :queued

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.run_id == run.derived_run_id

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed
    assert completed_job.job_type == :derived_telemetry_evaluation
    assert completed_job.attempt_count == 1

    assert {:ok, completed_run} = Cadence.fetch_derived_telemetry_run(run.derived_run_id)
    assert completed_run.status == :completed
    assert completed_run.evaluated_sample_count == 2
    assert completed_run.emitted_sample_count == 4
    assert completed_run.definition_count == 2

    base_history = Cadence.derived_telemetry_history("mission-alpha", "DERIVED.counter_double")
    assert Enum.map(base_history, & &1.value) == [40, 20]

    chained_history =
      Cadence.derived_telemetry_history("mission-alpha", "DERIVED.counter_double_plus_one")

    assert Enum.map(chained_history, & &1.value) == [41, 21]

    latest =
      Cadence.latest_derived_telemetry_value("mission-alpha", "DERIVED.counter_double_plus_one")

    assert latest.value == 41
    assert latest.trigger_sample_id == List.first(chained_history).trigger_sample_id
    assert latest.provenance["source_point_ids"] == ["DERIVED.counter_double"]

    latest_values =
      Cadence.latest_derived_telemetry_values("mission-alpha")
      |> Enum.map(fn sample -> {sample.point_id, sample.value} end)

    assert latest_values == [
             {"DERIVED.counter_double", 40},
             {"DERIVED.counter_double_plus_one", 41}
           ]
  end

  defp persist_binding_set_fixture do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-derived",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-derived",
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
