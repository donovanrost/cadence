defmodule Cadence.Contacts.ContactCommandAction do
  @moduledoc """
  Planned command action bound to a specific contact.

  These actions are evaluated by the runtime when readiness gates
  become satisfied during an active contact.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @gates [:active, :uplink_ready]
  @states [:planned, :cancelled]

  schema "contact_command_actions" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :contact, Cadence.Contacts.Contact

    field :gate, Ecto.Enum, values: @gates, default: :uplink_ready
    field :order, :integer, default: 0
    field :state, Ecto.Enum, values: @states, default: :planned
    field :command_ref, :map
    field :metadata, :map, default: %{}
    field :command_name, :string, virtual: true
    field :parameters_json, :string, virtual: true

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [
    :organization_id,
    :mission_id,
    :contact_id,
    :gate,
    :order,
    :state,
    :command_ref
  ]

  @optional_fields [:metadata, :command_name, :parameters_json]

  @doc false
  def changeset(action, attrs) do
    action
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:order, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:contact_id)
  end
end
