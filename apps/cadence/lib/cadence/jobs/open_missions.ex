defmodule Cadence.Jobs.OpenMissions do
  @moduledoc "Which missions have a job of one type queued or running, across all missions."

  import Ecto.Query

  alias Cadence.Jobs.{BackgroundJobRow, Job}
  alias Cadence.Repo

  @doc "The missions with a job of this type queued or running (one query)."
  @spec of_type(Job.job_type()) :: MapSet.t(binary())
  def of_type(job_type) when is_atom(job_type) do
    BackgroundJobRow
    |> where(
      [row],
      row.job_type == ^Atom.to_string(job_type) and row.status in ["queued", "running"]
    )
    |> select([row], row.mission_id)
    |> distinct(true)
    |> Repo.all()
    |> MapSet.new()
  end
end
