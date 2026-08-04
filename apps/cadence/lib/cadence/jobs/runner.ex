defmodule Cadence.Jobs.Runner do
  @moduledoc """
  Composition-boundary router for durable jobs.

  The platform-owned `Cadence.Jobs` queue has no domain dependencies. This
  runner is started by the jobs worker and is the one explicit place that maps
  a durable job type to the public API owned by the executing context.
  """

  alias Cadence.Jobs
  alias Cadence.Jobs.Job

  @spec run_job(binary()) :: {:ok, Job.t()} | {:error, term()}
  def run_job(job_id) when is_binary(job_id) do
    case Jobs.fetch_job(job_id) do
      {:ok, %Job{status: :running} = job} ->
        Jobs.record_execution_result(job, safe_dispatch(job))

      {:ok, %Job{} = job} ->
        Jobs.record_execution_result(job, {:error, {:job_not_running, job.status}})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch(%Job{job_type: job_type, run_id: run_id}) do
    case Map.fetch(job_handlers(), job_type) do
      {:ok, {module, function}} when is_atom(module) and is_atom(function) ->
        apply(module, function, [run_id])

      :error ->
        {:error, {:job_handler_not_configured, job_type}}

      {:ok, invalid_handler} ->
        {:error, {:invalid_job_handler, job_type, invalid_handler}}
    end
  end

  defp job_handlers, do: Application.get_env(:cadence, :job_handlers, %{})

  defp safe_dispatch(%Job{} = job) do
    dispatch(job)
  rescue
    exception ->
      {:error, {:exception, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end
end
