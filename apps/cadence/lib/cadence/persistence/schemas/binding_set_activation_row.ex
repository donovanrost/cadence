defmodule Cadence.Persistence.Schemas.BindingSetActivationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Persistence.JsonDocument

  @primary_key {:activation_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_binding_set_activations" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:metadata, :map, default: %{})
    field(:activated_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :activation_id,
    :mission_id,
    :binding_set_id,
    :binding_set_version,
    :metadata,
    :activated_at
  ]

  @spec changeset(BindingSetActivation.t()) :: Ecto.Changeset.t()
  def changeset(%BindingSetActivation{} = activation) do
    %__MODULE__{}
    |> cast(domain_attrs(activation), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: BindingSetActivation.t()
  def to_domain(%__MODULE__{} = activation_row) do
    %BindingSetActivation{
      activation_id: activation_row.activation_id,
      organization_id: activation_row.organization_id,
      mission_id: activation_row.mission_id,
      binding_set_id: activation_row.binding_set_id,
      binding_set_version: activation_row.binding_set_version,
      metadata: JsonDocument.unwrap_value(activation_row.metadata),
      activated_at: activation_row.activated_at
    }
  end

  defp domain_attrs(%BindingSetActivation{} = activation) do
    %{
      activation_id: activation.activation_id,
      organization_id: activation.organization_id,
      mission_id: activation.mission_id,
      binding_set_id: activation.binding_set_id,
      binding_set_version: activation.binding_set_version,
      metadata: JsonDocument.wrap_value(activation.metadata),
      activated_at: activation.activated_at
    }
  end

  defp all_fields do
    [
      :activation_id,
      :organization_id,
      :mission_id,
      :binding_set_id,
      :binding_set_version,
      :metadata,
      :activated_at
    ]
  end
end
