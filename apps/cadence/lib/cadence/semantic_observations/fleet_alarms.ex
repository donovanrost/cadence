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
  and the newest receipt among them. `refresh_batch/2` recomputes the rows of the spacecraft a batch
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
  alias Cadence.SemanticRuntime.AlarmLevel

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
  # The level table is `SemanticRuntime.AlarmLevel`'s; the SQL lists are built from it.
  @rank "(CASE WHEN effective_state IN (#{AlarmLevel.sql_in([:critical])}) THEN 2 ELSE 1 END)"
  @active "effective_state IN (#{AlarmLevel.sql_in([:caution, :critical])})"

  @spec load(binary(), binary()) :: %{binary() => alarm()}
  def load(organization_id, mission_id) do
    from(s in FleetAlarmSummaryRow,
      join: l in LatestAlarmStateRow,
      on: l.id == s.worst_state_id,
      where: s.organization_id == ^organization_id and s.mission_id == ^mission_id,
      # Only what the fleet needs of the worst alarm, not its whole row (state_document included).
      select: %{
        spacecraft_id: s.spacecraft_id,
        worst_rank: s.worst_rank,
        active: s.active,
        last_received_at: s.last_received_at,
        parameter_id: l.parameter_id,
        policy_id: l.policy_id,
        effective_state: l.effective_state,
        receipt_time: l.receipt_time
      }
    )
    |> Repo.all()
    |> Map.new(fn row ->
      {row.spacecraft_id,
       %{
         limit_state: if(row.worst_rank == 2, do: :critical, else: :caution),
         active: row.active,
         last_received_at: row.last_received_at,
         worst: %{
           parameter_id: row.parameter_id,
           policy_id: row.policy_id,
           effective_state: row.effective_state,
           receipt_time: row.receipt_time
         }
       }}
    end)
  end

  # One writer per spacecraft at a time (#871): two transactions that transition the same spacecraft
  # (two partitions after a handover, a replay beside the live owner) would each recompute from a
  # snapshot that lacks the other's uncommitted rows, and the later commit could leave a stale
  # summary. A transaction-scoped advisory lock per (mission, spacecraft) makes the second wait for
  # the first's commit; its recompute statement then reads the first's rows (READ COMMITTED takes a
  # snapshot per statement).
  #
  # The locks are taken AFTER the latest-state upserts, and that is still correct: the upserts only
  # need to be visible to the recompute of whoever commits LAST. The lock is held until commit and
  # the recompute runs after it is granted, so the last lock holder recomputes after every earlier
  # holder has committed its upserts, and sees its own. A transaction that has upserted but not yet
  # locked recomputes later, under the lock, from everything committed by then. An upsert of the
  # SAME row also waits on the row lock until the other commits.
  #
  # All locks of a batch are taken in one sorted order (mission, then spacecraft) across missions,
  # so two batches cannot wait on each other. The key has its own namespace: the ground-limit
  # summary's locks (`telemetry_fleet_limit/`) do not serialize with these.
  defp lock_spacecraft(repo, keys) do
    Enum.each(keys, fn {mission_id, spacecraft_id} ->
      repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "semantic_fleet_alarm/" <> mission_id <> "/" <> spacecraft_id
      ])
    end)
  end

  @doc """
  Recomputes the summaries of `spacecraft_ids` of a mission from their active alarms, inside the
  caller's transaction.
  """
  @spec refresh(module(), binary(), binary(), [binary()]) :: :ok
  def refresh(repo, organization_id, mission_id, spacecraft_ids) do
    refresh_batch(repo, Enum.map(spacecraft_ids, &{organization_id, mission_id, &1}))
  end

  @doc """
  Recomputes the summaries of the `{organization, mission, spacecraft}` entries a batch
  transitioned (duplicates and entries without an organization or spacecraft are ignored), inside
  the caller's transaction: every spacecraft lock first, in one sorted order, then one recompute
  per mission.
  """
  @spec refresh_batch(module(), [{binary() | nil, binary(), binary() | nil}]) :: :ok
  def refresh_batch(repo, entries) do
    entries =
      entries
      |> Enum.reject(fn {organization_id, _mission, spacecraft} ->
        is_nil(organization_id) or is_nil(spacecraft)
      end)
      |> Enum.uniq()

    entries
    |> Enum.map(fn {_org, mission, craft} -> {mission, craft} end)
    |> Enum.uniq()
    |> Enum.sort()
    |> then(&lock_spacecraft(repo, &1))

    entries
    |> Enum.group_by(fn {org, mission, _craft} -> {org, mission} end, &elem(&1, 2))
    |> Enum.each(fn {{organization_id, mission_id}, spacecraft_ids} ->
      recompute(repo, organization_id, mission_id, spacecraft_ids)
    end)
  end

  defp recompute(repo, organization_id, mission_id, spacecraft_ids) do
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
