defmodule Cadence.Reads.Dashboards.Directory do
  @moduledoc "Authorized, versioned dashboard directory data independent of frontend delivery."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards
  alias Cadence.Missions

  @page_size 50
  @keys ~w(query lifecycle tag sort page)

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
      active = Dashboards.list_dashboard_summaries(org, mission)
      archived = Dashboards.list_archived_dashboard_summaries(org, mission)
      summaries = active ++ archived
      tags = summaries |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

      preferences =
        Map.new(
          Dashboards.list_dashboard_user_preferences(org, mission, user),
          &{&1.dashboard_id, &1.starred}
        )

      matches =
        summaries
        |> Enum.filter(&matches?(&1, filters))
        |> Enum.sort_by(&sort_key(&1, filters["sort"]))

      total = length(matches)
      pages = max(1, ceil(total / @page_size))
      page = min(filters["page"], pages)

      rows =
        matches
        |> Enum.slice((page - 1) * @page_size, @page_size)
        |> Enum.map(&row(&1, preferences))

      {:ok,
       %{
         version: 1,
         mission_id: mission,
         author:
           Policy.authorize(scope, :author_dashboards, %{
             organization_id: org,
             mission_id: mission
           }) == :ok,
         filters: Map.put(filters, "page", page),
         available_tags: tags,
         total: total,
         pages: pages,
         page_size: @page_size,
         rows: rows
       }}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def load(_scope, _mission, _params), do: {:error, :unavailable}

  def filters(params) when is_map(params) and map_size(params) <= 5 do
    with true <-
           Enum.all?(params, fn {key, value} ->
             key in @keys and is_binary(value) and String.valid?(value) and
               byte_size(value) <= 512
           end),
         query = String.trim(Map.get(params, "query", "")),
         lifecycle = Map.get(params, "lifecycle", "active"),
         true <- lifecycle in ~w(active archived all),
         sort = Map.get(params, "sort", "updated"),
         true <- sort in ~w(updated name widgets),
         tag = Map.get(params, "tag", "all"),
         {page, ""} when page > 0 and page <= 1_000_000 <-
           Integer.parse(Map.get(params, "page", "1")) do
      {:ok,
       %{"query" => query, "lifecycle" => lifecycle, "tag" => tag, "sort" => sort, "page" => page}}
    else
      _ -> {:error, :invalid_filters}
    end
  end

  def filters(_params), do: {:error, :invalid_filters}

  defp matches?(summary, filters) do
    haystack =
      String.downcase(Enum.join([summary.name, summary.description || "" | summary.tags], " "))

    (filters["query"] == "" or String.contains?(haystack, String.downcase(filters["query"]))) and
      (filters["lifecycle"] == "all" or summary.lifecycle_state == filters["lifecycle"]) and
      (filters["tag"] in ["", "all"] or filters["tag"] in summary.tags)
  end

  defp sort_key(summary, "name"), do: {String.downcase(summary.name), summary.dashboard_id}
  defp sort_key(summary, "widgets"), do: {-summary.widget_count, summary.dashboard_id}
  defp sort_key(summary, "updated"), do: {-timestamp(summary.updated_at), summary.dashboard_id}
  defp timestamp(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)
  defp timestamp(_value), do: 0

  defp row(summary, preferences) do
    %{
      id: summary.dashboard_id,
      name: summary.name,
      description: summary.description,
      tags: summary.tags,
      lifecycle: summary.lifecycle_state,
      starred: Map.get(preferences, summary.dashboard_id, false),
      version: summary.latest_version,
      published_version: summary.published_version,
      widget_count: summary.widget_count
    }
  end
end
