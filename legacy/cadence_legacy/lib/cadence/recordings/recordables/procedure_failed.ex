defmodule Cadence.Recordings.Recordables.ProcedureFailed do
  @moduledoc """
  Recordable for when a procedure execution fails.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_faileds" do
    field :error_message, :string
    field :error_step_index, :integer
    field :failed_steps, {:array, :string}, default: []

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:error_message, :error_step_index, :failed_steps])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ProcedureFailed do
  def recording_type(_), do: "ProcedureFailed"
  def aggregate_type(_), do: "ProcedureExecution"
  def title(r), do: r.error_message || "Failed"
  def status(_), do: "failed"
  def severity(_), do: "error"
end
