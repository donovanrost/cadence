defmodule Cadence.Recordings.Recordables.ProcedureVersionClosed do
  @moduledoc """
  Recordable for when a procedure version is closed/abandoned.

  Similar to closing a PR without merging.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_version_closeds" do
    field :reason, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:reason])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureVersionClosed do
  def recording_type(_), do: "ProcedureVersionClosed"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Version closed"
  def status(_), do: "closed"
  def severity(_), do: nil
end
