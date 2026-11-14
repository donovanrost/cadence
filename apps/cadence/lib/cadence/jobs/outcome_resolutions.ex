defmodule Cadence.Jobs.OutcomeResolutions do
  @moduledoc """
  Jobs whose outcome is unknown because the node stopped while they ran (U54), and an operator's
  decision on each: retry it (the only way such a job runs again) or close it as it is.

  One item per run: `job_outcome_unknown:<job_id>:<attempt>`. A retried job that is cut off again
  raises a new item next to the resolved one. A decision is one insert keyed by that id, in the
  same transaction as the retry's requeue: of two operators at once, one wins and the other gets
  `:attention_item_not_open`, and the job is never queued twice.

  Only jobs recovery marked (`cause: node_stopped_while_running`) are items. The rows relabelled
  after the 11-14 jobs fix are outcome_unknown too, but the director ruled them not retryable.
  """

  import Ecto.Query

  alias Cadence.Jobs.{Available, BackgroundJobRow, Job, OutcomeResolutionRow}
  alias Cadence.Repo

  @prefix "job_outcome_unknown:"
  @cause "node_stopped_while_running"

  @spec item_id(Job.t()) :: binary()
  def item_id(%Job{job_id: job_id, attempt_count: attempt}),
    do: @prefix <> job_id <> ":" <> Integer.to_string(attempt)

  @spec parse_item_id(binary()) :: {:ok, {binary(), pos_integer()}} | :error
  def parse_item_id(@prefix <> rest) do
    with [job_id, attempt] <- String.split(rest, ":"),
         {attempt, ""} when attempt > 0 <- Integer.parse(attempt) do
      {:ok, {job_id, attempt}}
    else
      _other -> :error
    end
  end

  def parse_item_id(_id), do: :error

  @doc "The mission's open items: unknown-outcome runs nobody has decided on, oldest first."
  @spec open_jobs(binary()) :: [Job.t()]
  def open_jobs(mission_id) do
    from(job in unknown_runs(mission_id),
      left_join: decision in OutcomeResolutionRow,
      on: decision.job_id == job.job_id and decision.attempt == job.attempt_count,
      where: is_nil(decision.item_id),
      order_by: [asc: job.completed_at, asc: job.job_id]
    )
    |> Repo.all()
    |> Enum.map(&BackgroundJobRow.to_domain/1)
  end

  @doc "One open item's job, or `:attention_item_not_found` / `:attention_item_not_open`."
  @spec fetch_open(binary(), binary()) :: {:ok, Job.t()} | {:error, atom()}
  def fetch_open(mission_id, item_id) do
    with {:ok, {job_id, attempt}} <- parse(item_id),
         %BackgroundJobRow{} = row <- Repo.get(BackgroundJobRow, job_id),
         %Job{mission_id: ^mission_id, attempt_count: ^attempt} = job <-
           BackgroundJobRow.to_domain(row),
         true <- unknown_run?(job) || :not_open,
         nil <- Repo.get(OutcomeResolutionRow, item_id) do
      {:ok, job}
    else
      :not_open -> {:error, :attention_item_not_open}
      %OutcomeResolutionRow{} -> {:error, :attention_item_not_open}
      {:error, reason} -> {:error, reason}
      _missing -> {:error, :attention_item_not_found}
    end
  end

  @doc "Decisions recorded since `since`, newest first."
  @spec resolutions_since(binary(), DateTime.t()) :: [OutcomeResolutionRow.t()]
  def resolutions_since(mission_id, %DateTime{} = since) do
    from(row in OutcomeResolutionRow,
      where: row.mission_id == ^mission_id and row.resolved_at >= ^since,
      order_by: [desc: row.resolved_at]
    )
    |> Repo.all()
  end

  @doc """
  Records an operator's decision on an open item. `:retried` puts the job back in the queue in
  the same transaction; `:closed` leaves it as it is. `{:error, :attention_item_not_open}` when
  someone decided first.
  """
  @spec decide(Job.t(), :retried | :closed, map(), binary() | nil) ::
          {:ok, OutcomeResolutionRow.t()} | {:error, term()}
  def decide(%Job{} = job, action, actor, note) when action in [:retried, :closed] do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      attrs = %{
        item_id: item_id(job),
        job_id: job.job_id,
        attempt: job.attempt_count,
        mission_id: job.mission_id,
        job_type: Atom.to_string(job.job_type),
        action: Atom.to_string(action),
        actor: actor,
        note: note,
        resolved_at: now
      }

      with {:ok, row} <- insert(attrs),
           :ok <- maybe_requeue(action, job) do
        row
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> tap(fn
      {:ok, _row} when action == :retried -> publish_queued(job.job_id)
      _other -> :ok
    end)
  end

  defp insert(attrs) do
    case attrs |> OutcomeResolutionRow.changeset() |> Repo.insert() do
      {:ok, row} ->
        {:ok, row}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :item_id),
          do: {:error, :attention_item_not_open},
          else: {:error, changeset}
    end
  end

  defp maybe_requeue(:closed, _job), do: :ok

  defp maybe_requeue(:retried, %Job{job_id: job_id, attempt_count: attempt}) do
    {count, _rows} =
      Repo.update_all(
        from(row in BackgroundJobRow,
          where:
            row.job_id == ^job_id and row.status == "outcome_unknown" and
              row.attempt_count == ^attempt
        ),
        set: [
          status: "queued",
          started_at: nil,
          completed_at: nil,
          failure_reason: %{"value" => %{"reason" => "retried_by_operator"}}
        ]
      )

    if count == 1, do: :ok, else: {:error, :attention_item_not_open}
  end

  defp publish_queued(job_id) do
    case Repo.get(BackgroundJobRow, job_id) do
      %BackgroundJobRow{} = row -> row |> BackgroundJobRow.to_domain() |> Available.publish()
      nil -> :ok
    end
  end

  defp unknown_runs(mission_id) do
    from(job in BackgroundJobRow,
      where:
        job.mission_id == ^mission_id and job.status == "outcome_unknown" and
          fragment("?->'value'->>'cause' = ?", job.failure_reason, @cause)
    )
  end

  defp unknown_run?(%Job{status: :outcome_unknown, failure_reason: %{"cause" => @cause}}),
    do: true

  defp unknown_run?(_job), do: false

  defp parse(item_id) do
    case parse_item_id(item_id) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :attention_item_not_found}
    end
  end
end
