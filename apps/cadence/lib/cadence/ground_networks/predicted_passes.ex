defmodule Cadence.GroundNetworks.PredictedPasses do
  @moduledoc """
  Predicted passes (#891, slice 3 of #732; docs/pass-prediction-design.md, DECISIONS #114):
  stored rows of each spacecraft's passes over each located station, computed with SGP4 from the
  spacecraft's current element set and kept fresh by supervised jobs, never in a request.

  Every recompute is one durable `:pass_prediction` job (`Cadence.Jobs`) whose payload names the
  run, with the mission's `organization_id`:

  | `"kind"` | Payload | Enqueued by |
  | --- | --- | --- |
  | `"spacecraft"` | `"spacecraft_ids"` | `ElementSets.submit/4`, when a stored set becomes a spacecraft's current one; `SpacecraftStore.archive_spacecraft/4` |
  | `"station"` | `"ground_station_ids"` | `Cadence.Comms.StationGeometry`, when a station's location, mask or lifecycle changes |

  Other contexts stage these through `Cadence.Platform.PassPredictionJobs`.
  | `"full"` | | `enqueue_full/2` (seeds, admins) |
  | `"extend"`, `"prune"` | | `daily/1` (the maintenance process) |

  What each run does is `Cadence.GroundNetworks.PredictedPasses.Recompute`. Each finished run
  publishes the `:predicted_passes_changed` read update once (a prune only when it deleted rows).
  """

  alias Cadence.GroundNetworks.PredictedPasses.{Read, Recompute, Settings, Store}
  alias Cadence.Jobs
  alias Cadence.Jobs.Available
  alias Cadence.Platform.{PassPredictionJobs, ScopedReadUpdates}
  alias Cadence.Repo

  @job_type :pass_prediction
  @max_window_days 14
  @max_unfiltered_window_days 1
  @default_limit 200
  @max_limit 500

  @doc "Stages (in a transaction) or enqueues a recompute of these spacecraft."
  @spec stage_spacecraft(binary(), binary(), [binary()]) ::
          {:ok, Jobs.Job.t() | nil} | {:error, term()}
  defdelegate stage_spacecraft(organization_id, mission_id, spacecraft_ids),
    to: PassPredictionJobs

  @doc """
  Enqueues a full recompute of the mission, unless one is already queued or running: then it
  answers that job, so a repeat request never stages a second run.
  """
  @spec enqueue_full(binary(), binary()) :: {:ok, Jobs.Job.t()} | {:error, term()}
  def enqueue_full(organization_id, mission_id) do
    Repo.transaction(fn ->
      # Two requests at once must not both find no open run.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
        "predicted_passes_full:" <> mission_id
      ])

      case Enum.find(Jobs.list_open_jobs(@job_type, mission_id), &(&1.payload["kind"] == "full")) do
        nil -> {:staged, stage!(organization_id, mission_id)}
        open -> {:open, open}
      end
    end)
    |> case do
      {:ok, {:staged, job}} ->
        publish_staged(job)
        {:ok, job}

      {:ok, {:open, job}} ->
        {:ok, job}

      {:error, _reason} = error ->
        error
    end
  end

  defp stage!(organization_id, mission_id) do
    {:ok, job} = PassPredictionJobs.stage(organization_id, mission_id, %{"kind" => "full"})
    job
  end

  @doc "Wakes the dispatcher for a job staged in a transaction that has now committed."
  @spec publish_staged(Jobs.Job.t()) :: :ok
  def publish_staged(job) do
    Available.publish(job)
    :ok
  end

  @doc "Runs a durable `:pass_prediction` job (`Cadence.Jobs.Runner`)."
  @spec execute_enqueued_run(binary()) :: {:ok, Recompute.summary()} | {:error, term()}
  def execute_enqueued_run(run_id) do
    with {:ok, job} <- Jobs.fetch_job_for_run(@job_type, run_id),
         {:ok, kind} <- kind(job.payload) do
      run(job.payload["organization_id"], job.mission_id, kind)
    end
  end

  @doc "A recompute is idempotent: running it again recomputes the same rows."
  def rerun_safe?(@job_type), do: true
  def rerun_safe?(_job_type), do: false

  @doc """
  Runs one recompute now. Every finished recompute publishes the read update once, rows changed
  or not, so a client waiting on one sees it end; a prune publishes only when it deleted rows.
  """
  @spec run(binary(), binary(), Recompute.kind(), DateTime.t()) ::
          {:ok, Recompute.summary()} | {:error, term()}
  def run(organization_id, mission_id, kind, now \\ DateTime.utc_now()) do
    with {:ok, summary} <- Recompute.run(organization_id, mission_id, kind, now) do
      if summary.run != :prune or summary.deleted > 0,
        do: ScopedReadUpdates.publish(:predicted_passes_changed, organization_id, mission_id)

      {:ok, summary}
    end
  end

  defp kind(%{"kind" => "full"}), do: {:ok, :full}
  defp kind(%{"kind" => "extend"}), do: {:ok, :extend}
  defp kind(%{"kind" => "prune"}), do: {:ok, :prune}

  defp kind(%{"kind" => "spacecraft", "spacecraft_ids" => ids}) when is_list(ids),
    do: {:ok, {:spacecraft, ids}}

  defp kind(%{"kind" => "station", "ground_station_ids" => ids}) when is_list(ids),
    do: {:ok, {:stations, ids}}

  defp kind(_payload), do: {:error, :invalid_pass_prediction_payload}

  @doc """
  The daily runs for every mission that has predicted passes: one horizon extension and one
  prune per mission and UTC day (run ids are per day, so a second call the same day is a no-op).
  """
  @spec daily(DateTime.t()) :: :ok
  def daily(now \\ DateTime.utc_now()) do
    day = now |> DateTime.to_date() |> Date.to_iso8601()

    for state <- Store.states(), kind <- ["extend", "prune"] do
      run_id = "pass_prediction_#{kind}:#{state.mission_id}:#{day}"

      with {:error, :job_not_found} <- Jobs.fetch_job_for_run(@job_type, run_id) do
        Jobs.enqueue(@job_type, state.mission_id, run_id, %{
          "kind" => kind,
          "organization_id" => state.organization_id
        })
      end
    end

    :ok
  end

  @doc """
  A page of the mission's predicted passes overlapping `[from, to)`, with its coverage.
  `params`: `from`, `to` (`DateTime`, required), `station_id`, `spacecraft_id`, `cursor`
  (opaque) and `limit` (1–500, default 200). `to` must be after `from` (else an invalid `to`),
  and the window spans at most 14 days, or 1 day without a station or spacecraft filter.
  """
  @spec page(binary(), binary(), map()) ::
          {:ok, map()}
          | {:error, {:invalid_param, binary()}}
          | {:error, {:window_too_long, pos_integer()}}
  def page(organization_id, mission_id, params) do
    with {:ok, limit} <- limit(params[:limit]),
         {:ok, cursor} <- cursor(params[:cursor]),
         :ok <- window(params) do
      filters = %{
        from: params.from,
        to: params.to,
        station_id: params[:station_id],
        spacecraft_id: params[:spacecraft_id],
        cursor: cursor,
        limit: limit
      }

      {:ok, Read.page(organization_id, mission_id, filters)}
    end
  end

  defp limit(nil), do: {:ok, @default_limit}
  defp limit(limit) when is_integer(limit) and limit in 1..@max_limit, do: {:ok, limit}
  defp limit(_limit), do: {:error, {:invalid_param, "limit"}}

  defp cursor(cursor) do
    case Read.decode(cursor) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, {:invalid_param, "cursor"}}
    end
  end

  defp window(%{from: %DateTime{} = from, to: %DateTime{} = to} = params) do
    max_days =
      if params[:station_id] || params[:spacecraft_id],
        do: @max_window_days,
        else: @max_unfiltered_window_days

    span = DateTime.diff(to, from, :microsecond)

    cond do
      span <= 0 -> {:error, {:invalid_param, %{field: "to", reason: "must be after from"}}}
      span > max_days * 86_400_000_000 -> {:error, {:window_too_long, max_days}}
      true -> :ok
    end
  end

  @doc "The longest horizon a mission may set, in days."
  defdelegate max_horizon_days, to: Settings
end
