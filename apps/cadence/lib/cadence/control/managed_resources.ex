defmodule Cadence.Control.ManagedResources do
  @moduledoc "Control-plane executor and recovery boundary for managed resources."

  alias Cadence.Dashboards.{
    ManagedQuestDBProvisioningJobs,
    ManagedQuestDBProvisioningRuns,
    TSDBBackendLifecycleJobs
  }

  alias Cadence.Management.ManagedResources
  alias Cadence.Management.ManagedResources.ManagedResourceRequest

  @spec request_tsdb_backend(binary(), ManagedResourceRequest.operation(), map(), keyword()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def request_tsdb_backend(data_source_id, operation, attrs \\ %{}, opts \\ []) do
    with {:ok, request} <-
           ManagedResources.request_tsdb_backend(data_source_id, operation, attrs, opts),
         accept_result <- accept(request, attrs, opts) do
      case accept_result do
        {:ok, job} ->
          {:ok, request.data_source, job}

        {:error, reason} ->
          {:error, {:managed_resource_requested_but_not_enqueued, request.request_id, reason}}
      end
    end
  end

  @spec accept(ManagedResourceRequest.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def accept(%ManagedResourceRequest{} = request, attrs \\ %{}, opts \\ []) do
    TSDBBackendLifecycleJobs.enqueue_for_source(
      request.data_source,
      request.operation,
      attrs,
      Keyword.put(opts, :run_id, request.request_id)
    )
  end

  @spec accept_requested_tsdb_backend(binary(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def accept_requested_tsdb_backend(data_source_id, attrs \\ %{}, opts \\ []) do
    with {:ok, request} <- ManagedResources.fetch_requested_tsdb_backend(data_source_id) do
      accept(request, attrs, opts)
    end
  end

  defdelegate list_managed_questdb_runs(mission_id, opts \\ []),
    to: ManagedQuestDBProvisioningRuns,
    as: :list_for_mission

  defdelegate list_tsdb_backend_runs(mission_id, opts \\ []),
    to: TSDBBackendLifecycleJobs,
    as: :list_for_mission

  def retry_deployment_run(job_id) do
    case ManagedQuestDBProvisioningRuns.retry_failed(job_id) do
      {:error, {:unsupported_managed_questdb_provisioning_job, _job_type}} ->
        TSDBBackendLifecycleJobs.retry_failed(job_id)

      result ->
        result
    end
  end

  def requeue_deployment_run(job_id) do
    case ManagedQuestDBProvisioningRuns.requeue_running(job_id) do
      {:error, {:unsupported_managed_questdb_provisioning_job, _job_type}} ->
        TSDBBackendLifecycleJobs.requeue_running(job_id)

      result ->
        result
    end
  end

  defdelegate enqueue_managed_questdb(attrs, opts \\ []),
    to: ManagedQuestDBProvisioningJobs,
    as: :enqueue
end
