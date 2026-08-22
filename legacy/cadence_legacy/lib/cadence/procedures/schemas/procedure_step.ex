defmodule Cadence.Procedures.ProcedureStep do
  @moduledoc """
  A step within a procedure section.

  Steps are the primary unit of work in a procedure. Each step can:
  - Contain multiple blocks (content, inputs, telemetry, commands)
  - Require signoff from specific roles
  - Depend on other steps completing first
  - Have conditions that skip execution
  - Define behavior on failure

  ## Step Lifecycle

  Steps transition through these statuses during execution:
  - `pending` - Not yet started
  - `active` - Currently being worked on
  - `awaiting_signoff` - Waiting for operator signoff
  - `completed` - Successfully finished
  - `skipped` - Skipped (condition false or manual skip)
  - `failed` - Failed with error
  - `blocked` - Waiting for dependencies

  ## Dependencies

  Steps can declare dependencies on other steps by name:

      depends_on: ["power_check", "thermal_verify"]
      dependency_logic: :all  # Must complete all (default) or :any

  ## Signoff Requirements

  Steps can require signoff from specific roles:

      requires_signoff: true
      required_roles: ["operator", "supervisor"]
      signoff_logic: :any  # Any role can sign off (default) or :all

  ## Conditional Execution

  Steps can be conditionally skipped based on telemetry or variables:

      condition: "target.EPS.battery_voltage >= 24.0"

  If the condition evaluates to false, the step is skipped.

  ## Failure Handling

  The `on_fail` field controls what happens when a step fails:
  - `:abort` - Stop procedure execution (default)
  - `:continue` - Log failure and continue to next step
  - `:pause` - Pause execution and wait for operator
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.{ProcedureBlock, ProcedureSection}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @signoff_logic_values [:any, :all]
  @dependency_logic_values [:all, :any]
  @on_fail_values [:abort, :continue, :pause]

  schema "procedure_steps" do
    field :name, :string
    field :title, :string
    field :position, :integer

    # Signoff requirements
    field :requires_signoff, :boolean, default: true
    field :required_roles, {:array, :string}, default: []
    field :signoff_logic, Ecto.Enum, values: @signoff_logic_values, default: :any

    # Dependencies
    field :depends_on, {:array, :string}, default: []
    field :dependency_logic, Ecto.Enum, values: @dependency_logic_values, default: :all

    # Conditional execution
    field :condition, :string
    field :on_fail, Ecto.Enum, values: @on_fail_values, default: :abort

    # Duration estimate (seconds)
    field :estimated_duration_seconds, :integer

    belongs_to :section, ProcedureSection
    has_many :blocks, ProcedureBlock, foreign_key: :step_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:section_id, :name, :position]
  @optional_fields [
    :title,
    :requires_signoff,
    :required_roles,
    :signoff_logic,
    :depends_on,
    :dependency_logic,
    :condition,
    :on_fail,
    :estimated_duration_seconds
  ]

  @doc """
  Creates a changeset for a procedure step.
  """
  def changeset(step, attrs) do
    step
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:title, max: 255)
    |> validate_length(:condition, max: 2000)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_number(:estimated_duration_seconds, greater_than_or_equal_to: 0)
    |> validate_name_format()
    |> validate_roles()
    |> foreign_key_constraint(:section_id)
    |> unique_constraint([:section_id, :name],
      name: :procedure_steps_section_id_name_index,
      message: "step name already exists in this section"
    )
  end

  @doc """
  Creates a changeset for updating step position.
  """
  def reposition_changeset(step, new_position) do
    step
    |> change()
    |> put_change(:position, new_position)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end

  # Step names must be valid identifiers for use in dependencies
  defp validate_name_format(changeset) do
    validate_format(changeset, :name, ~r/^[a-zA-Z][a-zA-Z0-9_]*$/,
      message: "must start with a letter and contain only letters, numbers, and underscores"
    )
  end

  defp validate_roles(changeset) do
    case get_field(changeset, :required_roles) do
      nil ->
        changeset

      roles when is_list(roles) ->
        if Enum.all?(roles, &valid_role_name?/1) do
          changeset
        else
          add_error(changeset, :required_roles, "contains invalid role names")
        end

      _ ->
        add_error(changeset, :required_roles, "must be a list of strings")
    end
  end

  defp valid_role_name?(role) when is_binary(role) do
    String.length(role) > 0 and String.length(role) <= 50
  end

  defp valid_role_name?(_), do: false

  @doc """
  Returns whether this step requires all dependencies to complete.
  """
  def requires_all_deps?(%__MODULE__{dependency_logic: :all}), do: true
  def requires_all_deps?(%__MODULE__{}), do: false

  @doc """
  Returns whether this step requires signoff from all specified roles.
  """
  def requires_all_signoffs?(%__MODULE__{signoff_logic: :all}), do: true
  def requires_all_signoffs?(%__MODULE__{}), do: false

  def signoff_logic_values, do: @signoff_logic_values
  def dependency_logic_values, do: @dependency_logic_values
  def on_fail_values, do: @on_fail_values
end
