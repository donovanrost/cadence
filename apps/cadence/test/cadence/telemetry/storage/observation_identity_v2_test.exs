defmodule Cadence.Telemetry.Storage.ObservationIdentityV2Test do
  @moduledoc """
  Identity v2 against the identity-state projection (docs/apogee/plans/ingress-time-tags.md).
  On 11-14 00:38:36–00:40:40Z eight frames per point shared one receipt-fallback timestamp and
  collapsed into one identity (8064 observations, 1008 identities).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, ObservationIdentityStates, WriteContext}

  @mission "mission-identity-v2"
  @shared_time ~U[2026-11-14 00:38:40.869209Z]

  test "eight packets sharing one receipt-fallback timestamp keep eight identities" do
    envelopes =
      for count <- 100..107 do
        envelope("sample-#{count}", generation_time: @shared_time, frame_ref: {:seq, 42, count})
      end

    assert :ok = ObservationIdentityStates.record_envelopes(envelopes, publish_facts?: false)

    states = ObservationIdentityStates.list_for_selection(@mission)
    assert length(states) == 8
    assert Enum.all?(states, &(&1.canonical_count == 1))

    assert states |> Enum.map(& &1.canonical_sample_id) |> Enum.sort() ==
             for(count <- 100..107, do: "sample-#{count}")
  end

  test "the same frame replayed from the journal stays one identity, at revision 2" do
    ref = {:pos, "journal-stream-1", 14}
    first = envelope("sample-live", frame_ref: ref, generation_time_source: :receipt)

    replayed =
      envelope("sample-replayed",
        frame_ref: ref,
        generation_time_source: :receipt,
        revision: 2,
        supersedes_observation_id: first.observation_id
      )

    assert first.observation_identity_id == replayed.observation_identity_id
    assert :ok = ObservationIdentityStates.record_envelopes([first], publish_facts?: false)
    assert :ok = ObservationIdentityStates.record_envelopes([replayed], publish_facts?: false)

    assert [state] = ObservationIdentityStates.list_for_selection(@mission)
    assert state.latest_revision == 2
    assert state.latest_observation_id == replayed.observation_id
  end

  defp envelope(sample_id, overrides) do
    {:ok, context} =
      WriteContext.new(
        organization_id: "org-identity-v2",
        mission_id: @mission,
        realm: :flight,
        data_source_id: "ds-primary",
        binding_id: "binding-v2",
        source_endpoint_id: "station-a",
        recorded_at: ~U[2026-11-14 00:38:41Z],
        metadata: %{}
      )

    sample = %Sample{
      sample_id: sample_id,
      mission_id: @mission,
      spacecraft_id: "spacecraft-earendil-001",
      point_id: "HK.sc_mode",
      point_name: "HK.sc_mode",
      packet_definition_id: "packet-def-hk",
      packet_definition_version: 1,
      packet_id: "packet-" <> sample_id,
      evidence_id: "evidence-" <> sample_id,
      raw_value: 4,
      engineering_value: 4,
      quality_state: :good,
      generation_time: Keyword.get(overrides, :generation_time, @shared_time),
      receipt_time: Keyword.get(overrides, :generation_time, @shared_time),
      generation_time_source: Keyword.get(overrides, :generation_time_source, :receipt),
      frame_ref: Keyword.fetch!(overrides, :frame_ref),
      provenance: %{}
    }

    {:ok, envelope} =
      ObservationEnvelope.from_sample(context, sample,
        revision: Keyword.get(overrides, :revision, 1),
        supersedes_observation_id: Keyword.get(overrides, :supersedes_observation_id)
      )

    envelope
  end
end
