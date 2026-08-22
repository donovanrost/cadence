defmodule Cadence.MissionModels.RuntimePlanRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.MissionModel.RuntimePlan
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:plan_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_model_runtime_plans" do
    field(:revision_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:target, :string)
    field(:target_contract_version, :string)
    field(:compiler_version, :string)
    field(:status, :string)
    field(:content_sha256, :string)
    field(:plan_document, :map)

    timestamps()
  end

  def changeset(revision, %RuntimePlan{} = plan) do
    attrs = %{
      plan_id: plan.plan_id,
      revision_id: revision.revision_id,
      organization_id: revision.organization_id,
      mission_id: revision.mission_id,
      target: Atom.to_string(plan.target),
      target_contract_version: plan.target_contract_version,
      compiler_version: plan.compiler_version,
      status: Atom.to_string(plan.status),
      content_sha256: plan.content_sha256,
      plan_document: JsonDocument.wrap_value(plan)
    }

    %__MODULE__{}
    |> cast(attrs, Map.keys(attrs))
    |> OrganizationScope.put_organization_id()
    |> validate_required(Map.keys(attrs) -- [:organization_id])
    |> unique_constraint([:revision_id, :target])
  end

  def to_domain(%__MODULE__{} = row) do
    row.plan_document
    |> JsonDocument.unwrap_value()
    |> Map.merge(%{
      "plan_id" => row.plan_id,
      "target" => row.target,
      "target_contract_version" => row.target_contract_version,
      "mission_model_revision_id" => row.revision_id,
      "compiler_version" => row.compiler_version,
      "status" => row.status,
      "content_sha256" => row.content_sha256
    })
    |> RuntimePlan.from_map()
  end
end
