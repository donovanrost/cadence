defmodule Cadence.Reads.AlarmEpisodes do
  @moduledoc """
  Console read of alarm episodes (`docs/apogee/domain/alarm-lifecycle.md` §4): one fetch renders
  the list. Each episode carries its spacecraft (`id, name, scid`), point (`id, name, unit`) and,
  for ground limits, the thresholds of the limit definition in effect.

  `point.unit` comes from the catalog declarations of the active binding set
  (`Cadence.Reads.PointInfo`); it is `nil` when the catalog has no unit for the point.
  """

  alias Cadence.Alarms.EpisodeCursor
  alias Cadence.Auth.Scope
  alias Cadence.Control.Alarms
  alias Cadence.Limits
  alias Cadence.Reads.AlarmEpisodes.Triggers
  alias Cadence.Reads.PointInfo
  alias Cadence.SpacecraftStore

  @doc """
  One page of episodes with the summary and `next_cursor` (U69 A6d; `nil` on the last page).
  `filters[:cursor]` is a previous page's `next_cursor`.
  """
  @spec list(Scope.t(), String.t(), map()) ::
          {:ok, %{episodes: [map()], summary: map(), next_cursor: binary() | nil}}
          | {:error, term()}
  def list(%Scope{} = scope, mission_id, filters \\ %{}) do
    with {:ok, after_key} <- EpisodeCursor.decode(Map.get(filters, :cursor)),
         filters = filters |> Map.delete(:cursor) |> Map.put(:after, after_key),
         {:ok, page} <- Alarms.page_episodes(scope, mission_id, filters),
         {:ok, summary} <- Alarms.summary(scope, mission_id) do
      {:ok,
       %{
         episodes: enrich(scope.organization_id, mission_id, page.episodes),
         summary: summary,
         next_cursor: EpisodeCursor.encode(page.next)
       }}
    end
  end

  @spec get(Scope.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(%Scope{} = scope, mission_id, episode_id) do
    with {:ok, episode} <- Alarms.get_episode(scope, mission_id, episode_id) do
      [enriched] = enrich(scope.organization_id, mission_id, [episode])
      {:ok, enriched}
    end
  end

  defp enrich(organization_id, mission_id, episodes) do
    spacecraft = spacecraft(organization_id, mission_id, episodes)
    thresholds = thresholds(organization_id, mission_id, episodes)
    points = if episodes == [], do: %{}, else: PointInfo.by_id(organization_id, mission_id)

    episodes
    |> Enum.map(fn episode ->
      episode
      |> Map.put(:spacecraft, Map.get(spacecraft, episode.spacecraft_id))
      |> Map.put(:point, Map.put(episode.point, :unit, unit(points, episode.point.id)))
      |> Map.put(:thresholds, Map.get(thresholds, definition_key(episode)))
    end)
    # U68 R5: the producing definition and the triggering sample.
    |> then(&Triggers.put(organization_id, mission_id, &1))
  end

  defp spacecraft(organization_id, mission_id, episodes) do
    episodes
    |> Enum.map(& &1.spacecraft_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.chunk_every(100)
    |> Enum.reduce(%{}, fn ids, acc ->
      {:ok, found} = SpacecraftStore.fetch_spacecrafts(organization_id, mission_id, ids)

      Enum.reduce(found, acc, fn {id, sc}, inner ->
        Map.put(inner, id, %{id: id, name: sc.display_name, scid: sc.scid})
      end)
    end)
  end

  defp thresholds(organization_id, mission_id, episodes) do
    episodes
    |> Enum.map(&definition_key/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn {id, version} = key ->
      case Limits.fetch_limit_definition(organization_id, mission_id, id, version) do
        {:ok, definition} -> {key, definition.thresholds}
        {:error, _reason} -> {key, nil}
      end
    end)
  end

  defp unit(points, point_id),
    do: points |> Map.get(point_id, PointInfo.unknown()) |> Map.get(:unit)

  defp definition_key(%{source: :ground_limit, context: context}) do
    case context do
      %{"limit_definition_id" => id, "limit_definition_version" => version}
      when is_binary(id) and is_integer(version) ->
        {id, version}

      _other ->
        nil
    end
  end

  defp definition_key(_episode), do: nil
end
