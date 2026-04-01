defmodule Cadence.Recordings.Recordables.ProcedureCompleted do
  @moduledoc """
  Recordable for when a procedure execution completes successfully.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_completeds" do
    field :completed_steps, {:array, :string}, default: []
    field :skipped_steps, {:array, :string}, default: []
    field :step_results, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:completed_steps, :skipped_steps, :step_results])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ProcedureCompleted do
  def recording_type(_), do: "ProcedureCompleted"
  def aggregate_type(_), do: "ProcedureExecution"
  def title(r), do: "Completed (#{length(r.completed_steps)} steps)"
  def status(_), do: "completed"
  def severity(_), do: nil
end
