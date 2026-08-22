defmodule Cadence.Procedures.ExecutionComment do
  @moduledoc """
  A comment on a procedure execution or specific step.

  Comments allow operators to add notes, questions, and observations during
  procedure execution. Comments can be:

  - Execution-level (applies to overall run)
  - Step-level (associated with a specific step)
  - Threaded (replies to other comments)

  ## Comment Types

  - `:note` - General observation or note (default)
  - `:issue` - Problem or concern identified
  - `:question` - Question needing answer
  - `:resolution` - Resolution to a previous issue/question

  ## Threading

  Comments can be threaded by setting `parent_comment_id`. This allows
  for discussions and back-and-forth between operators.

  ## Example Usage

      %ExecutionComment{
        procedure_execution_id: "...",
        step_execution_id: "...",  # nil for execution-level
        user_id: "...",
        content: "Observed unusual reading, proceeding with caution",
        comment_type: :note
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Procedures.{ProcedureExecution, StepExecution}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @comment_types [:note, :issue, :question, :resolution]

  schema "execution_comments" do
    field :content, :string
    field :comment_type, Ecto.Enum, values: @comment_types, default: :note

    belongs_to :procedure_execution, ProcedureExecution
    belongs_to :step_execution, StepExecution
    belongs_to :user, User
    belongs_to :parent_comment, __MODULE__

    has_many :replies, __MODULE__, foreign_key: :parent_comment_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:procedure_execution_id, :user_id, :content]
  @optional_fields [:step_execution_id, :parent_comment_id, :comment_type]

  @doc """
  Creates a changeset for an execution comment.
  """
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:content, min: 1, max: 10_000)
    |> foreign_key_constraint(:procedure_execution_id)
    |> foreign_key_constraint(:step_execution_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:parent_comment_id)
  end

  @doc """
  Creates a changeset for a reply to an existing comment.
  """
  def reply_changeset(parent_comment, attrs) do
    attrs =
      attrs
      |> Map.put(:procedure_execution_id, parent_comment.procedure_execution_id)
      |> Map.put(:step_execution_id, parent_comment.step_execution_id)
      |> Map.put(:parent_comment_id, parent_comment.id)

    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Returns true if this comment is a reply.
  """
  def reply?(%__MODULE__{parent_comment_id: nil}), do: false
  def reply?(%__MODULE__{}), do: true

  @doc """
  Returns true if this comment is step-level.
  """
  def step_level?(%__MODULE__{step_execution_id: nil}), do: false
  def step_level?(%__MODULE__{}), do: true

  @doc """
  Returns a preview of the comment content.
  """
  def preview(%__MODULE__{content: content}, max_length \\ 100) do
    if String.length(content) <= max_length do
      content
    else
      String.slice(content, 0, max_length - 3) <> "..."
    end
  end

  def comment_types, do: @comment_types
end
