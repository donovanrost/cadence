defmodule Cadence.Procedures.ProcedureVersion do
  @moduledoc """
  A specific version of a procedure.

  Each edit to a procedure creates a new version. Versions go through an
  approval workflow:

  - `draft` - Being edited, not ready for use
  - `in_review` - Submitted for approval
  - `approved` - Approved for execution
  - `deprecated` - No longer recommended for use

  ## Source Format

  For `:dag` type procedures, `source` contains a map with step definitions
  keyed by step name, supporting parallel execution based on dependencies:

      %{
        "steps" => %{
          "check_power" => %{"type" => "check", "condition" => "...", "depends_on" => []},
          "send_cmd" => %{"type" => "command", "name" => "...", "depends_on" => ["check_power"]}
        }
      }

  For `:script` type procedures, `source` is a map with a "code" key containing
  the raw Lua source code:

      %{"code" => "cadence.log('Hello')\\n..."}

  ## Parameters Schema

  The `parameters_schema` field defines expected runtime arguments:

      %{
        "min_voltage" => %{"type" => "number", "default" => 24.0, "required" => true},
        "heater_zone" => %{"type" => "string", "enum" => ["PRIMARY", "BACKUP"]}
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.Procedure

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:draft, :in_review, :approved, :deprecated]

  schema "procedure_versions" do
    field :version_number, :integer
    field :source, :map
    field :parameters_schema, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :draft

    # When true, commands sent by this procedure bypass hazardous confirmation.
    # This should only be enabled for procedures that are designed to execute
    # hazardous commands in controlled scenarios (e.g., automated recovery sequences).
    field :allow_hazardous_commands, :boolean, default: false

    field :approved_at, :utc_datetime
    field :change_summary, :string

    belongs_to :procedure, Procedure
    belongs_to :created_by, Cadence.Accounts.User
    belongs_to :approved_by, Cadence.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @required_fields [:procedure_id, :version_number, :source]
  @optional_fields [:parameters_schema, :status, :approved_at, :approved_by_id, :created_by_id, :change_summary, :allow_hazardous_commands]

  def changeset(version, attrs) do
    version
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:version_number, greater_than: 0)
    |> validate_length(:change_summary, max: 1000)
    |> validate_source()
    |> foreign_key_constraint(:procedure_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:approved_by_id)
    |> unique_constraint([:procedure_id, :version_number],
      name: :procedure_versions_procedure_version_index,
      message: "version number already exists"
    )
  end

  def approval_changeset(version, attrs) do
    version
    |> cast(attrs, [:status, :approved_at, :approved_by_id])
    |> validate_inclusion(:status, [:approved, :deprecated])
  end

  defp validate_source(changeset) do
    case get_field(changeset, :source) do
      nil ->
        changeset

      source when is_map(source) ->
        changeset

      _ ->
        add_error(changeset, :source, "must be a map")
    end
  end

  def statuses, do: @statuses
end
