defmodule Cadence.Recordings.Recordables.ProcedureVersionDeprecated do
  @moduledoc """
  Recordable for when a procedure version is deprecated.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_version_deprecateds" do
    field :reason, :string
    field :replacement_version_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:reason, :replacement_version_id])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureVersionDeprecated do
  def recording_type(_), do: "ProcedureVersionDeprecated"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(r), do: r.reason || "Deprecated"
  def status(_), do: "deprecated"
  def severity(_), do: nil
end
