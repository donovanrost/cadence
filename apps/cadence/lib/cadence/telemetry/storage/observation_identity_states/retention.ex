defmodule Cadence.Telemetry.Storage.ObservationIdentityStates.Retention do
  @moduledoc """
  #359 (a), on the shared retention sweeper (#694): which observation identity states may be deleted
  once they are old, and the chunked delete itself.

  Every stored observation could once get a state row ("seen once, canonical"). That row only
  matters while the same observation could still be re-delivered (a journal replay inside the
  settlement and journal window) or while its observation is still in the observation store.
  After both, a **trivial** state serves nothing: `EffectiveSelection` ignores a state without a
  decision.

  **The cutoff** is the later of two windows before `now`, so a state goes only when both have
  passed: the observation retention (`Cadence.Persistence.Retention.observation_days/0`, the
  window the observation store keeps the observation) and the re-delivery window (the journal's
  retention after settlement plus `identity_state_settlement_allowance_hours`, 24: a pass's
  observations settle within a day).

  A state is deleted ONLY when all of these hold (anything else is kept, forever, by this rule):

    * no decision: `decision_event_id` is null and the payload carries no `"decision"`;
    * seen once, canonical: `decision_reason = 'initial_canonical'`, `canonical_count <= 1`;
    * no duplicate, conflict, superseded or advisory count;
    * not a replay run's state (`replay_run_id` is null);
    * `last_seen_at` is before the cutoff.

  Decision events (`telemetry_observation_identity_decision_events`) are never touched.

  The walk follows the primary key (a keyset, no extra index): each chunk reads the next
  `chunk_rows` states after the cursor and deletes those that match, re-checking every condition
  on the row it deletes in the same statement, so a state decided between the read and the delete
  is kept. It never waits for a quiet moment: a chunk is one short statement, and the walk resumes
  where it stopped and starts over after the end.
  """

  @behaviour Cadence.Persistence.Retention.Rule

  alias Cadence.Persistence.Retention
  alias Cadence.Repo

  @table "telemetry_observation_identity_states"

  @typedoc "A walk position: the last primary key read, or `\"\"` to start from the beginning."
  @type cursor :: binary()

  @impl true
  def name, do: :identity_states

  @impl true
  def enabled?(_settings), do: true

  @impl true
  def initial_cursor, do: ""

  @impl true
  def interval_ms(settings), do: Keyword.fetch!(settings, :identity_state_interval_ms)

  @doc "The instant a state must be last seen before to go: the earlier of the two windows."
  @spec cutoff(DateTime.t(), keyword()) :: DateTime.t()
  def cutoff(%DateTime{} = now, settings \\ Retention.settings()) do
    store_ms = Retention.observation_days() * 86_400_000

    redelivery_ms =
      Retention.journal_retention_ms() +
        settings[:identity_state_settlement_allowance_hours] * 3_600_000

    # Whole seconds; rounding down only makes the cutoff earlier (keeps more).
    now |> DateTime.add(-max(store_ms, redelivery_ms), :millisecond) |> DateTime.truncate(:second)
  end

  @impl true
  def sweep_chunk(cursor, %DateTime{} = now, settings) do
    size = Keyword.fetch!(settings, :chunk_rows)

    %{rows: [[scanned, deleted, last]]} =
      Repo.query!(statement(), [cursor, size, naive(cutoff(now, settings))])

    {if(scanned < size, do: :done, else: :more), deleted, last || cursor, fn -> :ok end}
  end

  defp statement do
    """
    WITH scanned AS (#{scan()}),
    gone AS (
      DELETE FROM #{@table} p USING scanned d
      WHERE d.doomed AND p.observation_identity_id = d.observation_identity_id
        AND #{trivial("p")}
      RETURNING 1
    )
    SELECT (SELECT count(*) FROM scanned), (SELECT count(*) FROM gone),
           (SELECT max(observation_identity_id) FROM scanned)
    """
  end

  # $1 the cursor, $2 the scan size, $3 the cutoff (UTC, the column has no time zone).
  defp scan do
    """
    SELECT s.observation_identity_id, (#{trivial("s")}) AS doomed
    FROM #{@table} s
    WHERE s.observation_identity_id > $1
    ORDER BY s.observation_identity_id
    LIMIT $2
    """
  end

  defp trivial(row) do
    """
    #{row}.decision_event_id IS NULL
      AND NOT (coalesce(#{row}.payload, '{}'::jsonb) ? 'decision')
      AND #{row}.decision_reason = 'initial_canonical'
      AND #{row}.canonical_count <= 1
      AND #{row}.duplicate_count = 0 AND #{row}.conflict_count = 0
      AND #{row}.superseded_count = 0 AND #{row}.advisory_count = 0
      AND #{row}.replay_run_id IS NULL
      AND #{row}.last_seen_at < $3
    """
  end

  defp naive(%DateTime{} = at), do: at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive()
end
