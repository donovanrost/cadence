defmodule Cadence.Management.Contacts.Store.ContactPlanOpportunityRefRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_plan_opportunity_ref_id, :string, autogenerate: false}

  schema "contact_plan_opportunity_refs" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_plan_id, :string)
    field(:contact_plan_version, :integer)
    field(:contact_opportunity_snapshot_id, :string)
    field(:disposition, :string)
    field(:selection_order, :integer)
    field(:reason_document, :map, default: %{})
  end

  @fields [
    :contact_plan_opportunity_ref_id,
    :organization_id,
    :mission_id,
    :contact_plan_id,
    :contact_plan_version,
    :contact_opportunity_snapshot_id,
    :disposition,
    :selection_order,
    :reason_document
  ]

  def changeset(attrs) when is_map(attrs) do
    attrs = Map.update(attrs, :reason_document, %{}, &JsonDocument.wrap_value/1)

    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:contact_plan_version, greater_than: 0)
    |> validate_number(:selection_order, greater_than_or_equal_to: 0)
    |> validate_inclusion(:disposition, ~w(selected locked rejected))
    |> unique_constraint(
      [:contact_plan_id, :contact_plan_version, :contact_opportunity_snapshot_id],
      name: :contact_plan_opportunity_refs_identity_idx
    )
    |> foreign_key_constraint(:contact_plan_version,
      name: :contact_plan_opportunity_refs_plan_version_fk
    )
    |> foreign_key_constraint(:contact_opportunity_snapshot_id,
      name: :contact_plan_opportunity_refs_snapshot_fk
    )
  end
end
