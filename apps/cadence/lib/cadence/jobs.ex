defmodule Cadence.Jobs do
  @moduledoc """
  Durable background job queue for Cadence runtime work.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Jobs.{Available, BackgroundJobRow, Job}
  alias Cadence.Repo

  @spec enqueue(Job.job_type(), binary(), binary(), map()) :: {:ok, Job.t()} | {:error, term()}
  def enqueue(job_type, mission_id, run_id, payload)
      when is_atom(job_type) and is_binary(mission_id) and is_binary(run_id) and is_map(payload) do
    with {:ok, job} <- insert_job(job_type, mission_id, run_id, payload) do
      Available.publish(job)
      {:ok, job}
    end
  end

  @doc "Stages a job with its domain intent; publish Jobs.Available only after the outer transaction commits."
  def enqueue_in_transaction(job_type, mission_id, run_id, payload) do
    if Repo.in_transaction?(),
      do: insert_job(job_type, mission_id, run_id, payload),
      else: raise(ArgumentError, "job staging requires an enclosing transaction")
  end

  defp insert_job(job_type, mission_id, run_id, payload) do
    job =
      Job.new(%{
        mission_id: mission_id,
        job_type: job_type,
        run_id: run_id,
        payload: payload
      })

    case Repo.insert(BackgroundJobRow.changeset(job)) do
      {:ok, %BackgroundJobRow{} = background_job_row} ->
        {:ok, BackgroundJobRow.to_domain(background_job_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_job(binary()) :: {:ok, Job.t()} | {:error, term()}
  def fetch_job(job_id) when is_binary(job_id) do
    case Repo.get(BackgroundJobRow, job_id) do
      nil ->
        {:error, :job_not_found}

      %BackgroundJobRow{} = background_job_row ->
        {:ok, BackgroundJobRow.to_domain(background_job_row)}
    end
  end

  @spec fetch_job_for_run(Job.job_type(), binary()) :: {:ok, Job.t()} | {:error, term()}
  def fetch_job_for_run(job_type, run_id) when is_atom(job_type) and is_binary(run_id) do
    case Repo.get_by(BackgroundJobRow, job_type: Atom.to_string(job_type), run_id: run_id) do
      nil ->
        {:error, :job_not_found}

      %BackgroundJobRow{} = background_job_row ->
        {:ok, BackgroundJobRow.to_domain(background_job_row)}
    end
  end

  @spec list_jobs(Job.job_type(), binary(), keyword()) :: [Job.t()]
  def list_jobs(job_type, mission_id, opts \\ [])
      when is_atom(job_type) and is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 25)

    BackgroundJobRow
    |> where(
      [background_job_row],
      background_job_row.job_type == ^Atom.to_string(job_type) and
        background_job_row.mission_id == ^mission_id
    )
    |> order_by([background_job_row],
      desc: background_job_row.inserted_at,
      desc: background_job_row.job_id
    )
    |> maybe_limit(limit)
    |> Repo.all()
    |> Enum.map(&BackgroundJobRow.to_domain/1)
  end

  @doc "Pages deployment jobs for the exact source before applying the display limit."
  def source_deployment_page(organization_id, mission_id, source_id, page)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(source_id) and
             is_integer(page) and page in 1..1_000_000 do
    rows =
      source_deployment_query(organization_id, mission_id, source_id)
      |> order_by([row], desc: row.inserted_at, desc: row.job_id)
      |> offset(^((page - 1) * 25))
      |> limit(26)
      |> Repo.all()

    %{
      entries: rows |> Enum.take(25) |> Enum.map(&BackgroundJobRow.to_domain/1),
      page: page,
      page_size: 25,
      has_next: length(rows) > 25
    }
  end

  defp source_deployment_query(organization_id, mission_id, source_id) do
    BackgroundJobRow
    |> where(
      [row],
      row.mission_id == ^mission_id and
        (is_nil(row.organization_id) or row.organization_id == ^organization_id) and
        row.job_type in ["managed_questdb_provisioning", "tsdb_backend_lifecycle"] and
        fragment("COALESCE(?->'value', ?) ->> 'data_source_id'", row.payload, row.payload) ==
          ^source_id
    )
    |> deployment_payload_scope("organization_id", organization_id)
    |> deployment_payload_scope("mission_id", mission_id)
  end

  defp deployment_payload_scope(query, key, value) do
    where(
      query,
      [row],
      is_nil(fragment("COALESCE(?->'value', ?) ->> ?", row.payload, row.payload, ^key)) or
        fragment("COALESCE(?->'value', ?) ->> ?", row.payload, row.payload, ^key) == ^value
    )
  end

  @spec retry_failed_job(binary()) :: {:ok, Job.t()} | {:error, term()}
  def retry_failed_job(job_id) when is_binary(job_id) do
    with {:ok, %Job{status: :failed} = job} <- fetch_job(job_id),
         {:ok, %Job{} = retried_job} <-
           update_job(%Job{
             job
             | status: :queued,
               failure_reason: nil,
               started_at: nil,
               completed_at: nil
           }) do
      Available.publish(retried_job)
      {:ok, retried_job}
    else
      {:ok, %Job{} = job} ->
        {:error, {:job_not_failed, job.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec requeue_running_job(binary(), term()) :: {:ok, Job.t()} | {:error, term()}
  def requeue_running_job(job_id, reason \\ :requeued_by_operator) when is_binary(job_id) do
    with {:ok, %Job{status: :running} = job} <- fetch_job(job_id),
         {:ok, %Job{} = requeued_job} <-
           update_job(%Job{
             job
             | status: :queued,
               failure_reason: requeue_reason(reason),
               started_at: nil,
               completed_at: nil
           }) do
      Available.publish(requeued_job)
      {:ok, requeued_job}
    else
      {:ok, %Job{} = job} ->
        {:error, {:job_not_running, job.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp requeue_reason(reason) when is_atom(reason), do: %{"reason" => Atom.to_string(reason)}
  defp requeue_reason(reason) when is_binary(reason), do: %{"reason" => reason}
  defp requeue_reason(reason) when is_map(reason), do: reason
  defp requeue_reason(reason), do: %{"reason" => inspect(reason)}

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _limit), do: query

  @spec claim_jobs(pos_integer()) :: [Job.t()]
  def claim_jobs(limit) when is_integer(limit) and limit > 0 do
    Repo.transaction(fn ->
      queued_rows =
        BackgroundJobRow
        |> where([background_job_row], background_job_row.status == "queued")
        |> order_by([background_job_row],
          asc: background_job_row.inserted_at,
          asc: background_job_row.job_id
        )
        |> limit(^limit)
        |> lock("FOR UPDATE SKIP LOCKED")
        |> Repo.all()

      Enum.map(queued_rows, fn %BackgroundJobRow{} = background_job_row ->
        claimed_job =
          background_job_row
          |> BackgroundJobRow.to_domain()
          |> mark_running()

        background_job_row
        |> BackgroundJobRow.changeset(claimed_job)
        |> Repo.update!()
        |> BackgroundJobRow.to_domain()
      end)
    end)
    |> case do
      {:ok, jobs} -> jobs
      {:error, _reason} -> []
    end
  end

  @doc false
  @spec record_execution_result(Job.t(), {:ok, term()} | {:error, term()}) ::
          {:ok, Job.t()} | {:error, term()}
  def record_execution_result(%Job{} = job, {:ok, _result}), do: complete_job(job)
  def record_execution_result(%Job{} = job, {:error, reason}), do: fail_job(job, reason)

  @spec requeue_running_jobs() :: non_neg_integer()
  def requeue_running_jobs do
    {count, _rows} =
      Repo.update_all(
        from(background_job_row in BackgroundJobRow,
          where: background_job_row.status == "running"
        ),
        set: [
          status: "queued",
          started_at: nil,
          failure_reason: %{"value" => %{"reason" => "requeued_after_restart"}}
        ]
      )

    count
  end

  @spec fail_worker_start(binary(), term()) :: {:ok, Job.t()} | {:error, term()}
  def fail_worker_start(job_id, reason) when is_binary(job_id) do
    with {:ok, %Job{} = job} <- fetch_job(job_id) do
      fail_job(job, {:worker_start_failed, reason})
    end
  end

  defp mark_running(%Job{} = job) do
    %Job{
      job
      | status: :running,
        attempt_count: job.attempt_count + 1,
        failure_reason: nil,
        started_at: DateTime.utc_now(),
        completed_at: nil
    }
  end

  defp complete_job(%Job{} = job) do
    update_job(%Job{job | status: :completed, completed_at: DateTime.utc_now()})
  end

  defp fail_job(%Job{} = job, reason) do
    update_job(%Job{
      job
      | status: :failed,
        failure_reason: reason,
        completed_at: DateTime.utc_now()
    })
  end

  defp update_job(%Job{} = job) do
    case Repo.get(BackgroundJobRow, job.job_id) do
      nil ->
        {:error, :job_not_found}

      %BackgroundJobRow{} = background_job_row ->
        case Repo.update(BackgroundJobRow.changeset(background_job_row, job)) do
          {:ok, %BackgroundJobRow{} = updated_row} ->
            {:ok, BackgroundJobRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
