defmodule Cadence.Persistence.Schemas.ContactPlanRequirementRefRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:contact_plan_requirement_ref_id, :string, autogenerate: false}

  schema "contact_plan_requirement_refs" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_plan_id, :string)
    field(:contact_plan_version, :integer)
    field(:contact_requirement_id, :string)
    field(:contact_requirement_version, :integer)
  end

  @fields [
    :contact_plan_requirement_ref_id,
    :organization_id,
    :mission_id,
    :contact_plan_id,
    :contact_plan_version,
    :contact_requirement_id,
    :contact_requirement_version
  ]

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:contact_plan_version, greater_than: 0)
    |> validate_number(:contact_requirement_version, greater_than: 0)
    |> unique_constraint(
      [:contact_plan_id, :contact_plan_version, :contact_requirement_id],
      name: :contact_plan_requirement_refs_identity_idx
    )
    |> foreign_key_constraint(:contact_plan_version,
      name: :contact_plan_requirement_refs_plan_version_fk
    )
    |> foreign_key_constraint(:contact_requirement_version,
      name: :contact_plan_requirement_refs_requirement_version_fk
    )
  end
end
