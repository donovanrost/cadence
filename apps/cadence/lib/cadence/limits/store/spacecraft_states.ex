defmodule Cadence.Limits.Store.SpacecraftStates do
  @moduledoc """
  One spacecraft's latest ground-limit states (#143): a row per point a limit job has evaluated for
  it, each with when that job ran (`updated_at` of the state row). The mission-scope states (no
  spacecraft) are not the spacecraft's. Served by the table's `(mission, spacecraft scope, point)`
  unique index, so the read is the spacecraft's rows, not the mission's.
  """

  import Ecto.Query

  alias Cadence.Limits.Event
  alias Cadence.Limits.Store.LatestStateRow
  alias Cadence.Repo

  @type state :: %{event: Event.t(), evaluated_at: DateTime.t()}

  @spec list(binary(), binary(), binary()) :: [state()]
  def list(organization_id, mission_id, spacecraft_id) do
    from(row in LatestStateRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.spacecraft_scope_id == ^spacecraft_id and not is_nil(row.spacecraft_id)
    )
    |> Repo.all()
    |> Enum.map(&%{event: LatestStateRow.to_domain(&1), evaluated_at: &1.updated_at})
  end
end
