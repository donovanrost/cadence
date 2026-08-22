defmodule Cadence.Links.ChannelActiveSelection do
  @moduledoc """
  Optional manual active selection for a channel direction.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions [:uplink, :downlink]

  schema "channel_active_selections" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :channel, Cadence.Links.Channel
    belongs_to :binding, Cadence.Links.Binding

    field :direction, Ecto.Enum, values: @directions

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an active selection.
  """
  def changeset(selection, attrs, organization_id, mission_id) do
    selection
    |> cast(attrs, [:channel_id, :binding_id, :direction])
    |> put_change(:organization_id, organization_id)
    |> put_change(:mission_id, mission_id)
    |> validate_required([:organization_id, :mission_id, :channel_id, :direction])
    |> unique_constraint([:channel_id, :direction],
      name: :channel_active_selections_channel_direction_index
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:channel_id)
    |> foreign_key_constraint(:binding_id)
  end
end
