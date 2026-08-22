defmodule Cadence.Recordings.Recordables.ProcedureCancelled do
  @moduledoc """
  Recordable for when a procedure execution is cancelled.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_cancelleds" do
    field :reason, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:reason])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ProcedureCancelled do
  def recording_type(_), do: "ProcedureCancelled"
  def aggregate_type(_), do: "ProcedureExecution"
  def title(r), do: r.reason || "Cancelled"
  def status(_), do: "cancelled"
  def severity(_), do: nil
end
