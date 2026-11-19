defmodule Cadence.TestSupport.ObservationIdentityFixtures do
  @moduledoc """
  Observation envelopes, their stored samples and decision options for identity-state tests
  (the first-seen rule, 11-17).
  """

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow

  @doc "An envelope as the storage path builds it. Overrides: any context or sample field."
  @spec envelope(keyword()) :: ObservationEnvelope.t()
  def envelope(overrides) do
    mission_id = Keyword.get(overrides, :mission_id, "mission-first-seen")
    sample_id = Keyword.fetch!(overrides, :sample_id)
    raw_value = Keyword.get(overrides, :raw_value, 42)

    {:ok, context} =
      WriteContext.new(
        organization_id: Keyword.get(overrides, :organization_id, "org-first-seen"),
        mission_id: mission_id,
        realm: Keyword.get(overrides, :realm, :flight),
        replay_run_id: Keyword.get(overrides, :replay_run_id),
        data_source_id: Keyword.get(overrides, :data_source_id, "ds-primary"),
        binding_id: Keyword.get(overrides, :binding_id, "binding-v1"),
        source_endpoint_id: Keyword.get(overrides, :source_endpoint_id, "station-a"),
        recorded_at: Keyword.get(overrides, :recorded_at, ~U[2026-11-17 06:00:00.000000Z]),
        metadata: %{}
      )

    sample = %Sample{
      sample_id: sample_id,
      mission_id: mission_id,
      spacecraft_id: Keyword.get(overrides, :spacecraft_id, "sc-1"),
      point_id: Keyword.get(overrides, :point_id, "HK.counter"),
      point_name: Keyword.get(overrides, :point_id, "HK.counter"),
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-" <> sample_id,
      evidence_id: "evidence-" <> sample_id,
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      generation_time: Keyword.get(overrides, :generation_time, ~U[2026-11-17 05:59:59.250000Z]),
      receipt_time: ~U[2026-11-17 06:00:00.000000Z],
      provenance: %{}
    }

    {:ok, envelope} =
      ObservationEnvelope.from_sample(context, sample,
        validity_state: Keyword.get(overrides, :validity_state, :canonical),
        revision: Keyword.get(overrides, :revision, 1)
      )

    envelope
  end

  @doc """
  The row the write path stored for a canonical first sighting BEFORE the first-seen rule (#157):
  "seen once, canonical", with the old payload's six copies. Dev still holds such rows, and #359's
  retention deletes them; nothing writes them any more. Overrides: any row field (atom keys), e.g.
  `last_seen_at`, a count, `decision_reason` or `payload`.
  """
  @spec pre_first_seen_state!(ObservationEnvelope.t(), keyword()) :: struct()
  def pre_first_seen_state!(%ObservationEnvelope{} = envelope, overrides \\ []) do
    attrs =
      Map.merge(
        %{
          observation_identity_id: envelope.observation_identity_id,
          organization_id: envelope.organization_id,
          mission_id: envelope.mission_id,
          realm: Atom.to_string(envelope.realm),
          replay_run_id: envelope.replay_run_id,
          data_source_id: envelope.data_source_id,
          binding_id: envelope.binding_id,
          observable_id: envelope.observable_id,
          point_id: envelope.point_id,
          spacecraft_id: envelope.spacecraft_id,
          canonical_observation_id: envelope.observation_id,
          canonical_sample_id: envelope.sample_id,
          canonical_revision: envelope.revision,
          latest_observation_id: envelope.observation_id,
          latest_sample_id: envelope.sample_id,
          latest_revision: envelope.revision,
          validity_state: "canonical",
          canonical_count: 1,
          duplicate_count: 0,
          conflict_count: 0,
          superseded_count: 0,
          advisory_count: 0,
          first_seen_at: envelope.ingested_at,
          last_seen_at: envelope.ingested_at,
          decided_at: envelope.ingested_at,
          decision_reason: "initial_canonical",
          payload: %{
            "latest_observation_id" => envelope.observation_id,
            "latest_sample_id" => envelope.sample_id,
            "latest_validity_state" => "canonical",
            "supersedes_observation_id" => envelope.supersedes_observation_id,
            "source_endpoint_id" => envelope.source_endpoint_id,
            "evidence_id" => envelope.evidence_id,
            "packet_id" => envelope.packet_id
          }
        },
        Map.new(overrides)
      )

    %TelemetryObservationIdentityStateRow{}
    |> TelemetryObservationIdentityStateRow.changeset(attrs)
    |> Cadence.Repo.insert!()
  end

  @doc "The sample a history backend returns for the envelope's row (with its storage provenance)."
  @spec stored_sample(ObservationEnvelope.t()) :: Sample.t()
  def stored_sample(%ObservationEnvelope{} = envelope),
    do: ObservationEnvelope.to_sample(envelope)

  @doc """
  A `fetch_sample_fun` that returns `result` and reports each query to `test_pid` as
  `{:fetch_sample, query, in_transaction?}`.
  """
  @spec fetch_sample_fun(pid(), term()) :: (term(), keyword() -> term())
  def fetch_sample_fun(test_pid, result) do
    fn query, _opts ->
      send(test_pid, {:fetch_sample, query, Cadence.Repo.in_transaction?()})
      result
    end
  end

  @doc "Decision options naming the envelope's scope and observation, as a client sends them."
  @spec decision_opts(ObservationEnvelope.t(), keyword()) :: keyword()
  def decision_opts(%ObservationEnvelope{} = envelope, extra \\ []) do
    Keyword.merge(
      [
        organization_id: envelope.organization_id,
        mission_id: envelope.mission_id,
        realm: envelope.realm,
        data_source_id: envelope.data_source_id,
        binding_id: envelope.binding_id,
        point_id: envelope.point_id,
        sample_id: envelope.sample_id,
        observed_at: envelope.generation_time || envelope.receipt_time,
        decision_reason: "operator_review",
        refresh_latest_value?: false,
        publish_facts?: false
      ],
      extra
    )
  end
end
