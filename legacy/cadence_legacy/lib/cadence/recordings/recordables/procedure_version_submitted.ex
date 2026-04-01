defmodule Cadence.Recordings.Recordables.ProcedureVersionSubmitted do
  @moduledoc """
  Recordable for when a procedure version is submitted for review.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_version_submitteds" do
    field :note, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:note])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureVersionSubmitted do
  def recording_type(_), do: "ProcedureVersionSubmitted"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Submitted for review"
  def status(_), do: "pending_review"
  def severity(_), do: nil
end
