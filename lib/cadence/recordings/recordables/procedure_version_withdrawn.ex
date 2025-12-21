defmodule Cadence.Recordings.Recordables.ProcedureVersionWithdrawn do
  @moduledoc """
  Recordable for when a procedure version is withdrawn from review.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_version_withdrawns" do
    field :reason, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:reason])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureVersionWithdrawn do
  def recording_type(_), do: "ProcedureVersionWithdrawn"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(r), do: r.reason || "Withdrawn"
  def status(_), do: "draft"
  def severity(_), do: nil
end
