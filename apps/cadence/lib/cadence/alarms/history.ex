defmodule Cadence.Alarms.History do
  @moduledoc """
  Past alarm episodes of one spacecraft, for Investigate's History tab, in raw form.
  `Cadence.Reads.AlarmHistory` adds point units for the console.

  An occurrence is an episode in the `Cadence.Alarms.Queries.view/1` shape plus `condition` (the
  source state), `direction` (`:low | :high | nil`, from ground-limit states), `duration_s` and
  `ended` (`:back_in_limits | :source_stopped | :rule_retired | :rule_disabled | nil` while open). Episodes are listed newest
  opened first over `@horizon_days`, keyset-paged by `{opened_at, episode_id}`. Episodes are
  never pruned, so `retention_days/0` is nil.
  """

  import Ecto.Query

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow, Queries}
  alias Cadence.Repo

  @horizon_days 90
  @max_limit 200
  @count_days [7, 30, 90]
  @directions %{
    "red_low" => :low,
    "yellow_low" => :low,
    "red_high" => :high,
    "yellow_high" => :high
  }

  @type filter :: %{
          required(:spacecraft_id) => String.t(),
          optional(:point_id) => String.t(),
          optional(:subject) => {String.t(), String.t()},
          optional(:opened_before) => {DateTime.t(), String.t()}
        }

  @doc "How long episodes are kept, in days; nil while they are never pruned."
  @spec retention_days() :: pos_integer() | nil
  def retention_days, do: nil

  @doc "The episode's history filter: same spacecraft and subject (`:alarm`) or point (`:point`)."
  @spec filter_for(String.t(), String.t(), :alarm | :point) ::
          {:ok, filter()} | {:error, :episode_not_found}
  def filter_for(mission_id, episode_id, scope) do
    case Repo.get_by(EpisodeRow, mission_id: mission_id, episode_id: episode_id) do
      nil ->
        {:error, :episode_not_found}

      row ->
        base = %{
          spacecraft_id: row.spacecraft_id,
          opened_before: {row.opened_at, row.episode_id}
        }

        {:ok,
         if(scope == :point,
           do: Map.put(base, :point_id, row.parameter_ref),
           else: Map.put(base, :subject, {row.source, row.subject_key})
         )}
    end
  end

  @doc "One page of occurrences, newest opened first, and the cursor of the next page."
  @spec page(String.t(), filter(), {DateTime.t(), String.t()} | nil, pos_integer(), DateTime.t()) ::
          %{items: [map()], next_before: {DateTime.t(), String.t()} | nil}
  def page(mission_id, filter, before, limit, now) do
    limit = limit |> min(@max_limit) |> max(1)

    rows =
      mission_id
      |> base(filter)
      |> where([e], e.opened_at >= ^DateTime.add(now, -@horizon_days * 86_400))
      |> before(before)
      |> order_by([e], desc: e.opened_at, desc: e.episode_id)
      |> limit(^(limit + 1))
      |> Repo.all()

    {shown, rest} = Enum.split(rows, limit)
    causes = clear_causes(Enum.map(shown, & &1.episode_id))

    %{
      items: Enum.map(shown, &occurrence(&1, causes)),
      next_before:
        if(rest == [],
          do: nil,
          else: shown |> List.last() |> then(&{&1.opened_at, &1.episode_id})
        )
    }
  end

  @doc """
  Counts of episodes opened in the last 7, 30 and 90 days, the first one's open time and the
  median duration of the cleared ones. `opened_before` doesn't apply: an episode counts itself.
  """
  @spec stats(String.t(), filter(), DateTime.t()) :: map()
  def stats(mission_id, filter, now) do
    query = base(mission_id, Map.delete(filter, :opened_before))

    counts =
      Map.new(@count_days, fn days ->
        since = DateTime.add(now, -days * 86_400)
        {:"d#{days}", Repo.aggregate(where(query, [e], e.opened_at >= ^since), :count)}
      end)

    %{
      counts: counts,
      first_opened_at: Repo.aggregate(query, :min, :opened_at),
      median_duration_s:
        query
        |> where([e], not is_nil(e.cleared_at))
        |> select(
          [e],
          fragment(
            "percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM ? - ?))",
            e.cleared_at,
            e.opened_at
          )
        )
        |> Repo.one()
        |> seconds()
    }
  end

  defp base(mission_id, filter) do
    EpisodeRow
    |> where([e], e.mission_id == ^mission_id and e.spacecraft_id == ^filter.spacecraft_id)
    |> point(Map.get(filter, :point_id))
    |> subject(Map.get(filter, :subject))
    |> before(Map.get(filter, :opened_before))
  end

  defp point(query, nil), do: query
  defp point(query, point_id), do: where(query, [e], e.parameter_ref == ^point_id)

  defp subject(query, nil), do: query

  defp subject(query, {source, key}),
    do: where(query, [e], e.source == ^source and e.subject_key == ^key)

  defp before(query, nil), do: query

  defp before(query, {at, id}),
    do: where(query, [e], e.opened_at < ^at or (e.opened_at == ^at and e.episode_id < ^id))

  defp clear_causes([]), do: %{}

  defp clear_causes(episode_ids) do
    EpisodeEventRow
    |> where([v], v.episode_id in ^episode_ids and v.kind == "cleared")
    |> select([v], {v.episode_id, fragment("?->>'cause'", v.payload)})
    |> Repo.all()
    |> Map.new()
  end

  defp occurrence(row, causes) do
    row
    |> Queries.view()
    |> Map.merge(%{
      condition: row.source_state,
      direction: Map.get(@directions, row.source_state),
      duration_s: row.cleared_at && DateTime.diff(row.cleared_at, row.opened_at, :second),
      ended: ended(row, Map.get(causes, row.episode_id))
    })
  end

  defp ended(%EpisodeRow{state: "cleared"}, "reconcile"), do: :source_stopped
  defp ended(%EpisodeRow{state: "cleared"}, "rule_retired"), do: :rule_retired
  defp ended(%EpisodeRow{state: "cleared"}, "rule_disabled"), do: :rule_disabled
  defp ended(%EpisodeRow{state: "cleared"}, _in_limits), do: :back_in_limits
  defp ended(%EpisodeRow{}, _cause), do: nil

  defp seconds(nil), do: nil
  defp seconds(%Decimal{} = value), do: value |> Decimal.round(0) |> Decimal.to_integer()
  defp seconds(value) when is_float(value), do: round(value)
end
