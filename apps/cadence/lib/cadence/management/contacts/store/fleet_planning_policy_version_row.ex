defmodule Cadence.Management.Contacts.Store.FleetPlanningPolicyVersionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.FleetPlanningPolicyVersion
  alias Cadence.Persistence.JsonDocument

  @primary_key {:fleet_planning_policy_version_id, :string, autogenerate: false}

  schema "fleet_planning_policy_versions" do
    field(:fleet_planning_policy_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:horizon_document, :map)
    field(:scoring_document, :map)
    field(:resource_policy_document, :map)
    field(:budget_quota_document, :map)
    field(:redundancy_document, :map)
    field(:automation_repair_document, :map)
    field(:content_sha256, :string)
    field(:created_by, :string)
    field(:created_at, :utc_datetime_usec)
  end

  @fields [
    :fleet_planning_policy_version_id,
    :fleet_planning_policy_id,
    :organization_id,
    :mission_id,
    :version,
    :horizon_document,
    :scoring_document,
    :resource_policy_document,
    :budget_quota_document,
    :redundancy_document,
    :automation_repair_document,
    :content_sha256,
    :created_by,
    :created_at
  ]

  @spec changeset(FleetPlanningPolicyVersion.t()) :: Ecto.Changeset.t()
  def changeset(%FleetPlanningPolicyVersion{} = version) do
    %__MODULE__{}
    |> cast(domain_attrs(version), @fields)
    |> validate_required(@fields)
    |> validate_number(:version, greater_than: 0)
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint(
      [:organization_id, :mission_id, :fleet_planning_policy_id, :version],
      name: :fleet_planning_policy_versions_scope_uniq
    )
  end

  @spec to_domain(struct()) :: FleetPlanningPolicyVersion.t()
  def to_domain(%__MODULE__{} = row) do
    FleetPlanningPolicyVersion.new!(%{
      fleet_planning_policy_version_id: row.fleet_planning_policy_version_id,
      fleet_planning_policy_id: row.fleet_planning_policy_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      horizon_document: JsonDocument.unwrap_value(row.horizon_document),
      scoring_document: JsonDocument.unwrap_value(row.scoring_document),
      resource_policy_document: JsonDocument.unwrap_value(row.resource_policy_document),
      budget_quota_document: JsonDocument.unwrap_value(row.budget_quota_document),
      redundancy_document: JsonDocument.unwrap_value(row.redundancy_document),
      automation_repair_document: JsonDocument.unwrap_value(row.automation_repair_document),
      content_sha256: row.content_sha256,
      created_by: row.created_by,
      created_at: row.created_at
    })
  end

  defp domain_attrs(version) do
    %{
      fleet_planning_policy_version_id: version.fleet_planning_policy_version_id,
      fleet_planning_policy_id: version.fleet_planning_policy_id,
      organization_id: version.organization_id,
      mission_id: version.mission_id,
      version: version.version,
      horizon_document: JsonDocument.wrap_value(version.horizon_document),
      scoring_document: JsonDocument.wrap_value(version.scoring_document),
      resource_policy_document: JsonDocument.wrap_value(version.resource_policy_document),
      budget_quota_document: JsonDocument.wrap_value(version.budget_quota_document),
      redundancy_document: JsonDocument.wrap_value(version.redundancy_document),
      automation_repair_document: JsonDocument.wrap_value(version.automation_repair_document),
      content_sha256: version.content_sha256,
      created_by: version.created_by,
      created_at: version.created_at
    }
  end
end
