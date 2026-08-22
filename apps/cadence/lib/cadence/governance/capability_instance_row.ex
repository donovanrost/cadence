defmodule Cadence.Governance.CapabilityInstanceRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ApplicationDispatch.CapabilityInstance

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "governed_capability_instances" do
    field(:binding_set_row_id, :id)
    field(:capability_instance_id, :string)
    field(:family_key, :string)
    field(:target_scope, :string)
    field(:source_endpoint_ref, :string)
    field(:lifecycle_state, :string)
    field(:capability_config_type, :string)
    field(:capability_config_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :binding_set_row_id,
    :capability_instance_id,
    :family_key,
    :target_scope,
    :lifecycle_state,
    :capability_config_type,
    :capability_config_document
  ]

  @spec changeset(pos_integer(), CapabilityInstance.t(), map()) :: Ecto.Changeset.t()
  def changeset(binding_set_row_id, %CapabilityInstance{} = capability_instance, config_attrs)
      when is_integer(binding_set_row_id) and is_map(config_attrs) do
    attrs =
      Map.merge(
        %{
          binding_set_row_id: binding_set_row_id,
          capability_instance_id: capability_instance.capability_instance_id,
          family_key: Atom.to_string(capability_instance.family_key),
          target_scope: Atom.to_string(capability_instance.target_scope),
          source_endpoint_ref: capability_instance.source_endpoint_ref,
          lifecycle_state: Atom.to_string(capability_instance.lifecycle_state)
        },
        config_attrs
      )

    %__MODULE__{}
    |> cast(attrs, all_fields())
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:binding_set_row_id)
    |> unique_constraint([:binding_set_row_id, :capability_instance_id],
      name: :governed_capability_instances_binding_set_instance_idx
    )
  end

  defp all_fields do
    [
      :binding_set_row_id,
      :capability_instance_id,
      :family_key,
      :target_scope,
      :source_endpoint_ref,
      :lifecycle_state,
      :capability_config_type,
      :capability_config_document
    ]
  end
end
