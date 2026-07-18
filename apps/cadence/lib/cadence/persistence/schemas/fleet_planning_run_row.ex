defmodule Cadence.Persistence.Schemas.FleetPlanningRunRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.FleetPlanningRun
  alias Cadence.Persistence.JsonDocument

  @primary_key {:fleet_planning_run_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "fleet_planning_runs" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:lifecycle_state, :string)
    field(:phase, :string)
    field(:trigger_kind, :string)
    field(:fleet_planning_policy_id, :string)
    field(:fleet_planning_policy_version, :integer)
    field(:algorithm_key, :string)
    field(:algorithm_version, :integer)
    field(:horizon_start, :utc_datetime_usec)
    field(:horizon_end, :utc_datetime_usec)
    field(:source_fleet_planning_run_id, :string)
    field(:source_contact_plan_id, :string)
    field(:source_contact_plan_version, :integer)
    field(:candidate_contact_plan_id, :string)
    field(:candidate_contact_plan_version, :integer)
    field(:input_document, :map, default: %{})
    field(:progress_document, :map, default: %{})
    field(:result_summary_document, :map, default: %{})
    field(:failure_document, :map, default: %{})
    field(:trigger_actor_document, :map, default: %{})
    field(:triggered_by, :string)
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps()
  end

  @fields [
    :fleet_planning_run_id,
    :organization_id,
    :mission_id,
    :lifecycle_state,
    :phase,
    :trigger_kind,
    :fleet_planning_policy_id,
    :fleet_planning_policy_version,
    :algorithm_key,
    :algorithm_version,
    :horizon_start,
    :horizon_end,
    :source_fleet_planning_run_id,
    :source_contact_plan_id,
    :source_contact_plan_version,
    :candidate_contact_plan_id,
    :candidate_contact_plan_version,
    :input_document,
    :progress_document,
    :result_summary_document,
    :failure_document,
    :trigger_actor_document,
    :triggered_by,
    :started_at,
    :completed_at
  ]

  @required_fields @fields --
                     [
                       :source_fleet_planning_run_id,
                       :source_contact_plan_id,
                       :source_contact_plan_version,
                       :candidate_contact_plan_id,
                       :candidate_contact_plan_version,
                       :started_at,
                       :completed_at
                     ]

  @spec changeset(FleetPlanningRun.t()) :: Ecto.Changeset.t()
  def changeset(%FleetPlanningRun{} = run) do
    %__MODULE__{}
    |> cast(domain_attrs(run), @fields)
    |> validate_required(@required_fields)
    |> common_validations()
    |> unique_constraint(:fleet_planning_run_id)
  end

  @spec projection_changeset(struct(), map()) :: Ecto.Changeset.t()
  def projection_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [
      :lifecycle_state,
      :phase,
      :candidate_contact_plan_id,
      :candidate_contact_plan_version,
      :progress_document,
      :result_summary_document,
      :failure_document,
      :started_at,
      :completed_at
    ])
    |> validate_required([
      :lifecycle_state,
      :phase,
      :progress_document,
      :result_summary_document,
      :failure_document
    ])
    |> common_validations()
  end

  @spec to_domain(struct()) :: FleetPlanningRun.t()
  def to_domain(%__MODULE__{} = row) do
    FleetPlanningRun.new(%{
      fleet_planning_run_id: row.fleet_planning_run_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      lifecycle_state: row.lifecycle_state,
      phase: row.phase,
      trigger_kind: row.trigger_kind,
      fleet_planning_policy_id: row.fleet_planning_policy_id,
      fleet_planning_policy_version: row.fleet_planning_policy_version,
      algorithm_key: row.algorithm_key,
      algorithm_version: row.algorithm_version,
      horizon_start: row.horizon_start,
      horizon_end: row.horizon_end,
      source_fleet_planning_run_id: row.source_fleet_planning_run_id,
      source_contact_plan_id: row.source_contact_plan_id,
      source_contact_plan_version: row.source_contact_plan_version,
      candidate_contact_plan_id: row.candidate_contact_plan_id,
      candidate_contact_plan_version: row.candidate_contact_plan_version,
      input_document: JsonDocument.unwrap_value(row.input_document),
      progress_document: JsonDocument.unwrap_value(row.progress_document),
      result_summary_document: JsonDocument.unwrap_value(row.result_summary_document),
      failure_document: JsonDocument.unwrap_value(row.failure_document),
      trigger_actor_document: JsonDocument.unwrap_value(row.trigger_actor_document),
      triggered_by: row.triggered_by,
      started_at: row.started_at,
      completed_at: row.completed_at,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp common_validations(changeset) do
    changeset
    |> validate_number(:fleet_planning_policy_version, greater_than: 0)
    |> validate_number(:algorithm_version, greater_than: 0)
    |> validate_optional_positive(:source_contact_plan_version)
    |> validate_optional_positive(:candidate_contact_plan_version)
    |> validate_inclusion(
      :lifecycle_state,
      ~w(queued running completed partial failed canceled)
    )
    |> validate_inclusion(
      :phase,
      ~w(queued materializing searching optimizing materializing_plan finished)
    )
    |> validate_inclusion(:trigger_kind, ~w(manual scheduled repair))
    |> validate_time_range()
    |> validate_paired_fields(:candidate_contact_plan_id, :candidate_contact_plan_version)
  end

  defp domain_attrs(run) do
    %{
      fleet_planning_run_id: run.fleet_planning_run_id,
      organization_id: run.organization_id,
      mission_id: run.mission_id,
      lifecycle_state: Atom.to_string(run.lifecycle_state),
      phase: Atom.to_string(run.phase),
      trigger_kind: Atom.to_string(run.trigger_kind),
      fleet_planning_policy_id: run.fleet_planning_policy_id,
      fleet_planning_policy_version: run.fleet_planning_policy_version,
      algorithm_key: run.algorithm_key,
      algorithm_version: run.algorithm_version,
      horizon_start: run.horizon_start,
      horizon_end: run.horizon_end,
      source_fleet_planning_run_id: run.source_fleet_planning_run_id,
      source_contact_plan_id: run.source_contact_plan_id,
      source_contact_plan_version: run.source_contact_plan_version,
      candidate_contact_plan_id: run.candidate_contact_plan_id,
      candidate_contact_plan_version: run.candidate_contact_plan_version,
      input_document: JsonDocument.wrap_value(run.input_document),
      progress_document: JsonDocument.wrap_value(run.progress_document),
      result_summary_document: JsonDocument.wrap_value(run.result_summary_document),
      failure_document: JsonDocument.wrap_value(run.failure_document),
      trigger_actor_document: JsonDocument.wrap_value(run.trigger_actor_document),
      triggered_by: run.triggered_by,
      started_at: run.started_at,
      completed_at: run.completed_at
    }
  end

  defp validate_time_range(changeset) do
    case {get_field(changeset, :horizon_start), get_field(changeset, :horizon_end)} do
      {%DateTime{} = starts_at, %DateTime{} = ends_at} ->
        if DateTime.before?(starts_at, ends_at),
          do: changeset,
          else: add_error(changeset, :horizon_end, "must be after horizon_start")

      _other ->
        changeset
    end
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end

  defp validate_paired_fields(changeset, left, right) do
    if is_nil(get_field(changeset, left)) == is_nil(get_field(changeset, right)),
      do: changeset,
      else: add_error(changeset, left, "must be set with #{right}")
  end
end
