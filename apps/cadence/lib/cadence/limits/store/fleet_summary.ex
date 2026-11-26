defmodule Cadence.Limits.Store.FleetSummary do
  @moduledoc """
  The fleet's limit conditions in the database (#798): one row per spacecraft from the latest limit
  states, aggregated there instead of read whole (at 1,000 spacecraft x 200 points the whole read is
  200,000 rows, 2.7 s). Two statements however many spacecraft or points there are.

  Per spacecraft that has any limit state: its worst condition across every point (`:critical` when
  one is red, `:caution` when one is yellow, else `:nominal`), how many points violate (red or
  yellow), the newest receipt time of any of its limit states, and its worst violating point (the
  most severe, then the newest) as the event it came from. A spacecraft with no limit state is
  absent.
  """

  import Ecto.Query

  alias Cadence.Limits.Event
  alias Cadence.Limits.Store.LatestStateRow
  alias Cadence.Repo

  @type summary :: %{
          limit_state: :critical | :caution | :nominal,
          violating: non_neg_integer(),
          last_received_at: DateTime.t() | nil,
          worst: Event.t() | nil
        }

  # The severity rank of a normalized state: red 2, yellow 1, everything else 0 (the violators
  # index is on exactly this expression).
  defmacrop rank(state) do
    quote do
      fragment("(CASE ? WHEN 'red' THEN 2 WHEN 'yellow' THEN 1 ELSE 0 END)", unquote(state))
    end
  end

  @spec load(binary(), binary()) :: %{binary() => summary()}
  def load(organization_id, mission_id) do
    worst = worst_violating(organization_id, mission_id)

    organization_id
    |> aggregates(mission_id)
    |> Map.new(fn {id, rank, violating, last_received_at} ->
      {id,
       %{
         limit_state: condition(rank),
         violating: violating,
         last_received_at: last_received_at,
         worst: Map.get(worst, id)
       }}
    end)
  end

  defp aggregates(organization_id, mission_id) do
    from(r in LatestStateRow,
      where:
        r.mission_id == ^mission_id and r.organization_id == ^organization_id and
          not is_nil(r.spacecraft_id),
      group_by: r.spacecraft_id,
      select: {
        r.spacecraft_id,
        max(rank(r.normalized_state)),
        filter(count(), r.violation),
        max(r.receipt_time)
      }
    )
    |> Repo.all()
  end

  # DISTINCT ON the spacecraft: its most severe, then newest, violating row.
  defp worst_violating(organization_id, mission_id) do
    from(r in LatestStateRow,
      where:
        r.mission_id == ^mission_id and r.organization_id == ^organization_id and r.violation and
          not is_nil(r.spacecraft_id),
      distinct: r.spacecraft_id,
      order_by: [asc: r.spacecraft_id, desc: rank(r.normalized_state), desc: r.receipt_time]
    )
    |> Repo.all()
    |> Map.new(&{&1.spacecraft_id, LatestStateRow.to_domain(&1)})
  end

  defp condition(2), do: :critical
  defp condition(1), do: :caution
  defp condition(_nominal), do: :nominal
end
