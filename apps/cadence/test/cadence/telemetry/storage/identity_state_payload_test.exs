defmodule Cadence.Telemetry.Storage.IdentityStatePayloadTest do
  @moduledoc """
  #359 (b): an identity state's payload no longer copies fields the row (or the observation)
  already stores. Rows written before (with the seven copies) still read, re-deliver and take a
  decision exactly as before: no reader takes those fields from the payload.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, ObservationIdentityStates, WriteContext}
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow

  # What every state's payload held before #359: three copies of this row's columns and four of
  # the observation's.
  @old_payload_keys ~w(latest_observation_id latest_sample_id latest_validity_state
                       supersedes_observation_id source_endpoint_id evidence_id packet_id)

  test "a new state's payload carries no copies" do
    envelope = envelope("sample-new", 1)
    :ok = record(envelope)

    assert row(envelope).payload == %{}

    assert {:ok, %{payload: %{}}} =
             ObservationIdentityStates.fetch(envelope.observation_identity_id)
  end

  test "a revision rewrites an old-shape payload without the copies" do
    first = envelope("sample-rev-1", 1)
    :ok = record(first)
    old_shape!(first)

    :ok = record(envelope("sample-rev-2", 2))

    assert row(first).payload == %{}
    assert row(first).latest_sample_id == "sample-rev-2"
  end

  test "an old-shape row reads, re-delivers and takes a decision as before" do
    envelope = envelope("sample-old", 1)
    :ok = record(envelope)
    {:ok, fresh} = ObservationIdentityStates.fetch(envelope.observation_identity_id)

    old_shape!(envelope)
    {:ok, old} = ObservationIdentityStates.fetch(envelope.observation_identity_id)

    # Every field but the payload reads the same; the copies are only carried along.
    assert Map.delete(old, :payload) == Map.delete(fresh, :payload)
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

  # Rewrites the stored payload the way every row before #359 was written.
  defp old_shape!(envelope) do
    payload = %{
      "latest_observation_id" => envelope.observation_id,
      "latest_sample_id" => envelope.sample_id,
      "latest_validity_state" => "canonical",
      "supersedes_observation_id" => nil,
      "source_endpoint_id" => envelope.source_endpoint_id,
      "evidence_id" => envelope.evidence_id,
      "packet_id" => envelope.packet_id
    }

    {1, _} =
      TelemetryObservationIdentityStateRow
      |> where([s], s.observation_identity_id == ^envelope.observation_identity_id)
      |> Repo.update_all(set: [payload: payload])
  end

  defp envelope(sample_id, revision) do
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
        validity_state: :canonical,
        revision: revision
      )

    envelope
  end
end
