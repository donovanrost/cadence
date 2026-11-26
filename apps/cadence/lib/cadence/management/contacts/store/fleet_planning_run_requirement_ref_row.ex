defmodule Cadence.Management.Contacts.Store.FleetPlanningRunRequirementRefRow do
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
    field(:input_content_sha256, :string)
    field(:contact_planning_run_id, :string)
    field(:input_state, :string)
    field(:result_state, :string)
    field(:explanation_document, :map, default: %{})

    timestamps()
  end

  @doc "Serializes a normalized, timestamped requirement reference for bulk insertion."
  @spec insert_attrs(FleetPlanningRunRequirementRef.t()) :: map()
  def insert_attrs(%FleetPlanningRunRequirementRef{} = ref) do
    unless Regex.match?(~r/\A[0-9a-f]{64}\z/, ref.input_content_sha256) do
      raise ArgumentError, "fleet requirement reference needs a SHA-256 content hash"
    end

    %{
      fleet_planning_run_requirement_ref_id: ref.fleet_planning_run_requirement_ref_id,
      fleet_planning_run_id: ref.fleet_planning_run_id,
      organization_id: ref.organization_id,
      mission_id: ref.mission_id,
      contact_requirement_id: ref.contact_requirement_id,
      contact_requirement_version: ref.contact_requirement_version,
      input_content_sha256: ref.input_content_sha256,
      contact_planning_run_id: ref.contact_planning_run_id,
      input_state: Atom.to_string(ref.input_state),
      result_state: Atom.to_string(ref.result_state),
      explanation_document: JsonDocument.wrap_value(ref.explanation_document),
      inserted_at: ref.inserted_at,
      updated_at: ref.updated_at
    }
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
      input_content_sha256: row.input_content_sha256,
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
end
