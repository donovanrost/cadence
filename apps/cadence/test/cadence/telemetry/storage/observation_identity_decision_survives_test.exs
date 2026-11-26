defmodule Cadence.Telemetry.Storage.ObservationIdentityDecisionSurvivesTest do
  @moduledoc """
  #369 (lead's ruling: a revision never clears an operator's decision; domain's scope). Once an
  operator decides an observation identity, a later sighting of it (a re-sighting, then a canonical
  revision) updates only the counts, `latest_*` and the seen times. Every field the decision owns
  stays: the canonical columns, `validity_state`, `decision_reason`, `decided_at` and the
  payload's `"decision"` that `EffectiveSelection` reads. So selection keeps following the
  decision, and the columns keep agreeing with `decision_event_id`. One test per decision kind.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Telemetry.{EffectiveSelection, Sample}
  alias Cadence.Telemetry.Storage
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, ObservationIdentityStates, WriteContext}

  @mission "mission-369"
  @context [
    organization_id: "org-369",
    realm: :flight,
    data_source_id: "ds-primary",
    binding_id: "binding-v1"
  ]

  # The fields an operator's decision owns (domain's list on #369).
  @decision_owned [
    :decision_event_id,
    :validity_state,
    :canonical_observation_id,
    :canonical_sample_id,
    :canonical_revision,
    :decision_reason,
    :decided_at,
    :payload
  ]

  for kind <- [:mark_canonical, :mark_conflict, :mark_superseded, :mark_advisory] do
    test "#{kind}: a re-sighting and then a revision keep the decision; selection still follows it" do
      kind = unquote(kind)
      tag = Atom.to_string(kind)

      initial = envelope("#{tag}-r1")
      conflict = envelope("#{tag}-conflict", validity_state: :conflict, raw_value: 9)
      assert :ok = ObservationIdentityStates.record_envelopes([initial, conflict])

      extra =
        if kind == :mark_canonical,
          do: [
            canonical_observation_id: conflict.observation_id,
            canonical_sample_id: conflict.sample_id,
            canonical_revision: conflict.revision
          ],
          else: []

      decided = decide!(initial, kind, extra)
      owned = Map.take(decided, @decision_owned)
      assert owned.payload["decision"]["decision"] == tag

      # A re-sighting of the same identity (a different observation of it).
      resight = envelope("#{tag}-resight", validity_state: :duplicate)
      assert :ok = ObservationIdentityStates.record_envelopes([resight])
      after_resight = fetch!(initial)
      assert Map.take(after_resight, @decision_owned) == owned
      assert after_resight.duplicate_count == decided.duplicate_count + 1
      assert after_resight.latest_observation_id == resight.observation_id

      # A canonical revision of it: it never clears or moves the decision.
      revision =
        envelope("#{tag}-r2",
          revision: 2,
          raw_value: 7,
          supersedes_observation_id: initial.observation_id
        )

      assert :ok = ObservationIdentityStates.record_envelopes([revision])
      after_revision = fetch!(initial)
      assert Map.take(after_revision, @decision_owned) == owned
      assert after_revision.latest_revision == 2
      assert after_revision.latest_observation_id == revision.observation_id
      assert after_revision.canonical_count == decided.canonical_count + 1

      # U106: a newer revision than the decided canonical one has arrived, for the operator to see.
      if is_integer(owned.canonical_revision),
        do: assert(after_revision.latest_revision > owned.canonical_revision)

      assert_selection(kind, [initial, conflict, resight, revision], after_revision, conflict)
    end
  end

  # An exclusion keeps the identity out of canonical reads; a promote keeps the operator's choice,
  # never the newer revision.
  defp assert_selection(:mark_canonical, envelopes, state, chosen) do
    [selected] = selected(envelopes, state)
    assert selected.provenance["storage"]["observation_id"] == chosen.observation_id
  end

  defp assert_selection(_exclusion, envelopes, state, _chosen),
    do: assert(selected(envelopes, state) == [])

  defp selected(envelopes, state),
    do:
      envelopes
      |> Enum.map(&ObservationEnvelope.to_sample/1)
      |> EffectiveSelection.selected_samples([state], [])

  defp fetch!(envelope) do
    assert {:ok, state} = ObservationIdentityStates.fetch(envelope.observation_identity_id)
    state
  end

  defp decide!(envelope, decision, extra) do
    assert {:ok, state} =
             Storage.apply_observation_identity_decision(
               envelope.observation_identity_id,
               decision,
               [
                 organization_id: envelope.organization_id,
                 mission_id: envelope.mission_id,
                 realm: envelope.realm,
                 data_source_id: envelope.data_source_id,
                 binding_id: envelope.binding_id,
                 decision_reason: "operator_#{decision}",
                 decided_at: ~U[2026-06-22 12:10:00Z],
                 operator_id: "ops-1",
                 point_id: envelope.point_id,
                 sample_id: envelope.sample_id,
                 observed_at: envelope.generation_time || envelope.receipt_time,
                 fetch_sample_fun: fn _query, _opts ->
                   {:ok, ObservationEnvelope.to_sample(envelope)}
                 end
               ] ++ extra
             )

    state
  end

  # Every envelope here is the same identity: one point, one spacecraft, one generation time.
  defp envelope(sample_id, overrides \\ []) do
    {:ok, context} =
      WriteContext.new(
        @context ++
          [
            mission_id: @mission,
            source_endpoint_id: "station-a",
            recorded_at: ~U[2026-06-22 12:00:00Z],
            metadata: %{}
          ]
      )

    raw_value = Keyword.get(overrides, :raw_value, 1)

    sample = %Sample{
      sample_id: sample_id,
      mission_id: @mission,
      spacecraft_id: "sc-1",
      point_id: "HK.mode",
      point_name: "HK.mode",
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-" <> sample_id,
      evidence_id: "evidence-" <> sample_id,
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      generation_time: ~U[2026-06-22 11:05:00Z],
      receipt_time: ~U[2026-06-22 12:00:00Z],
      provenance: %{}
    }

    {:ok, envelope} =
      ObservationEnvelope.from_sample(context, sample,
        validity_state: Keyword.get(overrides, :validity_state, :canonical),
        revision: Keyword.get(overrides, :revision, 1),
        supersedes_observation_id: Keyword.get(overrides, :supersedes_observation_id)
      )

    envelope
  end
end
