defmodule Cadence.Persistence.Schemas.DerivedTelemetryEvaluationRunRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.DerivedTelemetry.Run
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:derived_run_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "derived_telemetry_evaluation_runs" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:status, :string)
    field(:evaluated_sample_count, :integer)
    field(:emitted_sample_count, :integer)
    field(:definition_count, :integer)
    field(:failure_reason, :map)
    field(:metadata, :map, default: %{})
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :derived_run_id,
    :mission_id,
    :status,
    :evaluated_sample_count,
    :emitted_sample_count,
    :definition_count,
    :started_at
  ]

  @spec changeset(Run.t()) :: Ecto.Changeset.t()
  def changeset(%Run{} = run), do: changeset(%__MODULE__{}, run)

  @spec changeset(struct(), Run.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = run_row, %Run{} = run) do
    run_row
    |> cast(domain_attrs(run), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: Run.t()
  def to_domain(%__MODULE__{} = run_row) do
    %Run{
      derived_run_id: run_row.derived_run_id,
      mission_id: run_row.mission_id,
      status: String.to_existing_atom(run_row.status),
      evaluated_sample_count: run_row.evaluated_sample_count,
      emitted_sample_count: run_row.emitted_sample_count,
      definition_count: run_row.definition_count,
      failure_reason: JsonDocument.unwrap_value(run_row.failure_reason),
      started_at: run_row.started_at,
      completed_at: run_row.completed_at,
      metadata: run_row.metadata
    }
  end

  defp domain_attrs(%Run{} = run) do
    %{
      derived_run_id: run.derived_run_id,
      mission_id: run.mission_id,
      status: Atom.to_string(run.status),
      evaluated_sample_count: run.evaluated_sample_count,
      emitted_sample_count: run.emitted_sample_count,
      definition_count: run.definition_count,
      failure_reason: maybe_wrap_failure_reason(run.failure_reason),
      metadata: JsonDocument.encode(run.metadata),
      started_at: run.started_at,
      completed_at: run.completed_at
    }
  end

  defp all_fields do
    [
      :derived_run_id,
      :mission_id,
      :status,
      :evaluated_sample_count,
      :emitted_sample_count,
      :definition_count,
      :failure_reason,
      :metadata,
      :started_at,
      :completed_at
    ]
  end

  defp maybe_wrap_failure_reason(nil), do: nil
  defp maybe_wrap_failure_reason(reason), do: JsonDocument.wrap_value(reason)
end
