defmodule Cadence.Recordings.Recordables.ProcedureVersionApproved do
  @moduledoc """
  Recordable for when a procedure version meets its approval threshold.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_version_approveds" do
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureVersionApproved do
  def recording_type(_), do: "ProcedureVersionApproved"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Approved"
  def status(_), do: "approved"
  def severity(_), do: nil
end
