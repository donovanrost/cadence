defmodule Cadence.Applications.PacketBindings.BindingRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Applications.PacketBinding
  alias Cadence.Persistence.JsonDocument

  @primary_key {:packet_binding_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "application_packet_bindings" do
    field(:packet_binding_configuration_id, :string)
    field(:source_endpoint_ref, :string)
    field(:catalog_revision_id, :string)
    field(:mission_model_revision_id, :string)
    field(:packet_id, :string)
    field(:packet_model_content_sha256, :string)
    field(:packet_name, :string)
    field(:apid, :integer)
    field(:selector, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :packet_binding_id,
    :packet_binding_configuration_id,
    :source_endpoint_ref,
    :catalog_revision_id,
    :mission_model_revision_id,
    :packet_id,
    :packet_model_content_sha256,
    :packet_name,
    :apid,
    :selector,
    :metadata
  ]

  @required_fields [
    :packet_binding_id,
    :packet_binding_configuration_id,
    :packet_name,
    :apid,
    :selector,
    :metadata
  ]

  @spec changeset(struct(), binary(), PacketBinding.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, configuration_id, %PacketBinding{} = binding) do
    row
    |> cast(domain_attrs(configuration_id, binding), @fields)
    |> validate_required(@required_fields)
    |> validate_number(:apid, greater_than_or_equal_to: 0, less_than_or_equal_to: 2_047)
  end

  defp domain_attrs(configuration_id, %PacketBinding{} = binding) do
    %{
      packet_binding_id: binding.packet_binding_id,
      packet_binding_configuration_id: configuration_id,
      source_endpoint_ref: binding.source_endpoint_ref,
      catalog_revision_id: binding.catalog_revision_id,
      mission_model_revision_id: binding.mission_model_revision_id,
      packet_id: binding.packet_id,
      packet_model_content_sha256: binding.packet_model_content_sha256,
      packet_name: binding.packet_name,
      apid: binding.apid,
      selector: JsonDocument.wrap_value(binding.selector),
      metadata: JsonDocument.wrap_value(binding.metadata)
    }
  end
end
