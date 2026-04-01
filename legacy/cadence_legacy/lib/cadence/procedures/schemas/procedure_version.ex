defmodule Cadence.Procedures.ProcedureVersion do
  @moduledoc """
  A specific version of a procedure.

  Each edit to a procedure creates a new version. Versions go through an
  approval workflow:

  - `draft` - Being edited, not ready for use
  - `in_review` - Submitted for approval
  - `changes_requested` - Reviewer requested changes, awaiting author revision
  - `approved` - Approved for execution
  - `closed` - Abandoned/cancelled (like closing a PR without merging)
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

  @statuses [:draft, :in_review, :changes_requested, :approved, :closed, :deprecated]
  @execution_modes [:manual, :assisted, :automatic]

  schema "procedure_versions" do
    field :version_number, :integer
    field :source, :map
    field :parameters_schema, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :draft

    # V2 execution mode:
    # - :manual - Operator must manually trigger each step
    # - :assisted - System suggests next step, operator confirms
    # - :automatic - Steps execute automatically when dependencies met
    field :execution_mode, Ecto.Enum, values: @execution_modes, default: :manual

    # When true, operators can propose changes during execution (redlines)
    field :allow_suggested_edits, :boolean, default: true

    # When true, commands sent by this procedure bypass hazardous confirmation.
    # This should only be enabled for procedures that are designed to execute
    # hazardous commands in controlled scenarios (e.g., automated recovery sequences).
    field :allow_hazardous_commands, :boolean, default: false

    field :approved_at, :utc_datetime
    field :change_summary, :string

    # Submission tracking
    field :submitted_at, :utc_datetime
    field :rejected_at, :utc_datetime
    field :rejection_reason, :string

    belongs_to :procedure, Procedure
    belongs_to :created_by, Cadence.Accounts.User
    belongs_to :approved_by, Cadence.Accounts.User
    belongs_to :submitted_by, Cadence.Accounts.User
    belongs_to :rejected_by, Cadence.Accounts.User

    # New review workflow (replaces approvals)
    has_many :reviews, Cadence.Procedures.ProcedureReview
    has_many :review_threads, Cadence.Procedures.ProcedureReviewThread
    has_many :review_requests, Cadence.Procedures.ProcedureReviewRequest

    timestamps(type: :utc_datetime)
  end

  @required_fields [:procedure_id, :version_number, :source]
  @optional_fields [
    :parameters_schema,
    :status,
    :approved_at,
    :approved_by_id,
    :created_by_id,
    :change_summary,
    :allow_hazardous_commands,
    :execution_mode,
    :allow_suggested_edits,
    :submitted_at,
    :submitted_by_id,
    :rejected_at,
    :rejected_by_id,
    :rejection_reason
  ]

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
    |> foreign_key_constraint(:submitted_by_id)
    |> foreign_key_constraint(:rejected_by_id)
    |> unique_constraint([:procedure_id, :version_number],
      name: :procedure_versions_procedure_version_index,
      message: "version number already exists"
    )
  end

  @doc """
  Changeset for approving a version.
  """
  def approval_changeset(version, attrs) do
    version
    |> cast(attrs, [:status, :approved_at, :approved_by_id])
    |> validate_inclusion(:status, [:approved, :deprecated])
  end

  @doc """
  Changeset for submitting a version for review.
  """
  def submit_changeset(version, attrs) do
    version
    |> cast(attrs, [:status, :submitted_at, :submitted_by_id])
    |> validate_inclusion(:status, [:in_review])
  end

  @doc """
  Changeset for withdrawing a submission.
  """
  def withdrawal_changeset(version, _attrs) do
    version
    |> change()
    |> put_change(:status, :draft)
    |> put_change(:submitted_at, nil)
    |> put_change(:submitted_by_id, nil)
  end

  @doc """
  Changeset for requesting changes on a version.
  Transitions to changes_requested status.
  """
  def changes_requested_changeset(version, _attrs) do
    version
    |> change()
    |> put_change(:status, :changes_requested)
  end

  @doc """
  Changeset for resubmitting a version after changes.
  Clears rejection data and transitions back to in_review.
  """
  def resubmit_changeset(version, attrs) do
    version
    |> cast(attrs, [:submitted_at, :submitted_by_id])
    |> put_change(:status, :in_review)
    |> put_change(:rejected_at, nil)
    |> put_change(:rejected_by_id, nil)
    |> put_change(:rejection_reason, nil)
  end

  @doc """
  Changeset for closing a version (abandoning without approval).
  """
  def close_changeset(version, _attrs) do
    version
    |> change()
    |> put_change(:status, :closed)
  end

  @doc """
  Changeset for rejecting a version.
  DEPRECATED: Use changes_requested_changeset instead for the new workflow.
  """
  def rejection_changeset(version, attrs) do
    version
    |> cast(attrs, [:rejected_at, :rejected_by_id, :rejection_reason])
    |> put_change(:status, :draft)
    |> validate_required([:rejection_reason])
    |> validate_length(:rejection_reason, max: 2000)
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
  def execution_modes, do: @execution_modes
end
