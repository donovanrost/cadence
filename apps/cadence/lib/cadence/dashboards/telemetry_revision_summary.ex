defmodule Cadence.Dashboards.TelemetryRevisionSummary do
  @moduledoc """
  Dashboard-facing summary of telemetry observation identity revision state.

  The storage read model owns which observation is canonical. Dashboard sources
  use this summary to carry identity-level revision facts into frames without
  making widgets interpret projection rows.
  """

  alias Cadence.Dashboards.DataLinks
  alias Cadence.Telemetry.ObservationIdentityDependency
  alias Cadence.Telemetry.Storage.ObservationIdentityState

  @validity_states [:canonical, :duplicate, :conflict, :superseded, :advisory]

  @type t :: %{
          identity_count: non_neg_integer(),
          validity_counts: map(),
          canonical_count: non_neg_integer(),
          duplicate_count: non_neg_integer(),
          conflict_count: non_neg_integer(),
          superseded_count: non_neg_integer(),
          advisory_count: non_neg_integer(),
          has_conflicts?: boolean(),
          has_duplicates?: boolean(),
          has_superseded?: boolean(),
          has_advisory?: boolean(),
          dependency: map(),
          dependency_fingerprint: binary(),
          evidence: [Cadence.Dashboards.EvidenceRef.t()],
          warning_codes: [atom()]
        }

  @spec from_identity_states([ObservationIdentityState.t()]) :: t()
  def from_identity_states(states) when is_list(states) do
    counts = Enum.frequencies_by(states, & &1.validity_state)
    dependency = dependency(states)

    summary = %{
      identity_count: length(states),
      validity_counts: Map.take(counts, @validity_states),
      canonical_count: sum_counts(states, :canonical_count),
      duplicate_count: sum_counts(states, :duplicate_count),
      conflict_count: sum_counts(states, :conflict_count),
      superseded_count: sum_counts(states, :superseded_count),
      advisory_count: sum_counts(states, :advisory_count),
      dependency: dependency,
      dependency_fingerprint: dependency.fingerprint,
      evidence: revision_decision_evidence(states)
    }

    summary
    |> Map.put(:has_conflicts?, summary.conflict_count > 0 or Map.get(counts, :conflict, 0) > 0)
    |> Map.put(
      :has_duplicates?,
      summary.duplicate_count > 0 or Map.get(counts, :duplicate, 0) > 0
    )
    |> Map.put(
      :has_superseded?,
      summary.superseded_count > 0 or Map.get(counts, :superseded, 0) > 0
    )
    |> Map.put(:has_advisory?, summary.advisory_count > 0 or Map.get(counts, :advisory, 0) > 0)
    |> then(&Map.put(&1, :warning_codes, warning_codes(&1)))
  end

  defp warning_codes(summary) do
    [
      summary.has_conflicts? && :conflicting_observations,
      summary.has_superseded? && :corrected_range,
      summary.has_advisory? && :advisory_backfill,
      mixed_revisions?(summary) && :mixed_revisions
    ]
    |> Enum.reject(&(&1 in [nil, false]))
  end

  defp dependency(states) do
    ObservationIdentityDependency.from_states(states)
  end

  defp revision_decision_evidence(states) do
    states
    |> Enum.map(fn %ObservationIdentityState{} = state ->
      %{
        decision_event_id: state.decision_event_id,
        decided_at: state.decided_at
      }
    end)
    |> DataLinks.telemetry_revision_decision_event_evidence_refs()
  end

  defp mixed_revisions?(summary) do
    summary.has_conflicts? or summary.has_duplicates? or summary.has_superseded? or
      summary.has_advisory?
  end

  defp sum_counts(states, field) do
    Enum.reduce(states, 0, fn %ObservationIdentityState{} = state, total ->
      total + Map.fetch!(state, field)
    end)
  end
end
