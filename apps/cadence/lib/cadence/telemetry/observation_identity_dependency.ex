defmodule Cadence.Telemetry.ObservationIdentityDependency do
  @moduledoc "Stable dependency token for canonical telemetry observation state."

  alias Cadence.Platform.Fingerprint
  alias Cadence.Telemetry.Storage.ObservationIdentityState

  @spec from_states([ObservationIdentityState.t()]) :: map()
  def from_states(states) when is_list(states) do
    entries =
      states
      |> Enum.map(&entry/1)
      |> Enum.sort_by(& &1.observation_identity_id)

    %{
      kind: :telemetry_observation_identity_state,
      fingerprint:
        "telemetry-revision:" <>
          Fingerprint.canonical_url_sha256(%{
            kind: :telemetry_observation_identity_state,
            entries: entries
          }),
      observation_identity_ids: Enum.map(entries, & &1.observation_identity_id)
    }
  end

  defp entry(%ObservationIdentityState{} = state) do
    %{
      observation_identity_id: state.observation_identity_id,
      validity_state: state.validity_state,
      canonical_observation_id: state.canonical_observation_id,
      canonical_sample_id: state.canonical_sample_id,
      canonical_revision: state.canonical_revision,
      latest_observation_id: state.latest_observation_id,
      latest_sample_id: state.latest_sample_id,
      latest_revision: state.latest_revision,
      canonical_count: state.canonical_count,
      duplicate_count: state.duplicate_count,
      conflict_count: state.conflict_count,
      superseded_count: state.superseded_count,
      advisory_count: state.advisory_count,
      decision_event_id: state.decision_event_id,
      last_seen_at: state.last_seen_at,
      decided_at: state.decided_at,
      decision_reason: state.decision_reason
    }
  end
end
