defmodule Cadence.Procedures.StepSignoff do
  @moduledoc """
  Records an operator signoff on a procedure step.

  Signoffs are the formal acknowledgment that a step has been completed
  and verified by an authorized operator. Each signoff records:

  - The user who signed off
  - The role they signed off as
  - Optional note explaining the signoff
  - Timestamp when signoff occurred

  ## Role-Based Signoffs

  Steps can require signoffs from specific roles. The `role` field
  records which role the operator used when signing off:

      %StepSignoff{
        user_id: "...",
        role: "operator",
        note: "Verified battery voltage within nominal range"
      }

  ## Signoff Logic

  Steps can require:
  - `:any` - Any authorized user can sign off (default)
  - `:all` - All specified roles must sign off

  For `:all` logic, multiple signoff records are created, one per
  required role.

  ## Immutability

  Signoffs are immutable once created - they cannot be edited or deleted.
  This ensures audit trail integrity. The `updated_at: false` timestamp
  configuration enforces this.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Procedures.StepExecution

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "step_signoffs" do
    field :role, :string
    field :note, :string

    belongs_to :step_execution, StepExecution
    belongs_to :user, User

    # Signoffs are immutable - no updated_at
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required_fields [:step_execution_id, :user_id, :role]
  @optional_fields [:note]

  @doc """
  Creates a changeset for a step signoff.
  """
  def changeset(signoff, attrs) do
    signoff
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:role, min: 1, max: 50)
    |> validate_length(:note, max: 2000)
    |> foreign_key_constraint(:step_execution_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:step_execution_id, :user_id],
      name: :step_signoffs_execution_user_index,
      message: "user has already signed off on this step"
    )
  end

  @doc """
  Returns true if this signoff satisfies the given role requirement.
  """
  def satisfies_role?(%__MODULE__{role: signoff_role}, required_role) do
    signoff_role == required_role
  end

  @doc """
  Checks if a list of signoffs satisfies the step's signoff requirements.

  ## Parameters

  - `signoffs` - List of StepSignoff records
  - `required_roles` - List of required role names (empty = any role)
  - `logic` - `:any` or `:all`

  ## Returns

  - `true` if requirements are satisfied
  - `false` otherwise
  """
  def requirements_met?(signoffs, required_roles, logic)

  # No signoffs at all
  def requirements_met?([], _required_roles, _logic), do: false

  # No specific roles required - any signoff counts
  def requirements_met?([_ | _], [], _logic), do: true

  # Any logic - at least one required role must be satisfied
  def requirements_met?(signoffs, required_roles, :any) do
    signoff_roles = Enum.map(signoffs, & &1.role)
    Enum.any?(required_roles, &(&1 in signoff_roles))
  end

  # All logic - all required roles must be satisfied
  def requirements_met?(signoffs, required_roles, :all) do
    signoff_roles = Enum.map(signoffs, & &1.role)
    Enum.all?(required_roles, &(&1 in signoff_roles))
  end

  @doc """
  Returns the roles still needed for signoff.
  """
  def missing_roles(signoffs, required_roles, logic)

  def missing_roles(_signoffs, [], _logic), do: []

  def missing_roles(signoffs, required_roles, :any) do
    signoff_roles = Enum.map(signoffs, & &1.role)

    if Enum.any?(required_roles, &(&1 in signoff_roles)) do
      []
    else
      required_roles
    end
  end

  def missing_roles(signoffs, required_roles, :all) do
    signoff_roles = Enum.map(signoffs, & &1.role)
    Enum.reject(required_roles, &(&1 in signoff_roles))
  end
end
