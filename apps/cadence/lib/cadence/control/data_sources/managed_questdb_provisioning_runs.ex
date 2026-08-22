defmodule Cadence.Control.DataSources.ManagedQuestDBProvisioningRuns do
  @moduledoc """
  Operator read model for managed QuestDB provisioning jobs.

  This projects durable background jobs into operator-facing deployment runs so
  queued/running/failed requests remain visible even before a data source row
  exists.
  """

  alias Cadence.DataSources.DeploymentStatus
  alias Cadence.Jobs
  alias Cadence.Jobs.Job

  @job_type :managed_questdb_provisioning

  @type t :: %{
          required(:job) => Job.t(),
          required(:job_id) => binary(),
          required(:run_id) => binary(),
          required(:data_source_id) => binary(),
          required(:organization_id) => binary() | nil,
          required(:mission_id) => binary(),
          required(:status) => DeploymentStatus.status(),
          required(:status_text) => binary(),
          required(:mode_text) => binary(),
          required(:backend_text) => binary(),
          required(:physical_boundary_text) => binary(),
          required(:attempt_count) => non_neg_integer(),
          required(:failure_summary) => binary(),
          required(:started_at) => DateTime.t() | nil,
          required(:completed_at) => DateTime.t() | nil,
          required(:remediation) => binary()
        }

  @spec list_for_mission(binary(), keyword()) :: [t()]
  def list_for_mission(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    @job_type
    |> Jobs.list_jobs(mission_id, opts)
    |> Enum.map(&from_job/1)
  end

  @spec retry_failed(binary()) :: {:ok, t()} | {:error, term()}
  def retry_failed(job_id) when is_binary(job_id) do
    with {:ok, %Job{job_type: @job_type}} <- Jobs.fetch_job(job_id),
         {:ok, %Job{} = retried_job} <- Jobs.retry_failed_job(job_id) do
      {:ok, from_job(retried_job)}
    else
      {:ok, %Job{} = job} ->
        {:error, {:unsupported_managed_questdb_provisioning_job, job.job_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec requeue_running(binary(), term()) :: {:ok, t()} | {:error, term()}
  def requeue_running(job_id, reason \\ :managed_questdb_provisioning_requeued)
      when is_binary(job_id) do
    with {:ok, %Job{job_type: @job_type}} <- Jobs.fetch_job(job_id),
         {:ok, %Job{} = requeued_job} <- Jobs.requeue_running_job(job_id, reason) do
      {:ok, from_job(requeued_job)}
    else
      {:ok, %Job{} = job} ->
        {:error, {:unsupported_managed_questdb_provisioning_job, job.job_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec from_job(Job.t()) :: t()
  def from_job(%Job{job_type: @job_type} = job) do
    deployment_status = DeploymentStatus.from_job(job)

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
    do: raise(ArgumentError, "unsupported provisioning job #{job.job_type}")

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

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(_value), do: "unknown"

  defp text_or_nil(value) when is_binary(value) and value != "", do: value
  defp text_or_nil(value) when is_atom(value), do: Atom.to_string(value)
  defp text_or_nil(_value), do: nil
end
