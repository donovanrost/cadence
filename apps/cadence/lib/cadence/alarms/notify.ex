defmodule Cadence.Alarms.Notify do
  @moduledoc """
  After-commit read invalidation for alarm episodes: `ScopedReadUpdates` `:alarms_changed`
  (organization, mission), published once per changed mission.
  """

  import Ecto.Query

  alias Cadence.Alarms.EpisodeRow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @doc "Publishes for every mission id given (duplicates collapse)."
  @spec missions_changed([String.t()]) :: :ok
  def missions_changed(mission_ids) do
    mission_ids
    |> Enum.uniq()
    |> Enum.each(fn mission_id ->
      case organization_id(mission_id) do
        nil -> :ok
        organization_id -> ScopedReadUpdates.publish(:alarms_changed, organization_id, mission_id)
      end
    end)
  end

  @spec subscribe(String.t(), String.t()) :: :ok | {:error, term()}
  def subscribe(organization_id, mission_id),
    do: ScopedReadUpdates.subscribe(:alarms_changed, organization_id, mission_id)

  defp organization_id(mission_id) do
    EpisodeRow
    |> where([e], e.mission_id == ^mission_id)
    |> select([e], e.organization_id)
    |> limit(1)
    |> Repo.one()
  end
end
