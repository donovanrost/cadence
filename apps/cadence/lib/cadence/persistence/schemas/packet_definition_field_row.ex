defmodule Cadence.Persistence.Schemas.PacketDefinitionFieldRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Telemetry.FieldDefinition

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "governed_packet_definition_fields" do
    field(:packet_definition_row_id, :id)
    field(:field_id, :string)
    field(:name, :string)
    field(:offset_bits, :integer)
    field(:size_bits, :integer)
    field(:data_type, :string)
    field(:engineering_unit, :string)

    timestamps()
  end

  @required_fields [
    :packet_definition_row_id,
    :field_id,
    :name,
    :offset_bits,
    :size_bits,
    :data_type
  ]

  @spec changeset(pos_integer(), FieldDefinition.t()) :: Ecto.Changeset.t()
  def changeset(packet_definition_row_id, %FieldDefinition{} = field_definition)
      when is_integer(packet_definition_row_id) do
    %__MODULE__{}
    |> cast(
      %{
        packet_definition_row_id: packet_definition_row_id,
        field_id: field_definition.field_id,
        name: field_definition.name,
        offset_bits: field_definition.offset_bits,
        size_bits: field_definition.size_bits,
        data_type: Atom.to_string(field_definition.data_type),
        engineering_unit: field_definition.engineering_unit
      },
      all_fields()
    )
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:packet_definition_row_id)
    |> unique_constraint([:packet_definition_row_id, :field_id],
      name: :governed_packet_definition_fields_scope_idx
    )
  end

  defp all_fields do
    [
      :packet_definition_row_id,
      :field_id,
      :name,
      :offset_bits,
      :size_bits,
      :data_type,
      :engineering_unit
    ]
  end
end
