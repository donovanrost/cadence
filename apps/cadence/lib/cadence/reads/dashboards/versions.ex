defmodule Cadence.Reads.Dashboards.Versions do
  @moduledoc """
  Authorized comparison of two saved dashboard versions. Version documents are exposed as pretty
  JSON for diffing, without authoring metadata. (The legacy page's list and staged views went with
  L8a.)
  """
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards.{Document, Documents, Version, VersionDiff}

  @spec compare(Scope.t(), binary(), binary(), pos_integer(), pos_integer()) ::
          {:ok, map()} | {:error, :unavailable}
  def compare(%Scope{} = scope, mission, dashboard, from, to)
      when is_integer(from) and is_integer(to) and from > 0 and to > 0 and from != to do
    with :ok <- authorize(scope, mission),
         {:ok, %Version{document: older}} <-
           Documents.fetch_version(scope.organization_id, mission, dashboard, min(from, to)),
         {:ok, %Version{document: newer}} <-
           Documents.fetch_version(scope.organization_id, mission, dashboard, max(from, to)) do
      {:ok, comparison(older, newer, %{from: min(from, to), to: max(from, to)})}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def compare(_, _, _, _, _), do: {:error, :unavailable}

  defp comparison(older, newer, versions) do
    Map.merge(versions, %{
      version: 1,
      changes: VersionDiff.changes(older, newer),
      from_json: json(older),
      to_json: json(newer)
    })
  end

  defp json(%Document{} = document) do
    document
    |> Document.to_map()
    |> Map.drop([:metadata, "metadata"])
    |> Jason.encode!(pretty: true)
  end

  defp authorize(scope, mission) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission
    })
  end
end
