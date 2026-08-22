defmodule Cadence.Governance.GovernedPacketDefinitionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Telemetry.PacketDefinition

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "governed_packet_definitions" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:packet_definition_id, :string)
    field(:packet_name, :string)
    field(:apid, :integer)
    field(:version, :integer)

    has_many(:field_rows, Cadence.Governance.PacketDefinitionFieldRow,
      foreign_key: :packet_definition_row_id
    )

    timestamps()
  end

  @required_fields [:mission_id, :packet_definition_id, :packet_name, :apid, :version]

  @spec changeset(PacketDefinition.t()) :: Ecto.Changeset.t()
  def changeset(%PacketDefinition{} = packet_definition) do
    %__MODULE__{}
    |> cast(
      %{
        organization_id: packet_definition.organization_id,
        mission_id: packet_definition.mission_id,
        packet_definition_id: packet_definition.packet_definition_id,
        packet_name: packet_definition.packet_name,
        apid: packet_definition.apid,
        version: packet_definition.version
      },
      all_fields()
    )
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :packet_definition_id, :version],
      name: :governed_packet_definitions_scope_idx
    )
  end

  defp all_fields do
    [:organization_id, :mission_id, :packet_definition_id, :packet_name, :apid, :version]
  end
end
