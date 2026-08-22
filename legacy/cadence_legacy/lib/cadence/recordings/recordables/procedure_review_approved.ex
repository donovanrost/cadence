defmodule Cadence.Recordings.Recordables.ProcedureReviewApproved do
  @moduledoc """
  Recordable for when a reviewer approves a procedure version.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_review_approveds" do
    field :body, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:body])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureReviewApproved do
  def recording_type(_), do: "ProcedureReviewApproved"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Review approved"
  def status(_), do: "in_review"
  def severity(_), do: nil
end
