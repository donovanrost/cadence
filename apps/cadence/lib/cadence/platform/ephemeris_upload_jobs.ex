defmodule Cadence.Platform.EphemerisUploadJobs do
  @moduledoc """
  Stages the durable `:ephemeris_upload` jobs (#968) that give each spacecraft's providers its
  current orbit (`Cadence.Control.Providers.EphemerisUploads` runs them). Staged with the pass-prediction
  job when an element set becomes current, and by the retry sweep for failed uploads. One job
  per batch of spacecraft, never one per spacecraft.

  Inside a transaction the job is staged with it (the dispatcher finds it once it commits);
  outside one it is enqueued. No ids, no job.
  """

  alias Cadence.Ids
  alias Cadence.Jobs
  alias Cadence.Repo

  @job_type :ephemeris_upload

  @spec stage_spacecraft(binary(), binary(), [binary()]) ::
          {:ok, Jobs.Job.t() | nil} | {:error, term()}
  def stage_spacecraft(_organization_id, _mission_id, []), do: {:ok, nil}

  def stage_spacecraft(organization_id, mission_id, spacecraft_ids) do
    payload = %{
      "organization_id" => organization_id,
      "spacecraft_ids" => Enum.uniq(spacecraft_ids)
    }

    run_id = Ids.new("ephemeris_upload_run")

    if Repo.in_transaction?(),
      do: Jobs.enqueue_in_transaction(@job_type, mission_id, run_id, payload),
      else: Jobs.enqueue(@job_type, mission_id, run_id, payload)
  end
end
