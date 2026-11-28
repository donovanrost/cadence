defmodule CadenceWeb.Console.PointConditionJSON do
  @moduledoc "Wire shape of a spacecraft's point conditions. Contract: docs/apogee/api/ops.md."

  alias CadenceWeb.Console.WireValue

  @spec points(map()) :: [map()]
  def points(%{points: points}), do: Enum.map(points, &point/1)

  @spec meta(map()) :: map()
  def meta(result) do
    %{
      observed_at: result.observed_at,
      next_cursor: result.next_cursor,
      stale_after_s: result.stale_after_s,
      telemetry: Atom.to_string(result.telemetry),
      counts: result.counts
    }
  end

  defp point(row) do
    %{
      point_id: row.point_id,
      point_name: row.point_name,
      unit: row.unit,
      source: Atom.to_string(row.source),
      policy_id: row.policy_id,
      condition: Atom.to_string(row.condition),
      raw_limit_state: row.raw_limit_state,
      evaluated: row.evaluated,
      evaluated_at: row.evaluated_at,
      entered_at: row.entered_at,
      entered_at_is_lower_bound: row.entered_at_is_lower_bound,
      value: WireValue.encode(row.value),
      last_sample_at: row.last_sample_at,
      freshness: Atom.to_string(row.freshness)
    }
  end
end
