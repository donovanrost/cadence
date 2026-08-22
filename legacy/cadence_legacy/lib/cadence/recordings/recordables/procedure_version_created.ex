defmodule Cadence.Recordings.Recordables.ProcedureVersionCreated do
  @moduledoc """
  Recordable for when a new procedure version is created.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_version_createds" do
    field :procedure_id, :binary_id
    field :version_number, :integer
    field :source_code, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:procedure_id]
  @optional_fields [:version_number, :source_code]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureVersionCreated do
  def recording_type(_), do: "ProcedureVersionCreated"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(r), do: "Version #{r.version_number || "draft"} created"
  def status(_), do: "draft"
  def severity(_), do: nil
end
