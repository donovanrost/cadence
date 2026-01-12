defmodule Cadence.Interfaces.InterfaceVcid do
  @moduledoc """
  Schema for virtual channel (VCID) mappings on an interface.

  Each mapping can optionally attach to a target and define routing metadata
  such as lane overrides or QoS tags.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "interface_vcids" do
    belongs_to :interface, Cadence.Interfaces.InterfaceSchema
    belongs_to :target, Cadence.Targets.Target

    field :vcid, :integer
    field :lane, :string
    field :qos, :string
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a VCID mapping.
  """
  def changeset(vcid_mapping, attrs) do
    vcid_mapping
    |> cast(attrs, [:interface_id, :target_id, :vcid, :lane, :qos, :notes])
    |> validate_required([:interface_id, :vcid])
    |> validate_number(:vcid, greater_than_or_equal_to: 0, less_than: 8)
    |> foreign_key_constraint(:interface_id)
    |> foreign_key_constraint(:target_id)
    |> unique_constraint([:interface_id, :target_id, :vcid],
      name: :interface_vcids_interface_id_target_id_vcid_index
    )
    |> unique_constraint([:interface_id, :vcid],
      name: :interface_vcids_interface_id_vcid_default_index
    )
  end
end
