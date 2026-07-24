defmodule Cadence.Runtime.ReplaySessionTest do
  use ExUnit.Case, async: true

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.{MissionRuntimeSpec, ReplaySession}

  test "processes a bounded replay without management, control, projections, or Repo" do
    assert Process.whereis(Cadence.Management.Supervisor) == nil
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Projections.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil

    mission_id = "isolated-replay-#{System.unique_integer([:positive])}"

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "empty-replay-basis",
        version: 1
      })

    assert {:ok, runtime_spec} =
             MissionRuntimeSpec.new(%{
               activation_id: "isolated-replay-activation",
               mission_id: mission_id,
               generation: 1,
               binding_set_id: binding_set.binding_set_id,
               binding_set_version: binding_set.version,
               binding_set: binding_set,
               activated_at: ~U[2026-07-23 12:00:00Z],
               metadata: %{"replay" => true}
             })

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "isolated/replay",
        receipt_time: ~U[2026-07-23 12:00:01Z],
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    assert {:ok, result} = ReplaySession.process([raw_evidence], runtime_spec)
    assert [%{raw_evidence: ^raw_evidence, packet_records: [_packet]}] = result.processing_results

    assert result.runtime_records == %{
             capability_records: [],
             action_requests: [],
             timer_events: []
           }

    assert Process.whereis(Cadence.Management.Supervisor) == nil
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Projections.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil
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
