defmodule Cadence.Procedures.SuggestedEdit do
  @moduledoc """
  A suggested edit (redline) proposed during procedure execution.

  Suggested edits allow operators to propose changes to procedure content
  while executing. These "redlines" are captured for review and can be
  incorporated into the next version of the procedure.

  ## Edit Types

  - `:add_step` - Add a new step
  - `:modify_step` - Modify an existing step
  - `:delete_step` - Remove a step
  - `:add_block` - Add a new block to a step
  - `:modify_block` - Modify an existing block
  - `:delete_block` - Remove a block

  ## Workflow

  1. Operator proposes edit during execution (status: `:pending`)
  2. Procedure owner reviews the suggestion
  3. Edit is either `:accepted` or `:rejected`
  4. If accepted, changes are automatically applied to next draft

  ## Snapshot Format

  The `before_snapshot` and `after_snapshot` fields capture the content:

  For step edits:
      %{
        "name" => "verify_power",
        "title" => "Verify Power Status",
        "blocks" => [...]  # Full block definitions
      }

  For block edits:
      %{
        "block_type" => "text",
        "content" => %{"markdown" => "..."}
      }

  ## Example

      %SuggestedEdit{
        edit_type: :modify_block,
        status: :pending,
        target_step_id: "...",
        target_block_id: "...",
        before_snapshot: %{"content" => %{"text" => "Old warning text"}},
        after_snapshot: %{"content" => %{"text" => "Updated warning text"}},
        reason: "Warning text was unclear about voltage threshold"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Procedures.{ProcedureExecution, StepExecution}
  alias Cadence.Time, as: CadenceTime

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @edit_types [:add_step, :modify_step, :delete_step, :add_block, :modify_block, :delete_block]
  @statuses [:pending, :accepted, :rejected]

  schema "suggested_edits" do
    field :edit_type, Ecto.Enum, values: @edit_types
    field :status, Ecto.Enum, values: @statuses, default: :pending

    # Target location
    field :target_section_id, :binary_id
    field :target_step_id, :binary_id
    field :target_block_id, :binary_id
    field :target_position, :integer

    # The change
    field :before_snapshot, :map
    field :after_snapshot, :map
    field :reason, :string

    # Resolution
    field :resolved_at, :utc_datetime_usec
    field :resolution_note, :string

    belongs_to :procedure_execution, ProcedureExecution
    belongs_to :step_execution, StepExecution
    belongs_to :suggested_by, User
    belongs_to :resolved_by, User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:procedure_execution_id, :suggested_by_id, :edit_type]
  @optional_fields [
    :step_execution_id,
    :status,
    :target_section_id,
    :target_step_id,
    :target_block_id,
    :target_position,
    :before_snapshot,
    :after_snapshot,
    :reason,
    :resolved_at,
    :resolved_by_id,
    :resolution_note
  ]

  @doc """
  Creates a changeset for a suggested edit.
  """
  def changeset(edit, attrs) do
    edit
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:reason, max: 2000)
    |> validate_length(:resolution_note, max: 2000)
    |> validate_target_for_type()
    |> validate_snapshots_for_type()
    |> foreign_key_constraint(:procedure_execution_id)
    |> foreign_key_constraint(:step_execution_id)
    |> foreign_key_constraint(:suggested_by_id)
    |> foreign_key_constraint(:resolved_by_id)
  end

  @doc """
  Changeset for accepting a suggested edit.
  """
  def accept_changeset(edit, user_id, note \\ nil) do
    now = CadenceTime.now() |> DateTime.truncate(:microsecond)

    edit
    |> change()
    |> put_change(:status, :accepted)
    |> put_change(:resolved_at, now)
    |> put_change(:resolved_by_id, user_id)
    |> put_change(:resolution_note, note)
  end

  @doc """
  Changeset for rejecting a suggested edit.
  """
  def reject_changeset(edit, user_id, note) do
    now = CadenceTime.now() |> DateTime.truncate(:microsecond)

    edit
    |> change()
    |> put_change(:status, :rejected)
    |> put_change(:resolved_at, now)
    |> put_change(:resolved_by_id, user_id)
    |> put_change(:resolution_note, note)
    |> validate_required([:resolution_note])
  end

  # Validate that required targets are set for edit type
  defp validate_target_for_type(changeset) do
    edit_type = get_field(changeset, :edit_type)

    case edit_type do
      type when type in [:add_step, :modify_step, :delete_step] ->
        # Step edits need section target (for add) or step target (for modify/delete)
        changeset

      type when type in [:add_block, :modify_block, :delete_block] ->
        # Block edits need step target
        if is_nil(get_field(changeset, :target_step_id)) do
          add_error(changeset, :target_step_id, "is required for block edits")
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  # Validate that snapshots are appropriate for edit type
  defp validate_snapshots_for_type(changeset) do
    edit_type = get_field(changeset, :edit_type)
    before = get_field(changeset, :before_snapshot)
    after_snap = get_field(changeset, :after_snapshot)
    requirements = snapshot_requirements(edit_type)

    changeset
    |> maybe_require_snapshot(:before_snapshot, before, requirements.before)
    |> maybe_require_snapshot(:after_snapshot, after_snap, requirements.after)
  end

  defp snapshot_requirements(type) when type in [:add_step, :add_block],
    do: %{before: false, after: true}

  defp snapshot_requirements(type) when type in [:delete_step, :delete_block],
    do: %{before: true, after: false}

  defp snapshot_requirements(type) when type in [:modify_step, :modify_block],
    do: %{before: true, after: true}

  defp snapshot_requirements(_type), do: %{before: false, after: false}

  defp maybe_require_snapshot(changeset, _field, _value, false), do: changeset

  defp maybe_require_snapshot(changeset, field, value, true) do
    if is_nil(value) do
      message =
        case field do
          :before_snapshot -> "is required for this edit"
          :after_snapshot -> "is required for this edit"
        end

      add_error(changeset, field, message)
    else
      changeset
    end
  end

  @doc """
  Returns true if the edit is still pending review.
  """
  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(%__MODULE__{}), do: false

  @doc """
  Returns true if the edit was accepted.
  """
  def accepted?(%__MODULE__{status: :accepted}), do: true
  def accepted?(%__MODULE__{}), do: false

  @doc """
  Returns a human-readable summary of the edit.
  """
  def summary(%__MODULE__{edit_type: :add_step, after_snapshot: snap}) do
    name = get_in(snap, ["name"]) || get_in(snap, [:name]) || "new step"
    "Add step: #{name}"
  end

  def summary(%__MODULE__{edit_type: :modify_step, after_snapshot: snap}) do
    name = get_in(snap, ["name"]) || get_in(snap, [:name]) || "step"
    "Modify step: #{name}"
  end

  def summary(%__MODULE__{edit_type: :delete_step, before_snapshot: snap}) do
    name = get_in(snap, ["name"]) || get_in(snap, [:name]) || "step"
    "Delete step: #{name}"
  end

  def summary(%__MODULE__{edit_type: :add_block, after_snapshot: snap}) do
    type = get_in(snap, ["block_type"]) || get_in(snap, [:block_type]) || "block"
    "Add #{type} block"
  end

  def summary(%__MODULE__{edit_type: :modify_block, after_snapshot: snap}) do
    type = get_in(snap, ["block_type"]) || get_in(snap, [:block_type]) || "block"
    "Modify #{type} block"
  end

  def summary(%__MODULE__{edit_type: :delete_block, before_snapshot: snap}) do
    type = get_in(snap, ["block_type"]) || get_in(snap, [:block_type]) || "block"
    "Delete #{type} block"
  end

  def summary(%__MODULE__{}), do: "Unknown edit"

  def edit_types, do: @edit_types
  def statuses, do: @statuses
end
