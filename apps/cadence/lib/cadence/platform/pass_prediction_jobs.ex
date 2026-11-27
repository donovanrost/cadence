defmodule Cadence.Platform.PassPredictionJobs do
  @moduledoc """
  Stages the durable `:pass_prediction` jobs (#891) for the contexts that change what pass
  prediction reads but may not depend on GroundNetworks, where the work runs
  (`Cadence.GroundNetworks.PredictedPasses`):

  - `"spacecraft"`: those spacecraft's passes from now on are recomputed; a spacecraft that is
    no longer active only loses them. Staged when an element set becomes current and when a
    spacecraft is archived.
  - `"station"`: likewise for stations. Staged when a station's location, mask or lifecycle
    changes.

  Inside a transaction the job is staged with it (the dispatcher finds it once it commits);
  outside one it is enqueued. No ids, no job.
  """

  alias Cadence.Ids
  alias Cadence.Jobs
  alias Cadence.Repo

  @job_type :pass_prediction

  @spec stage_spacecraft(binary(), binary(), [binary()]) ::
          {:ok, Jobs.Job.t() | nil} | {:error, term()}
  def stage_spacecraft(organization_id, mission_id, spacecraft_ids),
    do: stage(organization_id, mission_id, "spacecraft", "spacecraft_ids", spacecraft_ids)

  @spec stage_stations(binary(), binary(), [binary()]) ::
          {:ok, Jobs.Job.t() | nil} | {:error, term()}
  def stage_stations(organization_id, mission_id, station_ids),
    do: stage(organization_id, mission_id, "station", "ground_station_ids", station_ids)

  @doc "Stages or enqueues a job with this payload (`organization_id` is added)."
  @spec stage(binary(), binary(), map()) :: {:ok, Jobs.Job.t()} | {:error, term()}
  def stage(organization_id, mission_id, payload) do
    payload = Map.put(payload, "organization_id", organization_id)
    run_id = Ids.new("pass_prediction_run")

    if Repo.in_transaction?(),
      do: Jobs.enqueue_in_transaction(@job_type, mission_id, run_id, payload),
      else: Jobs.enqueue(@job_type, mission_id, run_id, payload)
  end

  defp stage(_organization_id, _mission_id, _kind, _key, []), do: {:ok, nil}

  defp stage(organization_id, mission_id, kind, key, ids),
    do: stage(organization_id, mission_id, %{"kind" => kind, key => Enum.uniq(ids)})
end
