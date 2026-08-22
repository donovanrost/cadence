defmodule Cadence.Recordings.Recordables.ProcedureReviewRequested do
  @moduledoc """
  Recordable for when a specific reviewer is requested to review a procedure version.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_review_requesteds" do
    field :reviewer_id, :binary_id
    field :message, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:reviewer_id, :message])
    |> validate_required([:reviewer_id])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureReviewRequested do
  def recording_type(_), do: "ProcedureReviewRequested"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Review requested"
  def status(_), do: "in_review"
  def severity(_), do: nil
end
