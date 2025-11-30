defmodule Cadence.MissionDatabase.AggregateMember do
  @moduledoc """
  Defines a member of an aggregate (struct) data type.

  Aggregate types are composed of multiple named members, each with their own type.

  ## Example

      # A position aggregate with x, y, z members
      %AggregateMember{
        name: "x",
        type_ref: "Float32Type",
        description: "X coordinate in meters"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :type_ref, :string  # Reference to DataType name
    field :description, :string
    field :initial_value, :string
  end

  @doc """
  Changeset for creating or updating an aggregate member.
  """
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:name, :type_ref, :description, :initial_value])
    |> validate_required([:name, :type_ref])
  end
end
