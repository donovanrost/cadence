defmodule Cadence.Jobs.BackgroundJobRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Jobs.Job
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:job_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "background_jobs" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:job_type, :string)
    field(:run_id, :string)
    field(:status, :string)
    field(:payload, :map, default: %{})
    field(:attempt_count, :integer)
    field(:failure_reason, :map)
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [:job_id, :mission_id, :job_type, :run_id, :status, :attempt_count]

  @spec changeset(Job.t()) :: Ecto.Changeset.t()
  def changeset(%Job{} = job) do
    changeset(%__MODULE__{}, job)
  end

  @spec changeset(struct(), Job.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = background_job_row, %Job{} = job) do
    background_job_row
    |> cast(domain_attrs(job), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: Job.t()
  def to_domain(%__MODULE__{} = background_job_row) do
    %Job{
      job_id: background_job_row.job_id,
      mission_id: background_job_row.mission_id,
      job_type: job_type(background_job_row.job_type),
      run_id: background_job_row.run_id,
      status: status(background_job_row.status),
      payload: JsonDocument.unwrap_value(background_job_row.payload),
      attempt_count: background_job_row.attempt_count,
      failure_reason: JsonDocument.unwrap_value(background_job_row.failure_reason),
      started_at: background_job_row.started_at,
      completed_at: background_job_row.completed_at
    }
  end

  defp domain_attrs(%Job{} = job) do
    %{
      job_id: job.job_id,
      mission_id: job.mission_id,
      job_type: Atom.to_string(job.job_type),
      run_id: job.run_id,
      status: Atom.to_string(job.status),
      payload: JsonDocument.wrap_value(job.payload),
      attempt_count: job.attempt_count,
      failure_reason: maybe_wrap_failure_reason(job.failure_reason),
      started_at: job.started_at,
      completed_at: job.completed_at
    }
  end

  defp all_fields do
    [
      :job_id,
      :mission_id,
      :job_type,
      :run_id,
      :status,
      :payload,
      :attempt_count,
      :failure_reason,
      :started_at,
      :completed_at
    ]
  end

  defp job_type("replay_telemetry_scope"), do: :replay_telemetry_scope
  defp job_type("telemetry_latest_value_rebuild"), do: :telemetry_latest_value_rebuild
  defp job_type("derived_telemetry_evaluation"), do: :derived_telemetry_evaluation

  defp job_type("derived_telemetry_latest_value_rebuild"),
    do: :derived_telemetry_latest_value_rebuild

  defp job_type("telemetry_limit_evaluation"), do: :telemetry_limit_evaluation
  defp job_type("telemetry_latest_limit_state_refresh"), do: :telemetry_latest_limit_state_refresh
  defp job_type("telemetry_latest_limit_state_rebuild"), do: :telemetry_latest_limit_state_rebuild
  defp job_type("mission_event_rebuild"), do: :mission_event_rebuild
  defp job_type("catalog_import_run"), do: :catalog_import_run
  defp job_type("telemetry_historical_data_workflow"), do: :telemetry_historical_data_workflow
  defp job_type("managed_questdb_provisioning"), do: :managed_questdb_provisioning
  defp job_type("dashboard_tsdb_backend_lifecycle"), do: :dashboard_tsdb_backend_lifecycle

  defp status("queued"), do: :queued
  defp status("running"), do: :running
  defp status("completed"), do: :completed
  defp status("failed"), do: :failed

  defp maybe_wrap_failure_reason(nil), do: nil
  defp maybe_wrap_failure_reason(reason), do: JsonDocument.wrap_value(reason)
end
