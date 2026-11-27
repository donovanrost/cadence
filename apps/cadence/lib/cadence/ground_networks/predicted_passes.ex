defmodule Cadence.GroundNetworks.PredictedPasses do
  @moduledoc """
  Predicted passes (#891, slice 3 of #732; docs/pass-prediction-design.md, DECISIONS #114):
  stored rows of each spacecraft's passes over each located station, computed with SGP4 from the
  spacecraft's current element set and kept fresh by supervised jobs, never in a request.

  Every recompute is one durable `:pass_prediction` job (`Cadence.Jobs`) whose payload names the
  run, with the mission's `organization_id`:

  | `"kind"` | Payload | Enqueued by |
  | --- | --- | --- |
  | `"spacecraft"` | `"spacecraft_ids"` | `ElementSets.submit/4`, when a stored set becomes a spacecraft's current one |
  | `"station"` | `"ground_station_ids"` | `Cadence.Comms.StationGeometry`, when a station's location, mask or lifecycle changes |
  | `"full"` | | `enqueue_full/2` (seeds, admins) |
  | `"extend"`, `"prune"` | | `daily/1` (the maintenance process) |

  What each run does is `Cadence.GroundNetworks.PredictedPasses.Recompute`. Each finished run
  that changed rows publishes the `:predicted_passes_changed` read update once.
  """

  alias Cadence.GroundNetworks.PredictedPasses.{Read, Recompute, Settings, Store}
  alias Cadence.Ids
  alias Cadence.Jobs
  alias Cadence.Jobs.Available
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @job_type :pass_prediction
  @max_window_days 14
  @max_unfiltered_window_days 1
  @default_limit 200
  @max_limit 500

  @doc "Stages (in a transaction) or enqueues a recompute of these spacecraft."
  @spec stage_spacecraft(binary(), binary(), [binary()]) :: {:ok, Jobs.Job.t()} | {:error, term()}
  def stage_spacecraft(organization_id, mission_id, spacecraft_ids),
    do:
      stage(organization_id, mission_id, %{
        "kind" => "spacecraft",
        "spacecraft_ids" => spacecraft_ids
      })

  @doc "Enqueues a full recompute of the mission."
  @spec enqueue_full(binary(), binary()) :: {:ok, Jobs.Job.t()} | {:error, term()}
  def enqueue_full(organization_id, mission_id),
    do: stage(organization_id, mission_id, %{"kind" => "full"})

  defp stage(organization_id, mission_id, payload) do
    payload = Map.put(payload, "organization_id", organization_id)
    run_id = Ids.new("pass_prediction_run")

    if Repo.in_transaction?(),
      do: Jobs.enqueue_in_transaction(@job_type, mission_id, run_id, payload),
      else: Jobs.enqueue(@job_type, mission_id, run_id, payload)
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

  @doc "Runs one recompute now and publishes the read update when it changed rows."
  @spec run(binary(), binary(), Recompute.kind(), DateTime.t()) ::
          {:ok, Recompute.summary()} | {:error, term()}
  def run(organization_id, mission_id, kind, now \\ DateTime.utc_now()) do
    with {:ok, summary} <- Recompute.run(organization_id, mission_id, kind, now) do
      if summary.deleted + summary.inserted > 0,
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
  (opaque) and `limit` (1–500, default 200). A window must end after it starts and span at most
  14 days, or 1 day without a station or spacecraft filter.
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

    span = DateTime.diff(to, from, :second)

    if span > 0 and span <= max_days * 86_400,
      do: :ok,
      else: {:error, {:window_too_long, max_days}}
  end

  @doc "The longest horizon a mission may set, in days."
  defdelegate max_horizon_days, to: Settings
end
