defmodule Cadence.Links.ChannelProtocolConfig do
  @moduledoc """
  Channel-owned protocol overrides.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_protocol_configs" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :channel, Cadence.Links.Channel

    field :overrides, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating channel protocol overrides.
  """
  def changeset(config, attrs, organization_id, mission_id) do
    config
    |> cast(attrs, [:channel_id, :overrides])
    |> put_change(:organization_id, organization_id)
    |> put_change(:mission_id, mission_id)
    |> validate_required([:organization_id, :mission_id, :channel_id])
    |> unique_constraint([:channel_id], name: :channel_protocol_configs_channel_index)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:channel_id)
  end

  @doc """
  Changeset for updating channel protocol overrides.
  """
  def update_changeset(config, attrs) do
    config
    |> cast(attrs, [:overrides])
  end
end
