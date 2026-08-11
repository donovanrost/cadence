defmodule Cadence.Applications.PacketBindings.ResourceRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Applications.PacketBindingResource
  alias Cadence.Persistence.JsonDocument

  @primary_key {:packet_binding_resource_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "application_packet_binding_resources" do
    field(:packet_binding_id, :string)
    field(:resource_id, :string)
    field(:resource_kind, :string)
    field(:path, :string)
    field(:data_type, :string)
    field(:offset_bits, :integer)
    field(:size_bits, :integer)
    field(:role, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :packet_binding_resource_id,
    :packet_binding_id,
    :resource_id,
    :resource_kind,
    :path,
    :data_type,
    :offset_bits,
    :size_bits,
    :role,
    :metadata
  ]

  @required_fields [
    :packet_binding_resource_id,
    :packet_binding_id,
    :resource_id,
    :resource_kind,
    :role,
    :metadata
  ]

  @spec changeset(struct(), binary(), PacketBindingResource.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, packet_binding_id, %PacketBindingResource{} = resource) do
    row
    |> cast(domain_attrs(packet_binding_id, resource), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:resource_kind, ["whole_packet", "field", "binary_region"])
    |> validate_inclusion(:role, ["primary", "context"])
    |> validate_number(:offset_bits, greater_than_or_equal_to: 0)
    |> validate_number(:size_bits, greater_than: 0)
    |> unique_constraint([:packet_binding_id, :resource_id],
      name: :application_packet_binding_resources_identity_idx
    )
  end

  defp domain_attrs(packet_binding_id, %PacketBindingResource{} = resource) do
    %{
      packet_binding_resource_id: resource.packet_binding_resource_id,
      packet_binding_id: packet_binding_id,
      resource_id: resource.resource_id,
      resource_kind: Atom.to_string(resource.resource_kind),
      path: resource.path,
      data_type: resource.data_type && Atom.to_string(resource.data_type),
      offset_bits: resource.offset_bits,
      size_bits: resource.size_bits,
      role: Atom.to_string(resource.role),
      metadata: JsonDocument.wrap_value(resource.metadata)
    }
  end
end
