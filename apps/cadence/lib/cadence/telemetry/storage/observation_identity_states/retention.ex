defmodule Cadence.Telemetry.Storage.ObservationIdentityStates.Retention do
  @moduledoc """
  #359 (a): which observation identity states may be deleted once they are old, and the batched
  delete itself. `Cadence.Control.IdentityStateRetention` decides when it runs and computes the
  cutoff.

  Every stored observation gets a state row ("seen once, canonical"). That row only matters while
  the same observation could still be re-delivered (a journal replay inside the settlement and
  journal window) or while its observation is still in the observation store. After both, a
  **trivial** state serves nothing: `EffectiveSelection` ignores a state without a decision.

  A state is deleted ONLY when all of these hold (anything else is kept, forever, by this rule):

    * no decision: `decision_event_id` is null and the payload carries no `"decision"`;
    * seen once, canonical: `decision_reason = 'initial_canonical'`, `canonical_count <= 1`;
    * no duplicate, conflict, superseded or advisory count;
    * not a replay run's state (`replay_run_id` is null);
    * `last_seen_at` is before the cutoff.

  Decision events (`telemetry_observation_identity_decision_events`) are never touched.

  The walk follows the primary key (a keyset, no extra index): each batch reads the next
  `scan_size` states after the last id, and deletes those that match, re-checking every condition
  on the row it deletes in the same statement. So a state decided between the read and the delete
  is kept. A dry walk counts instead of deleting.
  """

  alias Cadence.Repo

  @table "telemetry_observation_identity_states"

  @typedoc "A walk position: the last primary key read, or `\"\"` to start from the beginning."
  @type cursor :: binary()

  @typedoc "One batch: rows read, rows that matched (dry) or were deleted (live), the next cursor."
  @type batch :: %{scanned: non_neg_integer(), matched: non_neg_integer(), cursor: cursor()}

  @doc """
  Reads the next `scan_size` states after `cursor` and deletes (`:live`) or counts (`:dry`) the
  trivial ones last seen before `cutoff`. `scanned < scan_size` means the walk reached the end.
  """
  @spec batch(:dry | :live, cursor(), DateTime.t(), pos_integer()) :: batch()
  def batch(mode, cursor, %DateTime{} = cutoff, scan_size)
      when mode in [:dry, :live] and is_binary(cursor) and is_integer(scan_size) and
             scan_size > 0 do
    %{rows: [[scanned, matched, last]]} =
      Repo.query!(statement(mode), [cursor, scan_size, naive(cutoff)])

    %{scanned: scanned, matched: matched, cursor: last || cursor}
  end

  defp statement(:dry) do
    """
    WITH scanned AS (#{scan()})
    SELECT count(*), count(*) FILTER (WHERE doomed), max(observation_identity_id) FROM scanned
    """
  end

  defp statement(:live) do
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
