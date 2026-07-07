defmodule Cadence.Dashboards.TSDBDeploymentStatus do
  @moduledoc """
  Normalized deployment/provisioning status for dashboard TSDB backends.

  Persisted data sources describe a backend that already exists. Provisioning
  jobs describe a backend request that may still be queued, running, or failed
  before a `DataSource` can be registered.
  """

  alias Cadence.Dashboards.DataSource
  alias Cadence.Jobs.Job

  @type status :: :planned | :queued | :provisioning | :ready | :failed | :external | :unknown
  @type mode :: :managed_questdb | :byo_tsdb | :unknown
  @type backend :: :questdb | :unknown

  @type t :: %{
          required(:status) => status(),
          required(:status_text) => binary(),
          required(:mode) => mode(),
          required(:mode_text) => binary(),
          required(:backend) => backend(),
          required(:backend_text) => binary(),
          required(:physical_boundary) => DataSource.isolation_boundary() | :unknown,
          required(:physical_boundary_text) => binary(),
          required(:job_id) => binary() | nil,
          required(:run_id) => binary() | nil,
          required(:remediation) => binary()
        }

  @spec from_data_source(DataSource.t()) :: t()
  def from_data_source(%DataSource{} = data_source) do
    metadata = normalize_map(data_source.metadata)
    provisioning = normalize_map(value(metadata, :provisioning))
    isolation_profile = DataSource.isolation_profile(data_source)

    mode = deployment_mode(data_source, metadata, provisioning)
    status = deployment_status(data_source, metadata, provisioning, mode)
    backend = deployment_backend(metadata, provisioning)
    physical_boundary = physical_boundary(isolation_profile, provisioning)

    %{
      status: status,
      status_text: text(status),
      mode: mode,
      mode_text: text(mode),
      backend: backend,
      backend_text: text(backend),
      physical_boundary: physical_boundary,
      physical_boundary_text: text(physical_boundary),
      job_id: text_or_nil(value(provisioning, :job_id) || value(metadata, :deployment_job_id)),
      run_id: text_or_nil(value(provisioning, :run_id) || value(metadata, :provisioning_run_id)),
      remediation: remediation(status, mode)
    }
  end

  @spec from_job(Job.t()) :: t()
  def from_job(%Job{} = job) do
    payload = normalize_map(job.payload)
    mode = job_mode(job, payload)
    status = job_status(job.status)
    backend = job_backend(job, payload)
    physical_boundary = payload |> value(:isolation_level) |> physical_boundary_from_isolation()

    %{
      status: status,
      status_text: text(status),
      mode: mode,
      mode_text: text(mode),
      backend: backend,
      backend_text: text(backend),
      physical_boundary: physical_boundary,
      physical_boundary_text: text(physical_boundary),
      job_id: job.job_id,
      run_id: job.run_id,
      remediation: remediation(status, mode)
    }
  end

  defp deployment_mode(%DataSource{kind: :byo_tsdb}, _metadata, _provisioning), do: :byo_tsdb

  defp deployment_mode(_data_source, metadata, provisioning) do
    value(provisioning, :provisioner)
    |> fallback(value(metadata, :provisioning_mode))
    |> mode()
  end

  defp deployment_status(%DataSource{kind: :byo_tsdb}, _metadata, _provisioning, :byo_tsdb),
    do: :external

  defp deployment_status(_data_source, metadata, provisioning, mode) do
    explicit_status =
      value(provisioning, :deployment_status)
      |> fallback(value(metadata, :deployment_status))
      |> status()

    cond do
      explicit_status != :unknown -> explicit_status
      mode == :managed_questdb and value(provisioning, :applied_migration_count) != nil -> :ready
      mode == :managed_questdb -> :planned
      true -> :unknown
    end
  end

  defp deployment_backend(metadata, provisioning) do
    value(provisioning, :deployment_backend)
    |> fallback(value(provisioning, :storage))
    |> fallback(value(metadata, :physical_backend))
    |> fallback(value(metadata, :storage))
    |> backend()
  end

  defp physical_boundary(isolation_profile, provisioning) do
    value(provisioning, :physical_boundary)
    |> fallback(Map.get(isolation_profile, :physical_boundary))
    |> physical_boundary()
  end

  defp job_status(:queued), do: :queued
  defp job_status(:running), do: :provisioning
  defp job_status(:completed), do: :ready
  defp job_status(:failed), do: :failed
  defp job_status(_other), do: :unknown

  defp job_mode(%Job{job_type: :managed_questdb_provisioning}, _payload), do: :managed_questdb
  defp job_mode(_job, payload), do: payload |> value(:provisioning_kind) |> mode()

  defp job_backend(%Job{job_type: :managed_questdb_provisioning}, _payload), do: :questdb
  defp job_backend(_job, payload), do: payload |> value(:storage) |> backend()

  defp remediation(:planned, :managed_questdb), do: "enqueue_managed_questdb_provisioning"
  defp remediation(:queued, :managed_questdb), do: "wait_for_provisioning_worker"
  defp remediation(:provisioning, :managed_questdb), do: "monitor_schema_migration_job"
  defp remediation(:failed, :managed_questdb), do: "inspect_provisioning_job_and_retry"
  defp remediation(:ready, :managed_questdb), do: "probe_source_health"
  defp remediation(:external, :byo_tsdb), do: "monitor_customer_owned_backend"
  defp remediation(_status, _mode), do: "inspect_source_configuration"

  defp status(:planned), do: :planned
  defp status(:queued), do: :queued
  defp status(:provisioning), do: :provisioning
  defp status(:ready), do: :ready
  defp status(:failed), do: :failed
  defp status(:external), do: :external
  defp status("planned"), do: :planned
  defp status("queued"), do: :queued
  defp status("provisioning"), do: :provisioning
  defp status("ready"), do: :ready
  defp status("failed"), do: :failed
  defp status("external"), do: :external
  defp status(_other), do: :unknown

  defp mode(:managed_questdb), do: :managed_questdb
  defp mode(:byo_tsdb), do: :byo_tsdb
  defp mode("managed_questdb"), do: :managed_questdb
  defp mode("byo_tsdb"), do: :byo_tsdb
  defp mode(_other), do: :unknown

  defp backend(:questdb), do: :questdb
  defp backend("questdb"), do: :questdb
  defp backend(_other), do: :unknown

  defp physical_boundary(:shared), do: :shared
  defp physical_boundary(:organization), do: :organization
  defp physical_boundary(:mission), do: :mission
  defp physical_boundary(:customer_connection), do: :customer_connection
  defp physical_boundary("shared"), do: :shared
  defp physical_boundary("organization"), do: :organization
  defp physical_boundary("mission"), do: :mission
  defp physical_boundary("customer_connection"), do: :customer_connection
  defp physical_boundary(_other), do: :unknown

  defp physical_boundary_from_isolation(:org_isolated), do: :organization
  defp physical_boundary_from_isolation(:mission_isolated), do: :mission
  defp physical_boundary_from_isolation(:customer_owned), do: :customer_connection
  defp physical_boundary_from_isolation("org_isolated"), do: :organization
  defp physical_boundary_from_isolation("mission_isolated"), do: :mission
  defp physical_boundary_from_isolation("customer_owned"), do: :customer_connection
  defp physical_boundary_from_isolation(_other), do: :unknown

  defp value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp value(_other, _key), do: nil

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_other), do: %{}

  defp text_or_nil(value) when is_binary(value) and value != "", do: value
  defp text_or_nil(value) when is_atom(value), do: Atom.to_string(value)
  defp text_or_nil(_other), do: nil

  defp text(value) when is_atom(value), do: Atom.to_string(value)
end
