defmodule Cadence.Jobs.Runner do
  @moduledoc """
  Composition-boundary router for durable jobs.

  The platform-owned `Cadence.Jobs` queue has no domain dependencies. This
  runner is started by the jobs worker and is the one explicit place that maps
  a durable job type to the public API owned by the executing context.
  """

  alias Cadence.Jobs
  alias Cadence.Jobs.Job

  @default_handlers Application.compile_env(:cadence, :job_handlers, %{})

  @type handler :: {module(), atom()} | (binary() -> {:ok, term()} | {:error, term()})
  @type handler_map :: %{optional(Job.job_type()) => handler()}
  @type t :: %__MODULE__{handlers: handler_map()}

  @enforce_keys [:handlers]
  defstruct [:handlers]

  @spec new(handler_map()) :: t()
  def new(handlers) when is_map(handlers), do: %__MODULE__{handlers: handlers}

  @doc false
  @spec default() :: t()
  def default, do: new(@default_handlers)

  @spec run_job(binary()) :: {:ok, Job.t()} | {:error, term()}
  def run_job(job_id) when is_binary(job_id) do
    run_job(default(), job_id)
  end

  @spec run_job(t(), binary()) :: {:ok, Job.t()} | {:error, term()}
  def run_job(%__MODULE__{} = runner, job_id) when is_binary(job_id) do
    case Jobs.fetch_job(job_id) do
      {:ok, %Job{status: :running} = job} ->
        Jobs.record_execution_result(job, safe_dispatch(runner, job))

      # Not ours to run (finished, requeued, or never claimed): record nothing, so its outcome
      # stays the one its run recorded.
      {:ok, %Job{} = job} ->
        {:error, {:job_not_running, job.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Whether a job of this type may run again after the node stopped while it was running. Only
  when its handler module says so (`rerun_safe?/1`, next to its reasoning); false otherwise,
  including for a new job type, a function handler or an unknown type (Jobs recovery, 11-14).
  """
  @spec rerun_safe?(t(), atom()) :: boolean()
  def rerun_safe?(%__MODULE__{handlers: handlers}, job_type) do
    case Map.fetch(handlers, job_type) do
      {:ok, {module, _function}} when is_atom(module) ->
        Code.ensure_loaded?(module) and function_exported?(module, :rerun_safe?, 1) and
          module.rerun_safe?(job_type) == true

      _other ->
        false
    end
  end

  @doc false
  @spec dispatch(t(), Job.t()) :: {:ok, term()} | {:error, term()}
  def dispatch(%__MODULE__{handlers: handlers}, %Job{job_type: job_type, run_id: run_id}) do
    case Map.fetch(handlers, job_type) do
      {:ok, {module, function}} when is_atom(module) and is_atom(function) ->
        apply(module, function, [run_id])

      {:ok, handler} when is_function(handler, 1) ->
        handler.(run_id)

      :error ->
        {:error, {:job_handler_not_configured, job_type}}

      {:ok, invalid_handler} ->
        {:error, {:invalid_job_handler, job_type, invalid_handler}}
    end
  end

  defp safe_dispatch(%__MODULE__{} = runner, %Job{} = job) do
    dispatch(runner, job)
  rescue
    exception ->
      {:error, {:exception, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end
end
