defmodule Cadence.Links.Channel do
  @moduledoc """
  Mission-scoped channel identified by ChannelId (SCID/VCID/MAP).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions [:uplink, :downlink, :both]

  schema "channels" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :link, Cadence.Links.Link

    field :scid, :integer
    field :vcid, :integer
    field :map_id, :integer
    field :direction, Ecto.Enum, values: @directions
    field :enabled, :boolean, default: true

    has_many :bindings, Cadence.Links.Binding
    has_one :protocol_config, Cadence.Links.ChannelProtocolConfig

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a channel.
  """
  def changeset(channel, attrs, organization_id, mission_id) do
    channel
    |> cast(attrs, [:link_id, :scid, :vcid, :map_id, :direction, :enabled])
    |> put_change(:organization_id, organization_id)
    |> put_change(:mission_id, mission_id)
    |> validate_required([:organization_id, :mission_id, :link_id, :scid, :vcid, :direction])
    |> unique_constraint([:organization_id, :mission_id, :scid, :vcid],
      name: :channels_org_mission_scid_vcid_null_map_index
    )
    |> unique_constraint([:organization_id, :mission_id, :scid, :vcid, :map_id],
      name: :channels_org_mission_scid_vcid_map_index
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:link_id)
  end

  @doc """
  Changeset for updating a channel.
  """
  def update_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:direction, :enabled])
    |> validate_required([:direction])
  end
end
