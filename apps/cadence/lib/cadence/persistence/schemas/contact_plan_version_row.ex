defmodule Cadence.Persistence.Schemas.ContactPlanVersionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactPlanVersion
  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_plan_version_id, :string, autogenerate: false}

  schema "contact_plan_versions" do
    field(:contact_plan_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:requirement_refs_document, :map)
    field(:planning_run_refs_document, :map)
    field(:selected_snapshot_ids, {:array, :string}, default: [])
    field(:locked_snapshot_ids, {:array, :string}, default: [])
    field(:rejected_snapshot_ids, {:array, :string}, default: [])
    field(:coverage_document, :map)
    field(:conflict_document, :map)
    field(:unsatisfied_document, :map)
    field(:policy_snapshot_document, :map)
    field(:rationale, :string)
    field(:content_sha256, :string)
    field(:created_by, :string)
    field(:created_at, :utc_datetime_usec)
  end

  @fields [
    :contact_plan_version_id,
    :contact_plan_id,
    :organization_id,
    :mission_id,
    :version,
    :requirement_refs_document,
    :planning_run_refs_document,
    :selected_snapshot_ids,
    :locked_snapshot_ids,
    :rejected_snapshot_ids,
    :coverage_document,
    :conflict_document,
    :unsatisfied_document,
    :policy_snapshot_document,
    :rationale,
    :content_sha256,
    :created_by,
    :created_at
  ]

  @spec changeset(ContactPlanVersion.t()) :: Ecto.Changeset.t()
  def changeset(%ContactPlanVersion{} = version) do
    %__MODULE__{}
    |> cast(domain_attrs(version), @fields)
    |> validate_required(@fields)
    |> validate_number(:version, greater_than: 0)
    |> validate_length(:rationale, max: 2_000)
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint(
      [:organization_id, :mission_id, :contact_plan_id, :version],
      name: :contact_plan_versions_scope_uniq
    )
    |> foreign_key_constraint(:contact_plan_id, name: :contact_plan_versions_plan_fk)
  end

  @spec to_domain(struct()) :: ContactPlanVersion.t()
  def to_domain(%__MODULE__{} = row) do
    ContactPlanVersion.new(%{
      contact_plan_version_id: row.contact_plan_version_id,
      contact_plan_id: row.contact_plan_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      requirement_refs_document: JsonDocument.unwrap_value(row.requirement_refs_document),
      planning_run_refs_document: JsonDocument.unwrap_value(row.planning_run_refs_document),
      selected_snapshot_ids: row.selected_snapshot_ids,
      locked_snapshot_ids: row.locked_snapshot_ids,
      rejected_snapshot_ids: row.rejected_snapshot_ids,
      coverage_document: JsonDocument.unwrap_value(row.coverage_document),
      conflict_document: JsonDocument.unwrap_value(row.conflict_document),
      unsatisfied_document: JsonDocument.unwrap_value(row.unsatisfied_document),
      policy_snapshot_document: JsonDocument.unwrap_value(row.policy_snapshot_document),
      rationale: row.rationale,
      content_sha256: row.content_sha256,
      created_by: row.created_by,
      created_at: row.created_at
    })
  end

  defp domain_attrs(version) do
    %{
      contact_plan_version_id: version.contact_plan_version_id,
      contact_plan_id: version.contact_plan_id,
      organization_id: version.organization_id,
      mission_id: version.mission_id,
      version: version.version,
      requirement_refs_document: JsonDocument.wrap_value(version.requirement_refs_document),
      planning_run_refs_document: JsonDocument.wrap_value(version.planning_run_refs_document),
      selected_snapshot_ids: version.selected_snapshot_ids,
      locked_snapshot_ids: version.locked_snapshot_ids,
      rejected_snapshot_ids: version.rejected_snapshot_ids,
      coverage_document: JsonDocument.wrap_value(version.coverage_document),
      conflict_document: JsonDocument.wrap_value(version.conflict_document),
      unsatisfied_document: JsonDocument.wrap_value(version.unsatisfied_document),
      policy_snapshot_document: JsonDocument.wrap_value(version.policy_snapshot_document),
      rationale: version.rationale,
      content_sha256: version.content_sha256,
      created_by: version.created_by,
      created_at: version.created_at
    }
  end
end
