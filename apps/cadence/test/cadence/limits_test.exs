defmodule Cadence.LimitsTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.DerivedTelemetry.Definition, as: DerivedTelemetryDefinition
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Telemetry.PacketDefinition

  test "evaluates governed telemetry limits over derived telemetry in an async job" do
    binding_set = persist_binding_set_fixture()

    derived_definition =
      DerivedTelemetryDefinition.new(%{
        mission_id: "mission-alpha",
        derived_definition_id: "counter-double",
        point_id: "DERIVED.counter_double",
        point_name: "DERIVED.counter_double",
        expression: "HK.counter * 2"
      })

    limit_definition =
      LimitDefinition.new(%{
        mission_id: "mission-alpha",
        limit_definition_id: "derived-counter-limits",
        point_id: "DERIVED.counter_double",
        limit_set_name: "ops",
        thresholds: %{"yellow_high" => 50, "red_high" => 70}
      })

    assert {:ok, ^derived_definition} = Cadence.persist_derived_definition(derived_definition)
    assert {:ok, ^limit_definition} = Cadence.persist_limit_definition(limit_definition)
    assert [persisted_limit_definition] = Cadence.list_limit_definitions("mission-alpha")
    assert persisted_limit_definition.limit_set_name == "ops"

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(1, 10, 1_700_000_200),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(2, 30, 1_700_000_210),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, derived_run} = Cadence.evaluate_derived_telemetry("mission-alpha")
    assert derived_run.status == :completed

    assert Cadence.latest_derived_telemetry_value("mission-alpha", "DERIVED.counter_double").value ==
             60

    assert {:ok, run} = Cadence.start_evaluate_telemetry_limits("mission-alpha")
    assert run.status == :running

    assert {:ok, queued_job} = Cadence.fetch_telemetry_limit_job(run.limit_run_id)
    assert queued_job.status == :queued

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.run_id == run.limit_run_id

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed
    assert completed_job.job_type == :telemetry_limit_evaluation
    assert completed_job.attempt_count == 1

    assert {:ok, completed_run} = Cadence.fetch_telemetry_limit_run(run.limit_run_id)
    assert completed_run.status == :completed
    assert completed_run.evaluated_sample_count == 4
    assert completed_run.emitted_event_count == 2
    assert completed_run.definition_count == 1

    event_history =
      Cadence.telemetry_limit_event_history("mission-alpha", "DERIVED.counter_double")

    assert Enum.map(event_history, & &1.limit_state) == [:yellow_high, :green]

    latest_state =
      Cadence.latest_telemetry_limit_state("mission-alpha", "DERIVED.counter_double")

    assert latest_state.limit_state == :yellow_high
    assert latest_state.normalized_state == :yellow
    assert latest_state.violation
    assert latest_state.evaluated_value == 60
  end

  defp persist_binding_set_fixture do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-limits",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-limits",
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
