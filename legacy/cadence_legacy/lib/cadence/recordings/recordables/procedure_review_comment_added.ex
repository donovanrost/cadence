defmodule Cadence.Recordings.Recordables.ProcedureReviewCommentAdded do
  @moduledoc """
  Recordable for when a comment is added to a review thread.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_review_comment_addeds" do
    field :thread_id, :binary_id
    field :body, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:thread_id, :body])
    |> validate_required([:thread_id, :body])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureReviewCommentAdded do
  def recording_type(_), do: "ProcedureReviewCommentAdded"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Comment added"
  def status(_), do: nil
  def severity(_), do: nil
end
