defmodule Cadence.Reads.ApplicationSurfaces.Planning.ContactRequirementShow do
  @moduledoc "Versioned, bounded requirement review for an authorized mission surface."

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, Planner}
  alias Cadence.Reads.ApplicationSurfaces.Planning.RequirementDetailProjection

  @pages ~w(versions_page runs_page searches_page opportunities_page)
  @keys ~w(contact_requirement_id version planning_run_id) ++ @pages

  def admit_query(params) when is_map(params) do
    with true <- Enum.all?(params, fn {k, v} -> k in @keys and identifier?(v) end),
         true <- identifier?(params["contact_requirement_id"]),
         {:ok, version} <- optional_version(params["version"]),
         {:ok, pages} <- pages(params),
         true <-
           params["planning_run_id"] != nil or
             (pages["searches_page"] == 1 and pages["opportunities_page"] == 1) do
      {:ok,
       Map.merge(pages, %{
         "contact_requirement_id" => params["contact_requirement_id"],
         "version" => version,
         "planning_run_id" => params["planning_run_id"]
       })}
    else
      _ -> {:error, :invalid_requirement_detail_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_requirement_detail_query}

  def load(%Scope{} = scope, mission, params) do
    org = scope.organization_id
    mission_id = mission.mission_id

    with {:ok, query} <- admit_query(Map.delete(params, "mission_id")),
         {:ok, requirement, current} <-
           ContactRequirements.fetch(org, mission_id, query["contact_requirement_id"]),
         {:ok, reviewed} <-
           reviewed_version(org, mission_id, requirement, current, query["version"]),
         query = Map.put(query, "version", reviewed.version),
         {:ok, run} <-
           selected_run(org, mission_id, requirement, reviewed, query["planning_run_id"]),
         {:ok, versions} <-
           ContactRequirements.list_versions_page(
             org,
             mission_id,
             requirement.contact_requirement_id,
             reviewed.version,
             query["versions_page"]
           ),
         {:ok, runs} <-
           Planner.list_runs_page(
             org,
             mission_id,
             requirement.contact_requirement_id,
             query["runs_page"]
           ),
         {:ok, searches, opportunities} <- evidence(org, mission_id, run, query) do
      {:ok,
       %{
         detail:
           RequirementDetailProjection.project(
             scope,
             requirement,
             reviewed,
             run,
             query,
             %{versions: versions, runs: runs, searches: searches, opportunities: opportunities}
           )
       }}
    end
  end

  defp reviewed_version(_org, _mission, _requirement, current, nil), do: {:ok, current}

  defp reviewed_version(org, mission, requirement, current, version)
       when version <= current.version,
       do:
         ContactRequirements.fetch_version(
           org,
           mission,
           requirement.contact_requirement_id,
           version
         )

  defp reviewed_version(_, _, _, _, _), do: {:error, :future_requirement_version}

  defp selected_run(_org, _mission, _requirement, _version, nil), do: {:ok, nil}

  defp selected_run(org, mission, requirement, version, id) do
    with {:ok, run} <- Planner.fetch_run(org, mission, id),
         true <-
           run.contact_requirement_id == requirement.contact_requirement_id and
             run.contact_requirement_version == version.version do
      {:ok, run}
    else
      _ -> {:error, :requirement_run_mismatch}
    end
  end

  defp evidence(_org, _mission, nil, _query),
    do: {:ok, %{entries: [], more?: false}, %{entries: [], more?: false}}

  defp evidence(org, mission, run, query) do
    with {:ok, searches} <-
           Planner.list_searches_page(
             org,
             mission,
             run.contact_planning_run_id,
             query["searches_page"]
           ),
         {:ok, opportunities} <-
           Planner.list_snapshots_page(
             org,
             mission,
             run.contact_planning_run_id,
             query["opportunities_page"]
           ) do
      {:ok, searches, opportunities}
    end
  end

  defp pages(params) do
    Enum.reduce_while(@pages, {:ok, %{}}, fn key, {:ok, acc} ->
      case number(Map.get(params, key, "1"), 1_000_000) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        _ -> {:halt, {:error, :invalid_page}}
      end
    end)
  end

  defp optional_version(nil), do: {:ok, nil}
  defp optional_version(value), do: number(value, 9_007_199_254_740_991)

  defp number(value, maximum) when is_binary(value) do
    with true <- Regex.match?(~r/\A[1-9][0-9]{0,15}\z/, value),
         {integer, ""} when integer <= maximum <- Integer.parse(value) do
      {:ok, integer}
    else
      _ -> {:error, :invalid_integer}
    end
  end

  defp number(_, _), do: {:error, :invalid_integer}

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..240,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x20\x7f]/, value)

  defp identifier?(_), do: false
end
