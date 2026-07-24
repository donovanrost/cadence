defmodule Cadence.Projections.TelemetryLatestLimitStatesTest do
  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.DerivedTelemetry, as: DerivedTelemetryService
  alias Cadence.Jobs
  alias Cadence.Projections.TelemetryLatestLimitStates
  alias Cadence.Reads.Limits, as: LimitReads
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.DerivedTelemetry.Definition, as: DerivedTelemetryDefinition
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition
  alias Cadence.Limits.Store.LatestStateRow, as: TelemetryLatestLimitStateRow
  alias Cadence.Limits.Store.LimitEventRow, as: TelemetryLimitEventRow
  alias Cadence.Telemetry.PacketDefinition

  test "rebuilds the latest limit-state projection in an async job" do
    binding_set = persist_binding_set_fixture()

    limit_definition =
      Definition.new(%{
        mission_id: "mission-alpha",
        limit_definition_id: "counter-limits",
        point_id: "HK.counter",
        thresholds: %{"yellow_high" => 10, "red_high" => 20}
      })

    assert {:ok, ^limit_definition} = Cadence.Limits.persist_limit_definition(limit_definition)

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(1, 5, 1_700_000_300),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(2, 15, 1_700_000_310),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, limit_run} = Cadence.Limits.evaluate("mission-alpha")
    assert limit_run.status == :completed

    assert LimitReads.latest_state("mission-alpha", "HK.counter").limit_state ==
             :yellow_high

    Repo.delete_all(TelemetryLatestLimitStateRow)
    assert LimitReads.latest_state("mission-alpha", "HK.counter") == nil

    assert {:ok, rebuild_run} =
             TelemetryLatestLimitStates.start_rebuild("mission-alpha")

    assert rebuild_run.status == :running

    assert {:ok, queued_job} =
             Jobs.fetch_job_for_run(
               :telemetry_latest_limit_state_rebuild,
               rebuild_run.rebuild_run_id
             )

    assert queued_job.status == :queued

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.run_id == rebuild_run.rebuild_run_id

    assert {:ok, completed_job} = JobRunner.run_job(claimed_job.job_id)
    assert completed_job.status == :completed
    assert completed_job.job_type == :telemetry_latest_limit_state_rebuild
    assert completed_job.attempt_count == 1

    assert {:ok, completed_run} =
             TelemetryLatestLimitStates.fetch_run(rebuild_run.rebuild_run_id)

    assert completed_run.status == :completed
    assert completed_run.rebuilt_state_count == 1

    latest_state = LimitReads.latest_state("mission-alpha", "HK.counter")
    assert latest_state.limit_state == :yellow_high
    assert latest_state.normalized_state == :yellow
    assert latest_state.evaluated_value == 15
  end

  test "refreshes latest limit states from telemetry and derived latest-value projections without writing canonical limit events" do
    binding_set = persist_binding_set_fixture()

    derived_definition =
      DerivedTelemetryDefinition.new(%{
        mission_id: "mission-alpha",
        derived_definition_id: "counter-double",
        point_id: "DERIVED.counter_double",
        point_name: "DERIVED.counter_double",
        expression: "HK.counter * 2"
      })

    telemetry_limit_definition =
      Definition.new(%{
        mission_id: "mission-alpha",
        limit_definition_id: "telemetry-counter-limits",
        point_id: "HK.counter",
        thresholds: %{"yellow_high" => 10, "red_high" => 30}
      })

    derived_limit_definition =
      Definition.new(%{
        mission_id: "mission-alpha",
        limit_definition_id: "derived-counter-limits",
        point_id: "DERIVED.counter_double",
        thresholds: %{"yellow_high" => 30, "red_high" => 60}
      })

    assert {:ok, ^derived_definition} =
             Cadence.Governance.persist_derived_definition(derived_definition)

    assert {:ok, ^telemetry_limit_definition} =
             Cadence.Limits.persist_limit_definition(telemetry_limit_definition)

    assert {:ok, ^derived_limit_definition} =
             Cadence.Limits.persist_limit_definition(derived_limit_definition)

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(3, 5, 1_700_000_320),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(4, 20, 1_700_000_330),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, derived_run} = DerivedTelemetryService.evaluate("mission-alpha")
    assert derived_run.status == :completed

    assert Repo.aggregate(TelemetryLimitEventRow, :count, :limit_event_id) == 0
    Repo.delete_all(TelemetryLatestLimitStateRow)

    assert {:ok, refresh_run} =
             TelemetryLatestLimitStates.start_refresh_from_latest_values("mission-alpha")

    assert refresh_run.status == :running

    assert {:ok, queued_job} =
             Jobs.fetch_job_for_run(
               :telemetry_latest_limit_state_refresh,
               refresh_run.rebuild_run_id
             )

    assert queued_job.status == :queued

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.run_id == refresh_run.rebuild_run_id

    assert {:ok, completed_job} = JobRunner.run_job(claimed_job.job_id)
    assert completed_job.status == :completed
    assert completed_job.job_type == :telemetry_latest_limit_state_refresh
    assert completed_job.attempt_count == 1

    assert {:ok, completed_run} =
             TelemetryLatestLimitStates.fetch_run(refresh_run.rebuild_run_id)

    assert completed_run.status == :completed
    assert completed_run.rebuilt_state_count == 2
    assert Repo.aggregate(TelemetryLimitEventRow, :count, :limit_event_id) == 0

    assert LimitReads.latest_state("mission-alpha", "HK.counter").limit_state ==
             :yellow_high

    assert LimitReads.latest_state(
             "mission-alpha",
             "DERIVED.counter_double"
           ).limit_state == :yellow_high

    assert LimitReads.latest_states_for_mission("mission-alpha")
           |> Enum.map(fn state ->
             {state.point_id, state.limit_state, state.provenance["evaluation_mode"]}
           end) == [
             {"DERIVED.counter_double", :yellow_high, "latest_value_projection"},
             {"HK.counter", :yellow_high, "latest_value_projection"}
           ]
  end

  defp persist_binding_set_fixture do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-limit-state-rebuild",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-limit-state-rebuild",
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
