defmodule Cadence.Persistence.Schemas.ActiveBindingSetRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:mission_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_active_binding_sets" do
    field(:organization_id, :string)
    field(:activation_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:metadata, :map, default: %{})
    field(:activated_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :mission_id,
    :activation_id,
    :binding_set_id,
    :binding_set_version,
    :metadata,
    :activated_at
  ]

  @spec changeset(BindingSetActivation.t()) :: Ecto.Changeset.t()
  def changeset(%BindingSetActivation{} = activation) do
    %__MODULE__{}
    |> cast(domain_attrs(activation), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: BindingSetActivation.t()
  def to_domain(%__MODULE__{} = active_basis_row) do
    %BindingSetActivation{
      activation_id: active_basis_row.activation_id,
      organization_id: active_basis_row.organization_id,
      mission_id: active_basis_row.mission_id,
      binding_set_id: active_basis_row.binding_set_id,
      binding_set_version: active_basis_row.binding_set_version,
      metadata: JsonDocument.unwrap_value(active_basis_row.metadata),
      activated_at: active_basis_row.activated_at
    }
  end

  @spec metadata_document(map()) :: map()
  def metadata_document(metadata), do: JsonDocument.wrap_value(metadata)

  defp domain_attrs(%BindingSetActivation{} = activation) do
    %{
      organization_id: activation.organization_id,
      mission_id: activation.mission_id,
      activation_id: activation.activation_id,
      binding_set_id: activation.binding_set_id,
      binding_set_version: activation.binding_set_version,
      metadata: metadata_document(activation.metadata),
      activated_at: activation.activated_at
    }
  end

  defp all_fields do
    [
      :mission_id,
      :organization_id,
      :activation_id,
      :binding_set_id,
      :binding_set_version,
      :metadata,
      :activated_at
    ]
  end
end
