defmodule Cadence.MissionDatabase.HazardousState do
  @moduledoc """
  Marks a specific argument value as hazardous.

  This allows fine-grained hazard classification where only certain
  values of an argument are considered hazardous.

  ## Example

  For a LASER_MODE command argument:

      [
        %HazardousState{
          value: "ARM",
          description: "Arming the laser is an eye safety hazard"
        },
        %HazardousState{
          value: "FIRE",
          description: "WARNING: This will fire the laser"
        }
      ]

  When the operator selects one of these values, a hazardous command
  warning will be displayed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :value, :string
    field :description, :string
  end

  @doc """
  Changeset for creating or updating a hazardous state.
  """
  def changeset(hazardous_state, attrs) do
    hazardous_state
    |> cast(attrs, [:value, :description])
    |> validate_required([:value])
  end
end
