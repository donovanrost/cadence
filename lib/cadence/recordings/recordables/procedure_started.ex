defmodule Cadence.Recordings.Recordables.ProcedureStarted do
  @moduledoc """
  Recordable for when a procedure execution begins.

  This is the "rich" recordable for procedures - it contains all the
  initial execution context.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_starteds" do
    field :procedure_id, :binary_id
    field :procedure_version_id, :binary_id
    field :parameters, :map, default: %{}
    field :triggered_by, :string
    field :trigger_context, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:procedure_id, :procedure_version_id]
  @optional_fields [:parameters, :triggered_by, :trigger_context]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ProcedureStarted do
  def recording_type(_), do: "ProcedureStarted"
  def aggregate_type(_), do: "ProcedureExecution"
  def title(r), do: "Started (#{r.triggered_by || "manual"})"
  def status(_), do: "running"
  def severity(_), do: nil
end
