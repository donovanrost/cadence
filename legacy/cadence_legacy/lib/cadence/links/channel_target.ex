defmodule Cadence.Links.ChannelTarget do
  @moduledoc """
  Target-to-channel mapping for uplink resolution.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_targets" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission

    field :target_id, :string
    field :scid, :integer
    field :vcid, :integer, default: 0
    field :map_id, :integer
    field :purpose, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a channel target mapping.
  """
  def changeset(channel_target, attrs, organization_id, mission_id) do
    channel_target
    |> cast(attrs, [:target_id, :scid, :vcid, :map_id, :purpose])
    |> put_change(:organization_id, organization_id)
    |> put_change(:mission_id, mission_id)
    |> validate_required([:organization_id, :mission_id, :target_id, :scid, :vcid])
    |> unique_constraint([:organization_id, :mission_id, :target_id, :scid, :vcid],
      name: :channel_targets_null_map_null_purpose_index
    )
    |> unique_constraint([:organization_id, :mission_id, :target_id, :scid, :vcid, :map_id],
      name: :channel_targets_map_null_purpose_index
    )
    |> unique_constraint([:organization_id, :mission_id, :target_id, :scid, :vcid, :purpose],
      name: :channel_targets_null_map_with_purpose_index
    )
    |> unique_constraint(
      [:organization_id, :mission_id, :target_id, :scid, :vcid, :map_id, :purpose],
      name: :channel_targets_map_with_purpose_index
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
  end
end
