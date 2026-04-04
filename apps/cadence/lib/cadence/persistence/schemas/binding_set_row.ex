defmodule Cadence.Persistence.Schemas.BindingSetRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Persistence.OrganizationScope

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "governed_binding_sets" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:binding_set_id, :string)
    field(:version, :integer)

    timestamps()
  end

  @required_fields [:mission_id, :binding_set_id, :version]

  @spec changeset(BindingSet.t()) :: Ecto.Changeset.t()
  def changeset(%BindingSet{} = binding_set) do
    %__MODULE__{}
    |> cast(
      %{
        organization_id: binding_set.organization_id,
        mission_id: binding_set.mission_id,
        binding_set_id: binding_set.binding_set_id,
        version: binding_set.version
      },
      all_fields()
    )
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :binding_set_id, :version],
      name: :governed_binding_sets_scope_idx
    )
  end

  defp all_fields do
    [:organization_id, :mission_id, :binding_set_id, :version]
  end
end
