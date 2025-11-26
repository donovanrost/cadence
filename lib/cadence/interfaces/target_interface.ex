defmodule Cadence.Interfaces.TargetInterface do
  @moduledoc """
  Schema for the target_interfaces join table.

  Defines the routing between targets and interfaces:
  - Which interface(s) serve which target(s)
  - Direction of data flow (read, write, or both)

  ## Examples

      # SAT-001 receives telemetry via TCP_INT_1
      %TargetInterface{
        target_id: "sat-001-uuid",
        interface_id: "tcp-int-1-uuid",
        direction: "read"
      }

      # SAT-001 sends commands via TCP_INT_2
      %TargetInterface{
        target_id: "sat-001-uuid",
        interface_id: "tcp-int-2-uuid",
        direction: "write"
      }

      # GS-1 both sends and receives via TCP_INT_3
      %TargetInterface{
        target_id: "gs-1-uuid",
        interface_id: "tcp-int-3-uuid",
        direction: "read_write"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions ["read", "write", "read_write"]

  schema "target_interfaces" do
    belongs_to :target, Cadence.Targets.Target
    belongs_to :interface, Cadence.Interfaces.Interface

    field :direction, :string

    timestamps()
  end

  @doc """
  Creates a changeset for a target_interface.
  """
  def changeset(target_interface, attrs) do
    target_interface
    |> cast(attrs, [:target_id, :interface_id, :direction])
    |> validate_required([:target_id, :interface_id, :direction])
    |> validate_inclusion(:direction, @directions,
      message: "must be one of: #{Enum.join(@directions, ", ")}"
    )
    |> foreign_key_constraint(:target_id)
    |> foreign_key_constraint(:interface_id)
    |> unique_constraint([:target_id, :interface_id],
      name: :target_interfaces_target_id_interface_id_index,
      message: "This target-interface mapping already exists"
    )
  end

  @doc """
  Returns the list of valid direction values.
  """
  def valid_directions, do: @directions

  @doc """
  Checks if the direction allows reading (telemetry from target).
  """
  def allows_read?(%__MODULE__{direction: direction}), do: direction in ["read", "read_write"]

  @doc """
  Checks if the direction allows writing (commands to target).
  """
  def allows_write?(%__MODULE__{direction: direction}),
    do: direction in ["write", "read_write"]
end
