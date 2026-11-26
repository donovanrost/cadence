defmodule Cadence.SemanticObservations.FleetAlarms do
  @moduledoc """
  The live monitoring side of the fleet's condition (#871): per spacecraft, its ACTIVE catalog
  monitoring alarms from `semantic_latest_alarm_states`, which the runtime writes on every
  transition. Ground limits (`Limits.Store.FleetSummary`) are the batch side; `Reads.FleetStatus`
  takes the worst of the two.

  Severity is the mapping the alarm episodes use (`Alarms.Sources`): `watch` and `warning` are
  caution; `distress`, `critical` and `severe` are critical. `normal` is not active, and `unknown`
  and `disabled` change nothing, so none of them counts.

  **Kept by the writer, in its transaction.** `semantic_fleet_alarm_summaries` has one row per
  spacecraft with an active alarm: its worst alarm (most severe, then newest), how many are active,
  and the newest receipt among them. `refresh/3` recomputes the rows of the spacecraft a batch
  transitioned from their active alarms (the partial index `semantic_latest_alarm_states_active_idx`
  serves it) and removes the row of one left with none; `SemanticObservations.persist_many/1` calls
  it once per spacecraft, inside the transaction that upserts the latest states, and only for a batch
  that has transitions. `load/2` is ONE statement over the summaries however many spacecraft or
  parameters there are. Reading the aggregate on every fleet read cost what the active alarms do
  (58 ms p99 with 3% of 200,000 rows active, 800 ms in a mass event).
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.SemanticObservations.{FleetAlarmSummaryRow, LatestAlarmStateRow}

  @type alarm :: %{
          limit_state: :critical | :caution,
          active: pos_integer(),
          last_received_at: DateTime.t(),
          worst: %{
            parameter_id: binary(),
            policy_id: binary(),
            effective_state: binary(),
            receipt_time: DateTime.t()
          }
        }

  # The severity rank of a live state: critical 2, caution 1.
  @rank "(CASE WHEN effective_state IN ('distress', 'critical', 'severe') THEN 2 ELSE 1 END)"
  @active "effective_state IN ('watch', 'warning', 'distress', 'critical', 'severe')"

  @spec load(binary(), binary()) :: %{binary() => alarm()}
  def load(organization_id, mission_id) do
    from(s in FleetAlarmSummaryRow,
      join: l in LatestAlarmStateRow,
      on: l.id == s.worst_state_id,
      where: s.organization_id == ^organization_id and s.mission_id == ^mission_id,
      select: {s, l}
    )
    |> Repo.all()
    |> Map.new(fn {summary, worst} ->
      {summary.spacecraft_id,
       %{
         limit_state: if(summary.worst_rank == 2, do: :critical, else: :caution),
         active: summary.active,
         last_received_at: summary.last_received_at,
         worst: %{
           parameter_id: worst.parameter_id,
           policy_id: worst.policy_id,
           effective_state: worst.effective_state,
           receipt_time: worst.receipt_time
         }
       }}
    end)
  end

  # One writer per spacecraft at a time (#871): two transactions that transition the same spacecraft
  # (two partitions after a handover, a replay beside the live owner) would each recompute from a
  # snapshot that lacks the other's uncommitted rows, and the later commit could leave a stale
  # summary. A transaction-scoped advisory lock per (mission, spacecraft), taken in sorted order
  # (no deadlock between batches) before the recompute, makes the second wait for the first's
  # commit; its recompute statement then reads the first's rows (READ COMMITTED takes a snapshot
  # per statement). Held until commit, so it also covers the latest-state upserts before it.
  defp lock_spacecraft(repo, mission_id, spacecraft_ids) do
    Enum.each(spacecraft_ids, fn id ->
      repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        mission_id <> "/" <> id
      ])
    end)
  end

  @doc """
  Recomputes the summaries of `spacecraft_ids` of a mission from their active alarms, inside the
  caller's transaction.
  """
  @spec refresh(module(), binary(), binary(), [binary()]) :: :ok
  def refresh(_repo, _organization_id, _mission_id, []), do: :ok

  def refresh(repo, organization_id, mission_id, spacecraft_ids) do
    spacecraft_ids = Enum.sort(spacecraft_ids)
    lock_spacecraft(repo, mission_id, spacecraft_ids)
    params = [organization_id, mission_id, spacecraft_ids]

    repo.query!(
      """
      DELETE FROM semantic_fleet_alarm_summaries s
      WHERE s.organization_id = $1 AND s.mission_id = $2 AND s.spacecraft_id = ANY($3)
        AND NOT EXISTS (
          SELECT 1 FROM semantic_latest_alarm_states l
          WHERE l.organization_id = s.organization_id AND l.mission_id = s.mission_id
            AND l.spacecraft_id = s.spacecraft_id AND l.#{@active})
      """,
      params
    )

    repo.query!(
      """
      INSERT INTO semantic_fleet_alarm_summaries
        (organization_id, mission_id, spacecraft_id, worst_rank, active, last_received_at, worst_state_id)
      SELECT organization_id, mission_id, spacecraft_id, max(#{@rank}), count(*), max(receipt_time),
        (array_agg(id ORDER BY #{@rank} DESC, receipt_time DESC, id DESC))[1]
      FROM semantic_latest_alarm_states
      WHERE organization_id = $1 AND mission_id = $2 AND spacecraft_id = ANY($3) AND #{@active}
      GROUP BY organization_id, mission_id, spacecraft_id
      ON CONFLICT (organization_id, mission_id, spacecraft_id) DO UPDATE SET
        worst_rank = EXCLUDED.worst_rank, active = EXCLUDED.active,
        last_received_at = EXCLUDED.last_received_at, worst_state_id = EXCLUDED.worst_state_id
      """,
      params
    )

    :ok
  end
end
