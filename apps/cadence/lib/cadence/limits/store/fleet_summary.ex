defmodule Cadence.Limits.Store.FleetSummary do
  @moduledoc """
  The fleet's limit conditions, one row per spacecraft (#798, #849). `telemetry_fleet_limit_summaries`
  summarizes each spacecraft's latest limit states: its worst condition across every point
  (`:critical` when one is red, `:caution` when one is yellow, else `:nominal`), how many points
  violate (red or yellow), the newest receipt time of any of its limit states, and its worst
  violating point (the most severe, then the newest) as the state it came from. A spacecraft with no
  limit state has no row.

  **Kept by the writers, in their transaction.** `refresh/3` recomputes the rows of the spacecraft a
  writer touched from their latest states (one aggregate over that spacecraft's rows, about 0.6 ms
  at 200 points, once per spacecraft per transaction), and removes the row of a spacecraft left
  without states. `Limits.Store.persist_latest_states/2` and `replace_latest_states/3`, the only
  writers of `telemetry_latest_limit_states`, call it; a new writer must too (the property test in
  `fleet_summary_property_test.exs` is the check). Bulk fixtures call `refresh(repo, mission, :all)`.

  `load/2` is one statement over the summaries however many spacecraft or points there are.
  """

  import Ecto.Query

  alias Cadence.Limits.Event
  alias Cadence.Limits.Store.{FleetSummaryRow, LatestStateRow}
  alias Cadence.Repo

  @type summary :: %{
          limit_state: :critical | :caution | :nominal,
          violating: non_neg_integer(),
          last_received_at: DateTime.t() | nil,
          worst: Event.t() | nil,
          worst_evaluated_at: DateTime.t() | nil
        }

  # The severity rank of a normalized state: red 2, yellow 1, everything else 0.
  @rank "(CASE normalized_state WHEN 'red' THEN 2 WHEN 'yellow' THEN 1 ELSE 0 END)"

  @spec load(binary(), binary()) :: %{binary() => summary()}
  def load(organization_id, mission_id) do
    from(s in FleetSummaryRow,
      left_join: l in LatestStateRow,
      on: l.id == s.worst_state_id,
      where: s.organization_id == ^organization_id and s.mission_id == ^mission_id,
      select: {s, l}
    )
    |> Repo.all()
    |> Map.new(fn {summary, worst} ->
      {summary.spacecraft_id,
       %{
         limit_state: condition(summary.worst_rank),
         violating: summary.violating,
         last_received_at: summary.last_received_at,
         worst: worst && LatestStateRow.to_domain(worst),
         # When the ground-limit evaluation that wrote the worst state ran (not when its sample
         # arrived): ground limits are batch, and the console says how old they are (DECISIONS #17).
         worst_evaluated_at: worst && worst.updated_at
       }}
    end)
  end

  @doc """
  Recomputes the summaries of `spacecraft_ids` (or of every spacecraft of the mission, `:all`) from
  their latest limit states, inside the caller's transaction.
  """
  @spec refresh(module(), binary(), :all | [binary()]) :: :ok
  def refresh(_repo, _mission_id, []), do: :ok

  def refresh(repo, mission_id, spacecraft_ids) do
    {scope, params} =
      case spacecraft_ids do
        :all -> {"", [mission_id]}
        ids -> {"AND SCOPE_COLUMN = ANY($2)", [mission_id, ids]}
      end

    repo.query!(delete_sql(scope), params)
    repo.query!(upsert_sql(scope), params)
    :ok
  end

  defp delete_sql(scope) do
    """
    DELETE FROM telemetry_fleet_limit_summaries s
    WHERE s.mission_id = $1 #{String.replace(scope, "SCOPE_COLUMN", "s.spacecraft_id")}
      AND NOT EXISTS (
        SELECT 1 FROM telemetry_latest_limit_states l
        WHERE l.mission_id = s.mission_id AND l.organization_id = s.organization_id
          AND l.spacecraft_scope_id = s.spacecraft_id AND l.spacecraft_id IS NOT NULL)
    """
  end

  defp upsert_sql(scope) do
    """
    INSERT INTO telemetry_fleet_limit_summaries
      (organization_id, mission_id, spacecraft_id, worst_rank, violating, last_received_at, worst_state_id)
    SELECT organization_id, mission_id, spacecraft_id, max(#{@rank}), count(*) FILTER (WHERE violation),
      max(receipt_time),
      (array_agg(id ORDER BY #{@rank} DESC, receipt_time DESC, id DESC) FILTER (WHERE violation))[1]
    FROM telemetry_latest_limit_states
    WHERE mission_id = $1 #{String.replace(scope, "SCOPE_COLUMN", "spacecraft_scope_id")}
      AND spacecraft_id IS NOT NULL AND organization_id IS NOT NULL
    GROUP BY organization_id, mission_id, spacecraft_id
    ON CONFLICT (organization_id, mission_id, spacecraft_id) DO UPDATE SET
      worst_rank = EXCLUDED.worst_rank, violating = EXCLUDED.violating,
      last_received_at = EXCLUDED.last_received_at, worst_state_id = EXCLUDED.worst_state_id
    """
  end

  defp condition(2), do: :critical
  defp condition(1), do: :caution
  defp condition(_nominal), do: :nominal
end
