defmodule Cadence.Links.Link do
  @moduledoc """
  Mission-scoped spacecraft link keyed by SCID.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "links" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission

    field :scid, :integer
    field :name, :string

    has_one :protocol_config, Cadence.Links.ProtocolConfig
    has_many :channels, Cadence.Links.Channel

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a link.
  """
  def changeset(link, attrs, organization_id, mission_id) do
    link
    |> cast(attrs, [:scid, :name])
    |> put_change(:organization_id, organization_id)
    |> put_change(:mission_id, mission_id)
    |> validate_required([:organization_id, :mission_id, :scid])
    |> unique_constraint([:organization_id, :mission_id, :scid],
      name: :links_org_mission_scid_index
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
  end

  @doc """
  Changeset for updating a link.
  """
  def update_changeset(link, attrs) do
    link
    |> cast(attrs, [:name])
  end
end
