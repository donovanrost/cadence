defmodule Cadence.Management.Contacts.Store.FleetPlanningDecisionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContentHash
  alias Cadence.ContactPlanning.FleetPlanningDecision
  alias Cadence.Management.Contacts.Store.FleetPlanningScoreDocumentRow
  alias Cadence.Persistence.JsonDocument

  @primary_key {:fleet_planning_decision_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "fleet_planning_decisions" do
    field(:fleet_planning_run_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_opportunity_snapshot_id, :string)
    field(:disposition, :string)
    field(:score, :integer)
    field(:rank, :integer)
    field(:hard_constraint_document, :map, default: %{})
    field(:score_document_sha256, :string)
    field(:explanation_document, :map, default: %{})

    belongs_to(:score_evidence, FleetPlanningScoreDocumentRow,
      type: :string,
      foreign_key: :score_document_sha256,
      references: :score_document_sha256,
      define_field: false
    )

    timestamps()
  end

  @fields [
    :fleet_planning_decision_id,
    :fleet_planning_run_id,
    :organization_id,
    :mission_id,
    :contact_opportunity_snapshot_id,
    :disposition,
    :score,
    :rank,
    :hard_constraint_document,
    :score_document_sha256,
    :explanation_document
  ]

  @required_fields @fields -- [:rank]

  @spec changeset(FleetPlanningDecision.t()) :: Ecto.Changeset.t()
  def changeset(%FleetPlanningDecision{} = decision) do
    %__MODULE__{}
    |> cast(domain_attrs(decision), @fields)
    |> validate_required(@required_fields)
    |> validate_optional_positive(:rank)
    |> validate_inclusion(:disposition, ~w(selected displaced ineligible locked))
    |> unique_constraint(
      [:fleet_planning_run_id, :contact_opportunity_snapshot_id],
      name: :fleet_planning_decisions_snapshot_uniq
    )
  end

  @spec to_domain(struct()) :: FleetPlanningDecision.t()
  def to_domain(%__MODULE__{score_evidence: %FleetPlanningScoreDocumentRow{} = evidence} = row) do
    FleetPlanningDecision.new(%{
      fleet_planning_decision_id: row.fleet_planning_decision_id,
      fleet_planning_run_id: row.fleet_planning_run_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      contact_opportunity_snapshot_id: row.contact_opportunity_snapshot_id,
      disposition: row.disposition,
      score: row.score,
      rank: row.rank,
      hard_constraint_document: JsonDocument.unwrap_value(row.hard_constraint_document),
      score_document: JsonDocument.unwrap_value(evidence.score_document),
      explanation_document: JsonDocument.unwrap_value(row.explanation_document),
      inserted_at: row.inserted_at
    })
  end

  @spec insert_attrs(FleetPlanningDecision.t(), binary()) :: map()
  def insert_attrs(%FleetPlanningDecision{} = decision, sha256) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    decision
    |> domain_attrs(sha256)
    |> Map.put(:inserted_at, now)
  end

  defp domain_attrs(decision),
    do: domain_attrs(decision, ContentHash.sha256(decision.score_document))

  defp domain_attrs(decision, sha256) do
    %{
      fleet_planning_decision_id: decision.fleet_planning_decision_id,
      fleet_planning_run_id: decision.fleet_planning_run_id,
      organization_id: decision.organization_id,
      mission_id: decision.mission_id,
      contact_opportunity_snapshot_id: decision.contact_opportunity_snapshot_id,
      disposition: Atom.to_string(decision.disposition),
      score: decision.score,
      rank: decision.rank,
      hard_constraint_document: JsonDocument.wrap_value(decision.hard_constraint_document),
      score_document_sha256: sha256,
      explanation_document: JsonDocument.wrap_value(decision.explanation_document)
    }
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end
end
