defmodule Cadence.Applications.SpacecraftConfiguration.Authors do
  @moduledoc """
  Who authored the spacecraft configuration a review activates (board #236): for each reviewed
  spacecraft, everyone who saved a configuration version AFTER the spacecraft's active
  configuration, up to and including the reviewed version (every version when none is active).
  Each save stores the whole document, but the content carries every saver's choices, so all of
  them count, as a change set's change authors do. Read from the immutable revision rows.
  """
  import Ecto.Query

  alias Cadence.Applications.SpacecraftConfiguration.{Active, RevisionRow}
  alias Cadence.Catalog.ConfigurationReviews
  alias Cadence.Repo

  @doc """
  `{:ok, %{spacecraft_id => [user ids]}}` for a review's metadata (`{:ok, %{}}` for a request that
  isn't a configuration review). It FAILS CLOSED: a review it can't read, or a reviewed version it
  can't find, is `{:error, {:activation_approver_authors_unknown, spacecraft_ids}}` naming the
  spacecraft whose authors couldn't be read (`[]` when the review itself is unreadable), which the
  approval refuses on (lead's ruling 11-18).
  """
  @spec by_spacecraft(map(), map()) :: {:ok, %{binary() => [binary()]}} | {:error, term()}
  def by_spacecraft(mission, %{"configuration_review" => _} = metadata) do
    with {:ok, evidence} <- ConfigurationReviews.evidence(metadata),
         ids = evidence |> Map.keys() |> Enum.sort(),
         {:ok, active} <- Active.load(mission),
         {:ok, reviewed} <- reviewed_versions(mission, evidence, ids) do
      {:ok, authors(mission, reviewed, active.entries)}
    else
      {:error, {:activation_approver_authors_unknown, _ids}} = unknown -> unknown
      _unreadable -> {:error, {:activation_approver_authors_unknown, reviewed_ids(metadata)}}
    end
  end

  def by_spacecraft(_mission, _metadata), do: {:ok, %{}}

  # ONE query for every reviewed craft's reviewed version (a fleet review holds up to 500, and
  # approval runs this under its locks; api-ops, lead 11-18). A craft whose review names no
  # revision, or whose revision is missing or another craft's, fails closed: the first such craft
  # in review order, as before.
  defp reviewed_versions(mission, evidence, ids) do
    revision_ids =
      Map.new(ids, fn id ->
        {id, (evidence[id] || %{})["configuration_revision_id"]}
      end)

    rows = revision_rows(mission, revision_ids |> Map.values() |> Enum.filter(&is_binary/1))

    Enum.reduce_while(ids, {:ok, %{}}, fn id, {:ok, acc} ->
      case rows[revision_ids[id]] do
        {^id, version} ->
          {:cont, {:ok, Map.put(acc, id, version)}}

        _missing_or_another_craft ->
          {:halt, {:error, {:activation_approver_authors_unknown, [id]}}}
      end
    end)
  end

  defp revision_rows(_mission, []), do: %{}

  defp revision_rows(mission, revision_ids) do
    RevisionRow
    |> where(
      [row],
      row.organization_id == ^mission.organization_id and row.mission_id == ^mission.mission_id and
        row.configuration_revision_id in ^revision_ids
    )
    |> select([row], {row.configuration_revision_id, {row.spacecraft_id, row.version}})
    |> Repo.all()
    |> Map.new()
  end

  # ONE query for the authors: every version of the reviewed craft between the lowest floor and
  # the highest reviewed version; each craft's own window (after its active version, up to its
  # reviewed one) is applied here.
  defp authors(_mission, reviewed, _entries) when map_size(reviewed) == 0, do: %{}

  defp authors(mission, reviewed, entries) do
    floors = Map.new(reviewed, fn {id, _version} -> {id, floor_version(entries[id])} end)
    ids = Map.keys(reviewed)

    RevisionRow
    |> where(
      [row],
      row.organization_id == ^mission.organization_id and row.mission_id == ^mission.mission_id and
        row.spacecraft_id in ^ids and row.version > ^Enum.min(Map.values(floors)) and
        row.version <= ^Enum.max(Map.values(reviewed))
    )
    |> select([row], {row.spacecraft_id, row.version, row.created_by})
    |> Repo.all()
    |> Enum.filter(fn {id, version, _by} -> version > floors[id] and version <= reviewed[id] end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 2))
    |> then(&Map.new(reviewed, fn {id, _version} -> {id, Enum.uniq(Map.get(&1, id, []))} end))
  end

  defp floor_version(active_entry), do: (active_entry || %{})["configuration_version"] || 0

  defp reviewed_ids(metadata) do
    case ConfigurationReviews.spacecraft_ids(metadata) do
      {:ok, ids} -> ids
      _unreadable -> []
    end
  end
end
