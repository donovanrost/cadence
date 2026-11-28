defmodule Cadence.MissionModels.RuntimePlanRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.MissionModel.RuntimePlan
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  # A row is one revision's plan for one target (the key); the plan id names the plan's content
  # and repeats across revisions that leave it alone (#443).
  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_model_runtime_plans" do
    field(:plan_id, :string)
    field(:revision_id, :string, primary_key: true)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:target, :string, primary_key: true)
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
    |> unique_constraint([:revision_id, :target], name: :mission_model_runtime_plans_pkey)
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
