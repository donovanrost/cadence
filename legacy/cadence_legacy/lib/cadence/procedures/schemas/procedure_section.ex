defmodule Cadence.Procedures.ProcedureSection do
  @moduledoc """
  A section within a procedure version.

  Sections group related steps together for better organization and display.
  Each section has an ordered list of steps that can be collapsed/expanded
  in the UI.

  ## Example Structure

      %ProcedureSection{
        name: "Pre-Flight Checks",
        description: "Verify spacecraft is ready for command operations",
        position: 1,
        collapsed_by_default: false
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.{ProcedureStep, ProcedureVersion}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_sections" do
    field :name, :string
    field :description, :string
    field :position, :integer
    field :collapsed_by_default, :boolean, default: false

    belongs_to :procedure_version, ProcedureVersion
    has_many :steps, ProcedureStep, foreign_key: :section_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:procedure_version_id, :name, :position]
  @optional_fields [:description, :collapsed_by_default]

  @doc """
  Creates a changeset for a procedure section.
  """
  def changeset(section, attrs) do
    section
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 2000)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:procedure_version_id)
  end

  @doc """
  Creates a changeset for updating section position.
  """
  def reposition_changeset(section, new_position) do
    section
    |> change()
    |> put_change(:position, new_position)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
