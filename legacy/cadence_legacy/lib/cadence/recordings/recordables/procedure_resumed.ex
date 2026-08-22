defmodule Cadence.Recordings.Recordables.ProcedureResumed do
  @moduledoc """
  Recordable for when a procedure execution is resumed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_resumeds" do
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ProcedureResumed do
  def recording_type(_), do: "ProcedureResumed"
  def aggregate_type(_), do: "ProcedureExecution"
  def title(_), do: "Resumed"
  def status(_), do: "running"
  def severity(_), do: nil
end
