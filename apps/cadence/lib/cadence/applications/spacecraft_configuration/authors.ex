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
  alias Cadence.Catalog.SpacecraftModelBindings
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
    with {:ok, ids} <- SpacecraftModelBindings.reviewed_spacecraft_ids(metadata),
         {:ok, active} <- Active.load(mission) do
      Enum.reduce_while(ids, {:ok, %{}}, &collect(mission, metadata, active, &1, &2))
    else
      _unreadable -> {:error, {:activation_approver_authors_unknown, reviewed_ids(metadata)}}
    end
  end

  def by_spacecraft(_mission, _metadata), do: {:ok, %{}}

  defp collect(mission, metadata, active, id, {:ok, acc}) do
    review = SpacecraftModelBindings.review_for(metadata, id) || %{}

    case authors(mission, id, review["configuration_revision_id"], active.entries[id]) do
      {:ok, authors} -> {:cont, {:ok, Map.put(acc, id, authors)}}
      :error -> {:halt, {:error, {:activation_approver_authors_unknown, [id]}}}
    end
  end

  defp reviewed_ids(metadata) do
    case SpacecraftModelBindings.reviewed_spacecraft_ids(metadata) do
      {:ok, ids} -> ids
      _unreadable -> []
    end
  end

  defp authors(_mission, _id, nil, _active_entry), do: :error

  defp authors(mission, id, revision_id, active_entry) do
    case Repo.get(RevisionRow, revision_id) do
      %RevisionRow{version: reviewed, spacecraft_id: ^id} ->
        floor = (active_entry || %{})["configuration_version"] || 0

        RevisionRow
        |> where(
          [row],
          row.organization_id == ^mission.organization_id and
            row.mission_id == ^mission.mission_id and row.spacecraft_id == ^id and
            row.version > ^floor and row.version <= ^reviewed
        )
        |> select([row], row.created_by)
        |> distinct(true)
        |> Repo.all()
        |> then(&{:ok, &1})

      _missing_or_another_craft ->
        :error
    end
  end
end
