defmodule Cadence.Persistence.Schemas.SpacecraftTypeRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.SpacecraftType

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_spacecraft_types" do
    field(:spacecraft_type_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:lifecycle_state, :string)
    field(:display_name, :string)
    field(:downlink_protocol, :string)
    field(:uplink_protocol, :string)
    field(:packet_protocol, :string)
    field(:frame_parameters, :map, default: %{})
    field(:applications, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :spacecraft_type_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :display_name,
    :downlink_protocol,
    :uplink_protocol,
    :packet_protocol,
    :frame_parameters,
    :applications,
    :metadata
  ]

  @spec changeset(SpacecraftType.t()) :: Ecto.Changeset.t()
  def changeset(%SpacecraftType{} = type) do
    %__MODULE__{}
    |> cast(domain_attrs(type), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_length(:display_name, min: 1, max: 200)
    |> unique_constraint([:mission_id, :spacecraft_type_id, :version],
      name: :mission_spacecraft_types_scope_idx
    )
  end

  @spec to_domain(struct()) :: SpacecraftType.t()
  def to_domain(%__MODULE__{} = row) do
    SpacecraftType.new(%{
      spacecraft_type_id: row.spacecraft_type_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      lifecycle_state: row.lifecycle_state,
      display_name: row.display_name,
      downlink_protocol: row.downlink_protocol,
      uplink_protocol: row.uplink_protocol,
      packet_protocol: row.packet_protocol,
      frame_parameters: JsonDocument.unwrap_value(row.frame_parameters),
      applications: JsonDocument.unwrap_value(row.applications),
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%SpacecraftType{} = type) do
    %{
      spacecraft_type_id: type.spacecraft_type_id,
      organization_id: type.organization_id,
      mission_id: type.mission_id,
      version: type.version,
      lifecycle_state: Atom.to_string(type.lifecycle_state),
      display_name: type.display_name,
      downlink_protocol: Atom.to_string(type.downlink_protocol),
      uplink_protocol: Atom.to_string(type.uplink_protocol),
      packet_protocol: Atom.to_string(type.packet_protocol),
      frame_parameters: JsonDocument.wrap_value(type.frame_parameters),
      applications: JsonDocument.wrap_value(type.applications),
      metadata: JsonDocument.wrap_value(type.metadata)
    }
  end

  defp all_fields do
    [
      :spacecraft_type_id,
      :organization_id,
      :mission_id,
      :version,
      :lifecycle_state,
      :display_name,
      :downlink_protocol,
      :uplink_protocol,
      :packet_protocol,
      :frame_parameters,
      :applications,
      :metadata
    ]
  end
end
