defmodule Cadence.Reads.Dashboards.Directory do
  @moduledoc """
  Authorized dashboard directory: the mission's dashboards filtered and sorted
  for one person, with that person's starred and recently viewed shortcuts.

  Every save is the current version, so a dashboard was last updated when its
  current version was saved, by whoever saved it.
  """
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards
  alias Cadence.Dashboards.DashboardSummary
  alias Cadence.Missions
  alias Cadence.Reads.Dashboards.Authors

  @page_size 50
  @recent 5
  @max_tags 10
  @keys ~w(query tags starred archived sort page lifecycle tag)

  def load(scope, mission, params \\ %{})

  def load(
        %Scope{organization_id: org, mission_id: scoped, user: %{user_id: user}} = scope,
        mission,
        params
      )
      when is_binary(org) and org != "" and is_binary(mission) and mission != "" and
             is_binary(user) and user != "" and (is_nil(scoped) or scoped == mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{organization_id: org, mission_id: mission}),
         {:ok, _mission} <- Missions.fetch_mission(org, mission),
         {:ok, filters} <- filters(params) do
      {:ok, model(scope, mission, filters)}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def load(_scope, _mission, _params), do: {:error, :unavailable}

  defp model(%Scope{organization_id: org, user: %{user_id: user}} = scope, mission, filters) do
    active = Dashboards.list_dashboard_summaries(org, mission)

    listed =
      if filters["archived"],
        do: active ++ Dashboards.list_archived_dashboard_summaries(org, mission),
        else: active

    preferences =
      Map.new(
        Dashboards.list_dashboard_user_preferences(org, mission, user),
        &{&1.dashboard_id, &1}
      )

    matches = listed |> Enum.filter(&matches?(&1, filters, preferences)) |> sort(filters["sort"])
    pages = max(1, ceil(length(matches) / @page_size))
    page = min(filters["page"], pages)
    rows = Enum.slice(matches, (page - 1) * @page_size, @page_size)
    shortcuts = shortcuts(active, preferences)

    names =
      Authors.names(Enum.map(rows ++ shortcuts.starred ++ shortcuts.recent, & &1.published_by))

    %{
      version: 2,
      mission_id: mission,
      author: author?(scope, mission),
      filters: Map.put(filters, "page", page),
      available_tags: listed |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort(),
      total: length(matches),
      pages: pages,
      page_size: @page_size,
      rows: Enum.map(rows, &row(&1, preferences, names)),
      shortcuts: %{
        starred: Enum.map(shortcuts.starred, &row(&1, preferences, names)),
        recent: Enum.map(shortcuts.recent, &row(&1, preferences, names))
      }
    }
  end

  @doc """
  Admits directory URL filters. Bookmarks from the earlier directory
  (`lifecycle`, a single `tag`, `sort=widgets`) still resolve.
  """
  def filters(params) when is_map(params) and map_size(params) <= length(@keys) do
    with true <- Enum.all?(params, &param?/1),
         {:ok, sort} <- sort_param(Map.get(params, "sort", "updated")),
         {:ok, page} <- page_param(Map.get(params, "page", "1")),
         {:ok, starred} <- flag(Map.get(params, "starred")),
         {:ok, archived} <- archived(params),
         {:ok, tags} <- tags(params) do
      {:ok,
       %{
         "query" => String.trim(Map.get(params, "query", "")),
         "tags" => tags,
         "starred" => starred,
         "archived" => archived,
         "sort" => sort,
         "page" => page
       }}
    else
      _ -> {:error, :invalid_filters}
    end
  end

  def filters(_params), do: {:error, :invalid_filters}

  defp param?({key, value}),
    do: key in @keys and is_binary(value) and String.valid?(value) and byte_size(value) <= 512

  defp sort_param(sort) when sort in ~w(updated name name_desc), do: {:ok, sort}
  defp sort_param("widgets"), do: {:ok, "updated"}
  defp sort_param(_sort), do: :error

  defp page_param(value) do
    case Integer.parse(value) do
      {page, ""} when page in 1..1_000_000 -> {:ok, page}
      _ -> :error
    end
  end

  defp flag(nil), do: {:ok, false}
  defp flag("true"), do: {:ok, true}
  defp flag("false"), do: {:ok, false}
  defp flag(_value), do: :error

  defp archived(%{"archived" => value}), do: flag(value)
  defp archived(%{"lifecycle" => "active"}), do: {:ok, false}
  defp archived(%{"lifecycle" => lifecycle}) when lifecycle in ~w(archived all), do: {:ok, true}
  defp archived(%{"lifecycle" => _}), do: :error
  defp archived(_params), do: {:ok, false}

  defp tags(params) do
    legacy = if Map.get(params, "tag", "all") in ["", "all"], do: [], else: [params["tag"]]

    tags =
      (String.split(Map.get(params, "tags", ""), ",") ++ legacy)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if length(tags) <= @max_tags, do: {:ok, tags}, else: :error
  end

  defp matches?(%DashboardSummary{} = summary, filters, preferences) do
    haystack =
      String.downcase(Enum.join([summary.name, summary.description || "" | summary.tags], " "))

    String.contains?(haystack, String.downcase(filters["query"])) and
      Enum.all?(filters["tags"], &(&1 in summary.tags)) and
      (not filters["starred"] or starred?(preferences, summary.dashboard_id))
  end

  defp sort(summaries, "name"),
    do: Enum.sort_by(summaries, &{String.downcase(&1.name), &1.dashboard_id})

  defp sort(summaries, "name_desc"),
    do: Enum.sort_by(summaries, &{String.downcase(&1.name), &1.dashboard_id}, :desc)

  defp sort(summaries, "updated"),
    do: Enum.sort_by(summaries, &{-timestamp(updated_at(&1)), &1.dashboard_id})

  defp shortcuts(active, preferences) do
    starred =
      active
      |> Enum.filter(&starred?(preferences, &1.dashboard_id))
      |> Enum.sort_by(&{String.downcase(&1.name), &1.dashboard_id})

    recent =
      active
      |> Enum.filter(&viewed_at(preferences, &1.dashboard_id))
      |> Enum.sort_by(&viewed_at(preferences, &1.dashboard_id), {:desc, DateTime})
      |> Enum.take(@recent)

    %{starred: starred, recent: recent}
  end

  defp row(%DashboardSummary{} = summary, preferences, names) do
    %{
      id: summary.dashboard_id,
      name: summary.name,
      description: summary.description,
      tags: summary.tags,
      archived: summary.lifecycle_state == "archived",
      starred: starred?(preferences, summary.dashboard_id),
      version: summary.latest_version,
      updated_at: iso(updated_at(summary)),
      updated_by: summary.published_by && Map.get(names, summary.published_by),
      viewed_at: iso(viewed_at(preferences, summary.dashboard_id))
    }
  end

  defp author?(%Scope{organization_id: org} = scope, mission),
    do:
      Policy.authorize(scope, :author_dashboards, %{organization_id: org, mission_id: mission}) ==
        :ok

  defp starred?(preferences, id), do: match?(%{starred: true}, Map.get(preferences, id))

  defp viewed_at(preferences, id) do
    case Map.get(preferences, id) do
      %{last_viewed_at: %DateTime{} = at} -> at
      _ -> nil
    end
  end

  defp updated_at(%DashboardSummary{published_at: %DateTime{} = at}), do: at
  defp updated_at(%DashboardSummary{updated_at: at}), do: at

  defp timestamp(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)
  defp timestamp(_value), do: 0

  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso(_value), do: nil
end
