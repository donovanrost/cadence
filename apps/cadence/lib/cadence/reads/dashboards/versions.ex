defmodule Cadence.Reads.Dashboards.Versions do
  @moduledoc """
  Authorized dashboard version history: the list, comparisons and the changes
  an author is about to save. Version documents are exposed as pretty JSON for
  diffing, without authoring metadata.
  """
  alias Cadence.Accounts
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards.{Document, Documents, Version, VersionDiff}

  @max_versions 200

  @spec list(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, :unavailable}
  def list(%Scope{} = scope, mission, dashboard) do
    with :ok <- authorize(scope, mission),
         {:ok, current} <-
           Documents.fetch_for_mode(scope.organization_id, mission, dashboard, :view),
         versions when is_list(versions) <-
           Documents.list_versions(scope.organization_id, mission, dashboard) do
      latest = Document.version(current)
      versions = versions |> Enum.sort_by(& &1.version, :desc) |> Enum.take(@max_versions)
      names = names(versions)

      {:ok,
       %{
         version: 1,
         dashboard_id: dashboard,
         current_version: latest,
         versions: Enum.map(versions, &row(&1, latest, names))
       }}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

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

  @doc "The comparison between a saved baseline and a staged candidate."
  @spec staged(Document.t(), Document.t()) :: map()
  def staged(%Document{} = baseline, %Document{} = candidate),
    do: comparison(baseline, candidate, %{from: Document.version(baseline), to: nil})

  @doc "Readable changes only, for page payloads that must stay small."
  @spec summary(Document.t(), Document.t()) :: [VersionDiff.change()]
  def summary(%Document{} = from, %Document{} = to), do: VersionDiff.changes(from, to)

  defp comparison(older, newer, versions) do
    Map.merge(versions, %{
      version: 1,
      changes: VersionDiff.changes(older, newer),
      from_json: json(older),
      to_json: json(newer)
    })
  end

  defp row(%Version{} = version, latest, names) do
    %{
      version: version.version,
      saved_at: version.inserted_at && DateTime.to_iso8601(version.inserted_at),
      saved_by: Map.get(names, version.created_by, version.created_by),
      message: version.change_summary,
      restored_from:
        if(version.snapshot_kind == :revert, do: version.based_on_version, else: nil),
      current: version.version == latest
    }
  end

  defp names(versions) do
    versions
    |> Enum.map(& &1.created_by)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn id ->
      case Accounts.fetch_user(id) do
        {:ok, user} -> {id, user.display_name || user.email}
        _ -> {id, id}
      end
    end)
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
