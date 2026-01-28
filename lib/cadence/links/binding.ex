defmodule Cadence.Links.Binding do
  @moduledoc """
  Binding between a channel and a transport interface.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions [:uplink, :downlink, :both]
  @roles [:primary, :backup, :replay, :any]
  @states [:active, :inactive, :draining]

  schema "bindings" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :channel, Cadence.Links.Channel
    belongs_to :interface, Cadence.Transports.Interface

    field :direction, Ecto.Enum, values: @directions
    field :role, Ecto.Enum, values: @roles
    field :priority, :integer, default: 100
    field :desired_state, Ecto.Enum, values: @states, default: :inactive

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a binding.
  """
  def changeset(binding, attrs, organization_id, mission_id) do
    binding
    |> cast(attrs, [:channel_id, :interface_id, :direction, :role, :priority, :desired_state])
    |> put_change(:organization_id, organization_id)
    |> put_change(:mission_id, mission_id)
    |> validate_required([
      :organization_id,
      :mission_id,
      :channel_id,
      :interface_id,
      :direction,
      :role,
      :priority,
      :desired_state
    ])
    |> unique_constraint(
      [:organization_id, :mission_id, :channel_id, :interface_id, :direction, :role],
      name: :bindings_org_mission_channel_interface_index
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:channel_id)
    |> foreign_key_constraint(:interface_id)
  end

  @doc """
  Changeset for updating a binding.
  """
  def update_changeset(binding, attrs) do
    binding
    |> cast(attrs, [:direction, :role, :priority, :desired_state])
    |> validate_required([:direction, :role, :priority, :desired_state])
  end
end
