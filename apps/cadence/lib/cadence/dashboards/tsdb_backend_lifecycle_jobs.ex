defmodule Cadence.Dashboards.TSDBBackendLifecycleJobs do
  @moduledoc """
  Durable worker boundary for dedicated dashboard TSDB backend lifecycle work.

  Job payloads are redacted descriptors. Physical provisioning/deprovisioning
  adapters are runtime configuration, not durable data.
  """

  alias Cadence.Dashboards.{DataSource, TSDBDeploymentStatus}
  alias Cadence.Ids
  alias Cadence.Jobs
  alias Cadence.Jobs.Job
  alias Cadence.Management.ManagedResources

  @job_type :dashboard_tsdb_backend_lifecycle

  @durable_attrs [
    :operation,
    :data_source_id,
    :organization_id,
    :mission_id,
    :isolation_level,
    :physical_boundary,
    :storage,
    :backend,
    :endpoint_ref,
    :topology_ref,
    :actor_id
  ]

  @type enqueue_result :: {:ok, Job.t()} | {:error, term()}
  @type run_result :: {:ok, map()} | {:error, term()}

  @spec request_provisioning(binary(), map(), keyword()) ::
          {:ok, DataSource.t(), Job.t()} | {:error, term()}
  def request_provisioning(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    with {:ok, request} <-
           ManagedResources.request_tsdb_backend(data_source_id, :provision, attrs, opts),
         %DataSource{} = source <- request.data_source,
         {:ok, %Job{} = job} <- enqueue_for_source(source, :provision, attrs, opts) do
      {:ok, source, job}
    end
  end

  @spec request_deprovisioning(binary(), map(), keyword()) ::
          {:ok, DataSource.t(), Job.t()} | {:error, term()}
  def request_deprovisioning(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    with {:ok, request} <-
           ManagedResources.request_tsdb_backend(data_source_id, :deprovision, attrs, opts),
         %DataSource{} = source <- request.data_source,
         {:ok, %Job{} = job} <- enqueue_for_source(source, :deprovision, attrs, opts) do
      {:ok, source, job}
    end
  end

  @spec enqueue_for_source(DataSource.t(), atom(), map(), keyword()) :: enqueue_result()
  def enqueue_for_source(%DataSource{} = source, operation, attrs \\ %{}, opts \\ [])
      when is_atom(operation) and is_map(attrs) and is_list(opts) do
    with {:ok, mission_id} <- mission_id(source) do
      Jobs.enqueue(
        @job_type,
        mission_id,
        run_id(operation, source, attrs, opts),
        payload(source, operation, opts)
      )
    end
  end

  @spec execute_enqueued_run(binary()) :: run_result()
  def execute_enqueued_run(run_id) when is_binary(run_id) do
    with {:ok, %Job{job_type: @job_type} = job} <- Jobs.fetch_job_for_run(@job_type, run_id),
         {:ok, executor_result} <- lifecycle_executor().(job.payload, execution_opts()),
         {:ok, %DataSource{} = source} <- complete_job_lifecycle(job, executor_result) do
      {:ok,
       %{
         data_source_id: source.data_source_id,
         operation: payload_value(job.payload, :operation),
         executor_result: executor_result
       }}
    end
  end

  @spec list_for_mission(binary(), keyword()) :: [map()]
  def list_for_mission(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    @job_type
    |> Jobs.list_jobs(mission_id, opts)
    |> Enum.map(&from_job/1)
  end

  @spec retry_failed(binary()) :: {:ok, map()} | {:error, term()}
  def retry_failed(job_id) when is_binary(job_id) do
    with {:ok, %Job{job_type: @job_type}} <- Jobs.fetch_job(job_id),
         {:ok, %Job{} = retried_job} <- Jobs.retry_failed_job(job_id) do
      {:ok, from_job(retried_job)}
    else
      {:ok, %Job{} = job} ->
        {:error, {:unsupported_tsdb_backend_lifecycle_job, job.job_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec requeue_running(binary(), term()) :: {:ok, map()} | {:error, term()}
  def requeue_running(job_id, reason \\ :tsdb_backend_lifecycle_requeued)
      when is_binary(job_id) do
    with {:ok, %Job{job_type: @job_type}} <- Jobs.fetch_job(job_id),
         {:ok, %Job{} = requeued_job} <- Jobs.requeue_running_job(job_id, reason) do
      {:ok, from_job(requeued_job)}
    else
      {:ok, %Job{} = job} ->
        {:error, {:unsupported_tsdb_backend_lifecycle_job, job.job_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec from_job(Job.t()) :: map()
  def from_job(%Job{job_type: @job_type} = job) do
    deployment_status = TSDBDeploymentStatus.from_job(job)

    %{
      job: job,
      job_id: job.job_id,
      run_id: job.run_id,
      data_source_id: text(payload_value(job.payload, :data_source_id)),
      organization_id: text_or_nil(payload_value(job.payload, :organization_id)),
      mission_id: job.mission_id,
      status: deployment_status.status,
      status_text: deployment_status.status_text,
      mode_text: deployment_status.mode_text,
      backend_text: deployment_status.backend_text,
      physical_boundary_text: deployment_status.physical_boundary_text,
      attempt_count: job.attempt_count,
      failure_summary: failure_summary(job.failure_reason),
      started_at: job.started_at,
      completed_at: job.completed_at,
      remediation: deployment_status.remediation
    }
  end

  def from_job(%Job{} = job),
    do: raise(ArgumentError, "unsupported lifecycle job #{job.job_type}")

  @spec job_type() :: atom()
  def job_type, do: @job_type

  defp complete_job_lifecycle(%Job{} = job, executor_result) do
    case payload_value(job.payload, :operation) do
      "provision" ->
        ManagedResources.complete_tsdb_backend(
          text(payload_value(job.payload, :data_source_id)),
          :provision,
          %{
            job_id: job.job_id,
            run_id: job.run_id,
            executor_result: normalize_executor_result(executor_result)
          },
          actor_id: "dashboard_tsdb_backend_lifecycle_worker",
          payload: %{
            source: "dashboard_tsdb_backend_lifecycle_worker",
            job_id: job.job_id,
            run_id: job.run_id,
            operation: "complete_tsdb_backend_provisioning"
          }
        )

      "deprovision" ->
        ManagedResources.complete_tsdb_backend(
          text(payload_value(job.payload, :data_source_id)),
          :deprovision,
          %{
            job_id: job.job_id,
            run_id: job.run_id,
            executor_result: normalize_executor_result(executor_result)
          },
          actor_id: "dashboard_tsdb_backend_lifecycle_worker",
          payload: %{
            source: "dashboard_tsdb_backend_lifecycle_worker",
            job_id: job.job_id,
            run_id: job.run_id,
            operation: "complete_tsdb_backend_deprovisioning"
          }
        )

      operation ->
        {:error, {:unsupported_tsdb_backend_lifecycle_operation, operation}}
    end
  end

  defp mission_id(%DataSource{mission_id: mission_id})
       when is_binary(mission_id) and mission_id != "",
       do: {:ok, mission_id}

  defp mission_id(%DataSource{}),
    do: {:error, {:required_tsdb_lifecycle_job_field_missing, :mission_id}}

  defp run_id(operation, %DataSource{} = source, attrs, opts) do
    Keyword.get(opts, :run_id) ||
      get_attr(attrs, :run_id) ||
      Ids.new("dashboard_tsdb_backend_#{operation}_#{source.data_source_id}")
  end

  defp payload(%DataSource{} = source, operation, opts) do
    profile = DataSource.isolation_profile(source)

    %{
      operation: operation,
      data_source_id: source.data_source_id,
      organization_id: source.organization_id,
      mission_id: source.mission_id,
      isolation_level: source.isolation_level,
      physical_boundary: Map.get(profile, :physical_boundary),
      storage: Map.get(profile, :storage),
      backend: Map.get(profile, :storage),
      endpoint_ref: Map.get(profile, :endpoint_ref),
      topology_ref: Map.get(profile, :topology_ref),
      actor_id: Keyword.get(opts, :actor_id)
    }
    |> Map.take(@durable_attrs)
    |> Map.new(fn {key, value} -> {to_string(key), text_or_nil(value)} end)
    |> Map.put("provisioning_kind", "byo_tsdb")
    |> Map.put("redacted_fields", [])
  end

  defp lifecycle_executor do
    :cadence
    |> Application.get_env(:dashboard_tsdb_backend_lifecycle, [])
    |> Keyword.get(:executor, &missing_lifecycle_executor/2)
  end

  defp execution_opts do
    :cadence
    |> Application.get_env(:dashboard_tsdb_backend_lifecycle, [])
    |> Keyword.get(:execution_opts, [])
  end

  defp missing_lifecycle_executor(_payload, _opts),
    do: {:error, :dashboard_tsdb_backend_lifecycle_executor_not_configured}

  defp failure_summary(nil), do: "none"
  defp failure_summary(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp failure_summary(reason) when is_binary(reason), do: reason
  defp failure_summary(%{"reason" => reason}), do: failure_summary(reason)
  defp failure_summary(%{reason: reason}), do: failure_summary(reason)
  defp failure_summary(%{"tuple" => [reason | _details]}), do: failure_summary(reason)
  defp failure_summary(%{tuple: [reason | _details]}), do: failure_summary(reason)
  defp failure_summary(%{}), do: "failed"
  defp failure_summary(_reason), do: "failed"

  defp payload_value(payload, key) when is_map(payload) and is_atom(key) do
    Map.get(payload, key, Map.get(payload, Atom.to_string(key)))
  end

  defp payload_value(_payload, _key), do: nil

  defp normalize_executor_result(result) when is_map(result), do: result

  defp normalize_executor_result(result) when is_atom(result),
    do: %{"status" => Atom.to_string(result)}

  defp normalize_executor_result(result) when is_binary(result), do: %{"status" => result}
  defp normalize_executor_result(_result), do: %{"status" => "completed"}

  defp get_attr(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(_value), do: "unknown"

  defp text_or_nil(value) when is_binary(value) and value != "", do: value
  defp text_or_nil(value) when is_atom(value), do: Atom.to_string(value)
  defp text_or_nil(value) when is_integer(value), do: to_string(value)
  defp text_or_nil(_value), do: nil
end
