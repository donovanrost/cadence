defmodule Cadence.Recordings.Recordables.ProcedurePaused do
  @moduledoc """
  Recordable for when a procedure execution is paused.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_pauseds" do
    field :checkpoint_state, :binary
    field :current_step_index, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:checkpoint_state, :current_step_index])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ProcedurePaused do
  def recording_type(_), do: "ProcedurePaused"
  def aggregate_type(_), do: "ProcedureExecution"
  def title(r), do: "Paused at step #{r.current_step_index}"
  def status(_), do: "paused"
  def severity(_), do: nil
end
