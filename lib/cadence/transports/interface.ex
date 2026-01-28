defmodule Cadence.Transports.Interface do
  @moduledoc """
  Mission-scoped transport interface configuration.

  Interfaces are transport endpoints only; protocol state lives elsewhere.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @allowed_directions [:uplink, :downlink, :both]
  @types [:tcp, :udp, :serial, :file, :s3, :replay]

  schema "transport_interfaces" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission

    field :name, :string
    field :type, Ecto.Enum, values: @types
    field :endpoint, :map, default: %{}
    field :auth, :map, default: %{}
    field :tags, {:array, :string}, default: []
    field :allowed_directions, {:array, Ecto.Enum}, values: @allowed_directions, default: [:both]
    field :enabled, :boolean, default: true

    has_many :bindings, Cadence.Links.Binding, foreign_key: :interface_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a transport interface.
  """
  def changeset(interface, attrs, organization_id, mission_id) do
    interface
    |> cast(attrs, [:name, :type, :endpoint, :auth, :tags, :allowed_directions, :enabled])
    |> put_change(:organization_id, organization_id)
    |> put_change(:mission_id, mission_id)
    |> validate_required([:organization_id, :mission_id, :name, :type])
    |> unique_constraint([:organization_id, :mission_id, :name],
      name: :transport_interfaces_org_mission_name_index
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
  end

  @doc """
  Changeset for updating a transport interface.
  """
  def update_changeset(interface, attrs) do
    interface
    |> cast(attrs, [:name, :type, :endpoint, :auth, :tags, :allowed_directions, :enabled])
    |> validate_required([:name, :type])
  end
end
