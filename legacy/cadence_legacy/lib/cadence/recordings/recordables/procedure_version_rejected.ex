defmodule Cadence.Recordings.Recordables.ProcedureVersionRejected do
  @moduledoc """
  Recordable for when a procedure version is rejected.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_version_rejecteds" do
    field :reason, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:reason])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureVersionRejected do
  def recording_type(_), do: "ProcedureVersionRejected"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(r), do: r.reason || "Rejected"
  def status(_), do: "rejected"
  def severity(_), do: "warning"
end
