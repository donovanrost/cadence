defmodule Cadence.Recordings.Recordables.ProcedureVersionResubmitted do
  @moduledoc """
  Recordable for when an author resubmits a procedure version after addressing changes.

  This transitions the version back to in_review status and clears previous reviews.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_version_resubmitteds" do
    field :note, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:note])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureVersionResubmitted do
  def recording_type(_), do: "ProcedureVersionResubmitted"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Resubmitted for review"
  def status(_), do: "in_review"
  def severity(_), do: nil
end
