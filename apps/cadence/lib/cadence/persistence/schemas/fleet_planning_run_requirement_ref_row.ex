defmodule Cadence.Persistence.Schemas.FleetPlanningRunRequirementRefRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.FleetPlanningRunRequirementRef
  alias Cadence.Persistence.JsonDocument

  @primary_key {:fleet_planning_run_requirement_ref_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "fleet_planning_run_requirement_refs" do
    field(:fleet_planning_run_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_requirement_id, :string)
    field(:contact_requirement_version, :integer)
    field(:contact_planning_run_id, :string)
    field(:input_state, :string)
    field(:result_state, :string)
    field(:explanation_document, :map, default: %{})

    timestamps()
  end

  @fields [
    :fleet_planning_run_requirement_ref_id,
    :fleet_planning_run_id,
    :organization_id,
    :mission_id,
    :contact_requirement_id,
    :contact_requirement_version,
    :contact_planning_run_id,
    :input_state,
    :result_state,
    :explanation_document
  ]

  @required_fields @fields -- [:contact_planning_run_id]

  @spec changeset(FleetPlanningRunRequirementRef.t()) :: Ecto.Changeset.t()
  def changeset(%FleetPlanningRunRequirementRef{} = ref) do
    %__MODULE__{}
    |> cast(domain_attrs(ref), @fields)
    |> validate_required(@required_fields)
    |> common_validations()
    |> unique_constraint(
      [:fleet_planning_run_id, :contact_requirement_id, :contact_requirement_version],
      name: :fleet_planning_run_requirement_refs_input_uniq
    )
  end

  @spec progress_changeset(struct(), map()) :: Ecto.Changeset.t()
  def progress_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [
      :contact_planning_run_id,
      :input_state,
      :result_state,
      :explanation_document
    ])
    |> validate_required([:input_state, :result_state, :explanation_document])
    |> common_validations()
  end

  @spec to_domain(struct()) :: FleetPlanningRunRequirementRef.t()
  def to_domain(%__MODULE__{} = row) do
    FleetPlanningRunRequirementRef.new(%{
      fleet_planning_run_requirement_ref_id: row.fleet_planning_run_requirement_ref_id,
      fleet_planning_run_id: row.fleet_planning_run_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      contact_requirement_id: row.contact_requirement_id,
      contact_requirement_version: row.contact_requirement_version,
      contact_planning_run_id: row.contact_planning_run_id,
      input_state: row.input_state,
      result_state: row.result_state,
      explanation_document: JsonDocument.unwrap_value(row.explanation_document),
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp common_validations(changeset) do
    changeset
    |> validate_number(:contact_requirement_version, greater_than: 0)
    |> validate_inclusion(:input_state, ~w(pending searching searched failed))
    |> validate_inclusion(:result_state, ~w(pending satisfied partial unsatisfied failed))
  end

  defp domain_attrs(ref) do
    %{
      fleet_planning_run_requirement_ref_id: ref.fleet_planning_run_requirement_ref_id,
      fleet_planning_run_id: ref.fleet_planning_run_id,
      organization_id: ref.organization_id,
      mission_id: ref.mission_id,
      contact_requirement_id: ref.contact_requirement_id,
      contact_requirement_version: ref.contact_requirement_version,
      contact_planning_run_id: ref.contact_planning_run_id,
      input_state: Atom.to_string(ref.input_state),
      result_state: Atom.to_string(ref.result_state),
      explanation_document: JsonDocument.wrap_value(ref.explanation_document)
    }
  end
end
