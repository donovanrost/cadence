defmodule Cadence.Recordings.Recordables.ProcedureStepSkipped do
  @moduledoc """
  Recordable for when a procedure step is skipped.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_step_skippeds" do
    field :step_id, :string
    field :step_index, :integer
    field :reason, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:step_id, :step_index, :reason])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ProcedureStepSkipped do
  def recording_type(_), do: "ProcedureStepSkipped"
  def aggregate_type(_), do: "ProcedureExecution"
  def title(r), do: "Step #{r.step_id || r.step_index} skipped"
  def status(_), do: "running"
  def severity(_), do: nil
end
