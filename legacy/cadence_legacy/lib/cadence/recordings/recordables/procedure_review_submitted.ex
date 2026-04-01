defmodule Cadence.Recordings.Recordables.ProcedureReviewSubmitted do
  @moduledoc """
  Recordable for when a procedure version is submitted for review.

  This replaces the older ProcedureVersionSubmitted with additional support
  for tracking which reviewers were requested.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_review_submitteds" do
    field :note, :string
    field :reviewer_ids, {:array, :binary_id}, default: []

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:note, :reviewer_ids])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureReviewSubmitted do
  def recording_type(_), do: "ProcedureReviewSubmitted"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Submitted for review"
  def status(_), do: "in_review"
  def severity(_), do: nil
end
