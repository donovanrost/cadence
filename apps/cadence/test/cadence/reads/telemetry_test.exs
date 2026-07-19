defmodule Cadence.Reads.TelemetryTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.Schemas.TelemetrySampleRow
  alias Cadence.Telemetry.PacketDefinition

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-telemetry-reads-#{suffix}"
    mission_id = "mission-telemetry-reads-#{suffix}"

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "reads telemetry history and keeps the latest-value projection on the newest sample", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    binding_set = persist_binding_set_fixture(organization_id, mission_id)

    newer_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        receipt_time: DateTime.from_unix!(1_700_000_100, :second),
        raw: build_space_packet(42, 2, <<0, 20>>)
      })

    older_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        receipt_time: DateTime.from_unix!(1_700_000_050, :second),
        raw: build_space_packet(42, 1, <<0, 10>>)
      })

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               newer_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               older_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    latest_sample = Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter", [])
    assert latest_sample.raw_value == 20
    assert DateTime.compare(latest_sample.receipt_time, newer_evidence.receipt_time) == :eq

    as_of_sample =
      Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter",
        to_receipt_time: older_evidence.receipt_time
      )

    assert as_of_sample.raw_value == 10
    assert DateTime.compare(as_of_sample.receipt_time, older_evidence.receipt_time) == :eq

    history =
      Cadence.telemetry_history(organization_id, mission_id, "HK.counter", order: :asc, limit: 10)

    assert Enum.map(history, & &1.raw_value) == [10, 20]

    latest_values = Cadence.latest_telemetry_values(organization_id, mission_id, [])
    assert Enum.map(latest_values, & &1.point_name) == ["HK.counter"]
    assert hd(latest_values).raw_value == 20
  end

  test "reads replay latest values from replay-scoped history instead of live current values", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    binding_set = persist_binding_set_fixture(organization_id, mission_id)

    [replay_older] =
      persist_ingress_sample(binding_set, 90, 10, ~U[2026-06-17 12:01:00Z])

    [replay_newer] =
      persist_ingress_sample(binding_set, 99, 11, ~U[2026-06-17 12:02:00Z])

    [other_replay] =
      persist_ingress_sample(binding_set, 77, 12, ~U[2026-06-17 12:03:00Z])

    [live_sample] =
      persist_ingress_sample(binding_set, 20, 13, ~U[2026-06-17 12:10:00Z])

    mark_samples_as_replay([replay_older, replay_newer], "replay-run-1")
    mark_samples_as_replay([other_replay], "replay-run-2")

    latest_live = Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter", [])
    assert latest_live.sample_id == live_sample.sample_id
    assert latest_live.raw_value == 20

    latest_replay =
      Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter",
        realm: :replay,
        data_source_id: "managed_questdb_replay",
        source_binding_id: "replay_telemetry",
        replay_run_id: "replay-run-1"
      )

    assert latest_replay.sample_id == replay_newer.sample_id
    assert latest_replay.raw_value == 99
    assert latest_replay.provenance["storage"]["replay_run_id"] == "replay-run-1"

    latest_other_replay =
      Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter",
        realm: :replay,
        data_source_id: "managed_questdb_replay",
        source_binding_id: "replay_telemetry",
        replay_run_id: "replay-run-2"
      )

    assert latest_other_replay.sample_id == other_replay.sample_id
    assert latest_other_replay.raw_value == 77
  end

  defp persist_binding_set_fixture(organization_id, mission_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: mission_id <> "-read-model",
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

    assert {:ok, persisted_binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    assert persisted_binding_set.binding_set_id == binding_set.binding_set_id
    assert persisted_binding_set.organization_id == organization_id
    persisted_binding_set
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

  defp persist_ingress_sample(binding_set, raw_value, sequence_count, receipt_time) do
    evidence =
      RawEvidence.new(%{
        mission_id: binding_set.mission_id,
        receipt_time: receipt_time,
        raw: build_space_packet(42, sequence_count, <<0, raw_value>>)
      })

    assert {:ok, result} =
             Cadence.process_and_persist_telemetry_ingress(
               evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, samples} = Cadence.Persistence.telemetry_samples(result.outputs)
    samples
  end

  defp mark_samples_as_replay(samples, replay_run_id) do
    sample_ids = Enum.map(samples, & &1.sample_id)

    {count, _rows} =
      TelemetrySampleRow
      |> where([row], row.sample_id in ^sample_ids)
      |> Repo.update_all(set: [provenance: replay_provenance(replay_run_id)])

    assert count == length(sample_ids)
  end

  defp replay_provenance(replay_run_id) do
    %{
      "storage" => %{
        "realm" => "replay",
        "data_source_id" => "managed_questdb_replay",
        "binding_id" => "replay_telemetry",
        "replay_run_id" => replay_run_id,
        "validity_state" => "canonical"
      }
    }
  end
end
