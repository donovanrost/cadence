defmodule Cadence.Recordings.Recordables.ExecutionCommentAdded do
  @moduledoc """
  Recordable for when a comment is added to a procedure execution.

  This event captures operator notes, questions, and observations
  made during procedure execution.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "execution_comment_addeds" do
    field :step_name, :string
    field :comment_type, :string
    field :content_preview, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields []
  @optional_fields [:step_name, :comment_type, :content_preview]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ExecutionCommentAdded do
  def recording_type(_), do: "ExecutionCommentAdded"
  def aggregate_type(_), do: "ProcedureExecution"

  def title(r) do
    type = r.comment_type || "note"
    preview = r.content_preview || "(comment)"
    "#{String.capitalize(type)}: #{preview}"
  end

  def status(_), do: "comment"
  def severity(_), do: nil
end
