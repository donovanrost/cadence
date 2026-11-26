defmodule Cadence.Telemetry.Storage.IdentityStatePayloadTest do
  @moduledoc """
  #359 (b): an identity state's payload no longer copies fields the row (or the observation)
  already stores. Rows written before (with the seven copies) still read, re-deliver and take a
  decision exactly as before: no reader takes those fields from the payload.

  Since the first-seen rule (#157) a canonical first sighting writes no row, so a new row comes
  from a non-canonical sighting or a decision, and the old-shape rows are the ones written before
  (`ObservationIdentityFixtures.pre_first_seen_state!/2`).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, ObservationIdentityStates, WriteContext}
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow
  alias Cadence.TestSupport.ObservationIdentityFixtures

  # What every state's payload held before #359: three copies of this row's columns and four of
  # the observation's.
  @old_payload_keys ~w(latest_observation_id latest_sample_id latest_validity_state
                       supersedes_observation_id source_endpoint_id evidence_id packet_id)

  test "a new state's payload carries no copies" do
    # A non-canonical first sighting writes the identity's row (first-seen, #157).
    envelope = envelope("sample-new", 1, :advisory)
    :ok = record(envelope)

    assert row(envelope).payload == %{}

    assert {:ok, %{payload: %{}}} =
             ObservationIdentityStates.fetch(envelope.observation_identity_id)
  end

  test "a revision rewrites an old-shape payload without the copies" do
    first = envelope("sample-rev-1", 1)
    ObservationIdentityFixtures.pre_first_seen_state!(first)

    :ok = record(envelope("sample-rev-2", 2))

    assert row(first).payload == %{}
    assert row(first).latest_sample_id == "sample-rev-2"
  end

  test "an old-shape row reads, re-delivers and takes a decision as before" do
    envelope = envelope("sample-old", 1)
    ObservationIdentityFixtures.pre_first_seen_state!(envelope)
    {:ok, old} = ObservationIdentityStates.fetch(envelope.observation_identity_id)

    # It reads from its columns; the copies are only carried along.
    assert %{validity_state: :canonical, canonical_sample_id: "sample-old"} = old
    assert old.latest_observation_id == envelope.observation_id
    assert Enum.sort(Map.keys(old.payload)) == Enum.sort(@old_payload_keys)

    # A re-delivery of the same observation is recognised from the columns: nothing changes.
    before = row(envelope)
    :ok = record(envelope)
    assert row(envelope) == before

    # A decision on an old-shape row: selection reads only the payload's "decision".
    {:ok, _decided} =
      ObservationIdentityStates.apply_decision(envelope.observation_identity_id, :mark_advisory,
        organization_id: envelope.organization_id,
        mission_id: envelope.mission_id,
        decision_reason: "operator_review",
        refresh_latest_value?: false,
        publish_facts?: false
      )

    [selected] = ObservationIdentityStates.list_for_selection(envelope.mission_id)
    assert selected.payload["decision"]["decision"] == "mark_advisory"
    assert selected.validity_state == :advisory
  end

  defp record(envelope),
    do: ObservationIdentityStates.record_envelopes([envelope], publish_facts?: false)

  defp row(envelope),
    do: Repo.get!(TelemetryObservationIdentityStateRow, envelope.observation_identity_id)

  defp envelope(sample_id, revision, validity_state \\ :canonical) do
    {:ok, context} =
      WriteContext.new(
        organization_id: "org-payload",
        mission_id: "mission-payload",
        realm: :flight,
        data_source_id: "ds-primary",
        binding_id: "binding-v1",
        source_endpoint_id: "station-a",
        recorded_at: ~U[2026-11-19 12:00:00Z],
        metadata: %{}
      )

    sample = %Sample{
      sample_id: sample_id,
      mission_id: "mission-payload",
      spacecraft_id: "sc-1",
      point_id: "HK.counter",
      point_name: "HK.counter",
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-" <> sample_id,
      evidence_id: "evidence-" <> sample_id,
      raw_value: revision,
      engineering_value: revision,
      quality_state: :good,
      generation_time: ~U[2026-11-19 11:59:59Z],
      receipt_time: ~U[2026-11-19 12:00:00Z],
      provenance: %{}
    }

    {:ok, envelope} =
      ObservationEnvelope.from_sample(context, sample,
        validity_state: validity_state,
        revision: revision
      )

    envelope
  end
end
