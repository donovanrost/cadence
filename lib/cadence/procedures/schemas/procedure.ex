defmodule Cadence.Procedures.Procedure do
  @moduledoc """
  A procedure definition.

  Procedures can be either:
  - `:dag` - Step-based DAG (directed acyclic graph) with parallel execution support
  - `:script` - Raw Lua code for complex/custom operations

  Procedures are versioned - edits create new versions. The `current_version_id`
  points to the latest approved version (or latest draft if none approved).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.ProcedureVersion

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedures" do
    field :name, :string
    field :description, :string
    field :type, Ecto.Enum, values: [:dag, :script], default: :dag

    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :current_version, ProcedureVersion

    has_many :versions, ProcedureVersion

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :organization_id]
  @optional_fields [:description, :type, :mission_id, :current_version_id]

  def changeset(procedure, attrs) do
    procedure
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 2000)
    |> unique_constraint([:organization_id, :mission_id, :name],
      name: :procedures_org_mission_name_index,
      message: "procedure name must be unique within the mission"
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
  end
end
