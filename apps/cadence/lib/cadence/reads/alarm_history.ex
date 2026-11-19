defmodule Cadence.Reads.AlarmHistory do
  @moduledoc """
  Investigate's History tab (ux Investigate.md, 7631176e): a spacecraft's alarm episodes over
  the last 90 days with counts, and one episode with the same alarm's (or point's) earlier
  occurrences, counts and median duration. Items are `Cadence.Alarms.History` occurrences with
  the point's catalog unit added; the episode is the full `Cadence.Reads.AlarmEpisodes` shape.
  """

  alias Cadence.Alarms.History
  alias Cadence.Auth.Scope
  alias Cadence.Control.Alarms
  alias Cadence.Reads.{AlarmEpisodes, PointInfo}

  @spec spacecraft(Scope.t(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def spacecraft(%Scope{} = scope, mission_id, spacecraft_id, opts) do
    with {:ok, history} <- Alarms.spacecraft_history(scope, mission_id, spacecraft_id, opts) do
      {:ok, shape(scope, mission_id, history)}
    end
  end

  @spec episode(Scope.t(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def episode(%Scope{} = scope, mission_id, episode_id, opts) do
    with {:ok, history} <- Alarms.episode_history(scope, mission_id, episode_id, opts),
         {:ok, episode} <- AlarmEpisodes.get(scope, mission_id, episode_id) do
      {:ok,
       scope
       |> shape(mission_id, history)
       |> Map.merge(%{
         episode: episode,
         first_opened_at: history.stats.first_opened_at,
         median_duration_s: history.stats.median_duration_s
       })}
    end
  end

  defp shape(scope, mission_id, %{stats: stats, page: page}) do
    points =
      if page.items == [], do: %{}, else: PointInfo.by_id(scope.organization_id, mission_id)

    %{
      counts: stats.counts,
      retention_days: History.retention_days(),
      items: Enum.map(page.items, &with_unit(&1, points)),
      next_before: page.next_before
    }
  end

  defp with_unit(item, points) do
    unit = points |> Map.get(item.point.id, PointInfo.unknown()) |> Map.get(:unit)
    Map.update!(item, :point, &Map.put(&1, :unit, unit))
  end
end
